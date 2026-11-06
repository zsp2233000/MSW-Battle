-- server_main after formation_handoff_fixture_runtime_probe.lua. Mutates only hf2601.
local previousTimeout = _FormationService.SaveTimeoutSeconds
local ok, detail = pcall(function()
    local player
    for _, user in ipairs(_UserService.UserEntities.Values) do
        if user.PlayerComponent.ProfileCode == 'hf2601' then player = user break end
    end
    assert(isvalid(player), 'dedicated player joined')
    local userId, profile = player.PlayerComponent.UserId, player.PlayerComponent.ProfileCode
    local function reserve()
        local ticket = _FormationHandoff:Read(profile)
        assert(ticket ~= nil, 'ticket read')
        assert(_FormationHandoff:Reserve(userId, ticket, {attempt=_UtilLogic:NewGuid(),requestId=_UtilLogic:NewGuid(),source=_WorldInstanceService.WorldInstanceId,adapter='local'}), 'fixture reservation')
        return ticket
    end
    local session = _FormationService:GetSession(userId)
    local ticket = reserve()
    local original = _FormationHandoff:Roster(ticket.id)[1].x
    assert(_FormationHandoff:BeginSave(userId, ticket, function() return true end), 'seal follows the matched save mark')
    assert(_FormationHandoff:Seal(userId, ticket, function() return true end), 'sealing needs no save')
    assert(_FormationHandoff:Roster(ticket.id)[1].x == original, 'the fixed roster is unchanged')
    local matched = {key='local-failure',home=profile,away='hf2602',homeAttempt=ticket.data.requestId,awayAttempt='peer',homeSource=ticket.data.source,awaySource='other',differentSources=false}
    assert(_FormationHandoff:Commit(userId, ticket, matched, 900), 'handoff confirmed')
    assert(_FormationHandoff:BeginReturn(userId, ticket), 'return confirmed')
    assert(_FormationHandoff:IsLockedForUser(userId), 'locked while the transfer is out')
    assert(_FormationHandoff:Restore(userId, ticket.id), 'confirmed content restored')
    assert(_FormationHandoff:IsLockedForUser(userId), 'restoring keeps the lock until cleanup is durable')
    local epoch = session.writeEpoch
    assert(_FormationHandoff:Restore(userId, ticket.id) and session.writeEpoch == epoch, 'a second restore of the same ticket is acknowledged without applying it again')
    assert(_FormationHandoff:Restore(userId, ticket.id), 'restore retry acknowledged while return is still open')
    _FormationService.SaveTimeoutSeconds = 1
    _FormationStorage:ConfigureMakerFaults(0, 0, 2.5)
    assert(not _FormationHandoff:Close(userId, ticket, 'RETURNED'), 'timed-out cleanup stays unconfirmed')
    assert(_FormationHandoff:IsLockedForUser(userId), 'unconfirmed cleanup keeps the lock')
    assert(not _FormationHandoff:Reconcile(userId, ticket), 'old bytes do not finish cleanup')
    _FormationStorage:ConfigureMakerFaults(0, 0, 0)
    _FormationService.SaveTimeoutSeconds = previousTimeout
    wait(3)
    assert(_FormationHandoff:Reconcile(userId, ticket) or _FormationHandoff:Close(userId, ticket, 'RETURNED'), 'late cleanup is reconciled before retry')
    if _FormationHandoff:IsLockedForUser(userId) then
        assert(_FormationHandoff:Close(userId, ticket, 'RETURNED'), 'cleanup retry confirmed')
    end
    log('[VRF][HandoffFailures] PASS cleanup retries restore confirmed content and close once')

    local old = reserve()
    _FormationService.SaveTimeoutSeconds = 1
    _FormationStorage:ConfigureMakerFaults(0, 0, 2.5)
    assert(not _FormationHandoff:FailQueue(userId, old), 'handoff acknowledgement wait is bounded')
    _FormationStorage:ConfigureMakerFaults(0, 0, 0)
    _FormationService.SaveTimeoutSeconds = previousTimeout
    local current = _FormationHandoff:Read(profile)
    assert(current ~= nil and _FormationHandoff:Close(userId, current, 'CANCELLED'), 'cancel the uncertain older operation')
    local newer = reserve()
    assert(_FormationHandoff:BeginSave(userId, newer, function() return true end), 'new reservation follows the save mark')
    assert(_FormationHandoff:Seal(userId, newer, function() return true end), 'new reservation sealed')
    assert(_FormationHandoff:IsLockedForUser(userId), 'old cancellation cannot release the new lock')
    wait(3)
    assert(not _FormationHandoff:FailQueue(userId, old), 'stale handle rejected')
    local reloaded = _FormationHandoff:Read(profile)
    assert(reloaded ~= nil and reloaded.id == newer.id, 'late old write cannot overwrite the new reservation')
    assert(_FormationHandoff:Close(userId, reloaded, 'CANCELLED'), 'new fixture closed')
    log('[VRF][HandoffFailures] PASS bounded transfer wait; late old write and stale unlock fenced')
end)
_FormationService.SaveTimeoutSeconds = previousTimeout
_FormationStorage:ConfigureMakerSaveResponse('', 0)
_FormationStorage:ConfigureMakerFaults(0, 0, 0)
if not ok then log('[VRF][HandoffFailures] FAIL '..tostring(detail)) end
