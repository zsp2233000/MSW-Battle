-- server_main after formation_handoff_fixture_runtime_probe.lua. Mutates only hf2601.
local previousTimeout = _FormationService.SaveTimeoutSeconds
local ok, detail = pcall(function()
    local player
    for _, user in ipairs(_UserService.UserEntities.Values) do
        if user.PlayerComponent.ProfileCode == 'hf2601' then player = user break end
    end
    assert(isvalid(player), 'dedicated player joined')
    local userId, profile = player.PlayerComponent.UserId, player.PlayerComponent.ProfileCode
    local function fresh()
        local ticket = _FormationHandoff:Read(profile)
        assert(ticket ~= nil and (ticket.data == nil or ticket.data.state == 'CANCELLED' or ticket.data.state == 'RETURNED'), 'no live ticket')
        assert(not _FormationHandoff:IsLockedForUser(userId), 'terminal ticket is not an edit lock')
        return ticket
    end
    local function reserve()
        local ticket = fresh()
        local attempt, requestId = _UtilLogic:NewGuid(), _UtilLogic:NewGuid()
        assert(_FormationHandoff:Reserve(userId, ticket, { attempt = attempt, requestId = requestId, source = _WorldInstanceService.WorldInstanceId, adapter = 'local' }), 'reserve confirmed active formation')
        assert(ticket.data.state == 'QUEUED' and ticket.data.attempt == attempt and ticket.data.transfer == nil, 'reservation exposes metadata only')
        assert(_FormationHandoff:IsLockedForUser(userId), 'reservation locks editing before its first storage wait returns')
        return ticket
    end
    local function close(ticket, terminal)
        assert(_FormationHandoff:Close(userId, ticket, terminal), 'cleanup confirmed')
        assert(not _FormationHandoff:IsLockedForUser(userId), 'confirmed terminal record releases the lock')
    end

    local queued = reserve()
    local frozen = _FormationHandoff:Roster(queued.id)[1].x
    local renewed = _UtilLogic:NewGuid()
    assert(_FormationHandoff:Renew(userId, queued, renewed), 'renew the same frozen attempt')
    assert(queued.data.state == 'QUEUED' and queued.data.requestId == renewed and queued.data.attempt == queued.id, 'renewal changes only the queue request')
    assert(_FormationHandoff:Roster(queued.id)[1].x == frozen, 'renewal keeps the queue-time roster')
    assert(not _FormationHandoff:Close(userId, queued, 'RETURNED'), 'a queue cannot be closed as returned')
    close(queued, 'CANCELLED')
    log('[VRF][HandoffLifecycle] PASS renewal retains the fixed roster and confirmed cancellation unlocks')

    local committing = reserve()
    local matched = { key = 'local-lifecycle', home = profile, away = 'hf2602', homeAttempt = committing.data.requestId, awayAttempt = 'peer', homeSource = committing.data.source, awaySource = 'other', differentSources = false }
    assert(_FormationHandoff:BeginSave(userId, committing, function() return true end), 'commit follows the matched save mark')
    assert(_FormationHandoff:Seal(userId, committing, function() return true end), 'commit follows seal')
    _FormationService.SaveTimeoutSeconds = 1
    _FormationStorage:ConfigureMakerFaults(0, 0, 2.5)
    local barrierSeen = false
    _TimerService:SetTimerOnce(function()
        -- A caller snapshot may lag across script calls; the authoritative cancellation policy must already be closed.
        barrierSeen = not _FormationHandoff:CanCancel(committing)
    end, 0.1)
    assert(not _FormationHandoff:Commit(userId, committing, matched, 900), 'a timed-out commit stays unconfirmed')
    assert(barrierSeen, 'the commit intent cannot be cancelled before its acknowledgement')
    assert(committing.data.state == 'COMMITTING' and _FormationHandoff:IsLockedForUser(userId), 'the commit boundary remains locked')
    assert(not _FormationHandoff:Close(userId, committing, 'CANCELLED'), 'an unconfirmed commit cannot return to a cancellable queue')
    assert(not _FormationHandoff:Reconcile(userId, committing), 'old bytes do not accept the commit')
    _FormationStorage:ConfigureMakerFaults(0, 0, 0)
    _FormationService.SaveTimeoutSeconds = previousTimeout
    wait(3)
    assert(_FormationHandoff:Reconcile(userId, committing), 'late durable bytes are accepted before another commit')
    if committing.data.state ~= 'TRANSFER' then
        assert(_FormationHandoff:Commit(userId, committing, matched, 900), 'reconciled commit completes the handoff')
    end
    assert(committing.data.state == 'TRANSFER' and committing.data.matchKey == matched.key and committing.data.warpIssued ~= true, 'commit reaches transfer without issuing warp')
    assert(_FormationHandoff:Roster(committing.id)[1].x == frozen, 'commit keeps the queue-time roster')
    log('[VRF][HandoffLifecycle] PASS failed commit retries without cancellation or movement')

    _FormationStorage:ConfigureMakerFaults(0, 1, 0)
    assert(not _FormationHandoff:Admit(userId, committing), 'unconfirmed admission does not authorize movement')
    assert(committing.data.state == 'TRANSFER' and _FormationHandoff:IsLockedForUser(userId), 'failed admission retains transfer')
    _FormationStorage:ConfigureMakerFaults(0, 0, 0)
    assert(_FormationHandoff:Admit(userId, committing), 'admission retry confirms the room')
    assert(committing.data.state == 'IN_ROOM', 'admission records the room without moving the player')
    assert(_FormationHandoff:WithdrawAdmission(userId, committing), 'an explicit failed move returns to transfer')
    assert(committing.data.state == 'TRANSFER', 'withdrawal is the only path back from the room')
    assert(_FormationHandoff:Admit(userId, committing), 'room entry can be recorded again')
    log('[VRF][HandoffLifecycle] PASS admission failure and withdrawal stay inside the handoff')

    _FormationStorage:ConfigureMakerFaults(0, 1, 0)
    assert(not _FormationHandoff:BeginReturn(userId, committing), 'an unconfirmed return cannot leave the room')
    assert(committing.data.state == 'IN_ROOM', 'explicit return failure keeps the last confirmed room')
    _FormationStorage:ConfigureMakerFaults(0, 0, 0)
    assert(_FormationHandoff:BeginReturn(userId, committing), 'return retry is confirmed before movement')
    assert(committing.data.state == 'RETURNING', 'return owns the next lifecycle step')
    close(committing, 'RETURNED')
    log('[VRF][HandoffLifecycle] PASS return failure retains the room and a confirmed return can close')

    local old = reserve()
    _FormationService.SaveTimeoutSeconds = 1
    _FormationStorage:ConfigureMakerFaults(0, 0, 2.5)
    assert(not _FormationHandoff:FailQueue(userId, old), 'a timed-out queue failure stays unconfirmed')
    _FormationStorage:ConfigureMakerFaults(0, 0, 0)
    _FormationService.SaveTimeoutSeconds = previousTimeout
    local current = _FormationHandoff:Read(profile)
    assert(current ~= nil and _FormationHandoff:Close(userId, current, 'CANCELLED'), 'the late queue write is reconciled by cancellation')
    local newer = reserve()
    assert(not _FormationHandoff:FailQueue(userId, old), 'an old handle cannot change the new ticket')
    wait(3)
    local reloaded = _FormationHandoff:Read(profile)
    assert(reloaded ~= nil and reloaded.id == newer.id and reloaded.data.state == 'QUEUED' and _FormationHandoff:IsLockedForUser(userId), 'the late callback cannot overwrite or unlock the new reservation')
    close(reloaded, 'CANCELLED')
    log('[VRF][HandoffLifecycle] PASS uncertain queue failure and old callbacks stay fenced')
    local recoverable = reserve()
    _FormationStorage:ConfigureMakerFaults(1, 0, 0)
    assert(_FormationHandoff:OpenForUser(userId) == nil, 'failed own read cannot claim a fresh ticket')
    assert(_FormationHandoff:IsLocked(profile), 'failed read retains the edit lock')
    close(recoverable, 'CANCELLED')
    assert(not _FormationHandoff:IsLockedForUser(userId), 'confirmed close clears the failed-read lock')
    log('[VRF][HandoffLifecycle] PASS a confirmed close releases a prior failed-read lock')

end)
_FormationService.SaveTimeoutSeconds = previousTimeout
_FormationStorage:ConfigureMakerFaults(0, 0, 0)
if not ok then log('[VRF][HandoffLifecycle] FAIL '..tostring(detail)) end
