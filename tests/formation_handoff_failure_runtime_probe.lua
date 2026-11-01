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
        ticket.data = {schema=1,profile=profile,attempt=_UtilLogic:NewGuid(),requestId=_UtilLogic:NewGuid(),source=_WorldInstanceService.WorldInstanceId,adapter='local',state='QUEUED',started=DateTime.UtcNow.Elapsed,expires=0,matchKey=''}
        assert(_FormationHandoff:Reserve(userId, ticket), 'fixture reservation')
        return ticket
    end
    local session = _FormationService:GetSession(userId)
    local ticket = reserve()
    local original = _FormationHandoff:Roster(ticket.id)[1].x
    assert(_FormationHandoff:Seal(userId, ticket, function() return true end), 'sealing needs no save')
    assert(_FormationHandoff:Roster(ticket.id)[1].x == original, 'the fixed roster is unchanged')
    ticket.data.state = 'TRANSFER'
    assert(_FormationHandoff:Store(ticket), 'handoff confirmed')
    ticket.data.state = 'RETURNING'
    assert(_FormationHandoff:Store(ticket), 'return confirmed')
    assert(session.transferLocked == ticket.id, 'locked while the transfer is out')
    assert(_FormationHandoff:Restore(userId, ticket.id), 'confirmed content restored')
    assert(not session.transferLocked, 'restoring releases the lock')
    local epoch = session.writeEpoch
    assert(_FormationHandoff:Restore(userId, ticket.id) and session.writeEpoch == epoch, 'a second restore of the same ticket is acknowledged without applying it again')
    _FormationStorage:ConfigureMakerFaults(0, 1, 0)
    assert(not _FormationHandoff:Close(userId, ticket, 'RETURNED'), 'cleanup failure surfaced')
    assert(_FormationHandoff:Restore(userId, ticket.id), 'restore retry acknowledged')
    assert(_FormationHandoff:Close(userId, ticket, 'RETURNED'), 'cleanup retry confirmed')
    log('[VRF][HandoffFailures] PASS cleanup retries restore confirmed content and close once')

    local old = reserve()
    _FormationService.SaveTimeoutSeconds = 1
    _FormationStorage:ConfigureMakerFaults(0, 0, 2.5)
    old.data.state = 'RENEWING'
    assert(not _FormationHandoff:Store(old), 'handoff acknowledgement wait is bounded')
    _FormationStorage:ConfigureMakerFaults(0, 0, 0)
    _FormationService.SaveTimeoutSeconds = previousTimeout
    local current = _FormationHandoff:Read(profile)
    assert(current ~= nil and _FormationHandoff:Close(userId, current, 'CANCELLED'), 'cancel the uncertain older operation')
    local newer = reserve()
    assert(_FormationHandoff:Seal(userId, newer, function() return true end), 'new reservation sealed')
    _FormationHandoff:Release(userId, old.id)
    assert(session.transferLocked == newer.id, 'old cancellation cannot release the new lock')
    wait(3)
    assert(not _FormationHandoff:Store(old), 'stale handle rejected')
    local reloaded = _FormationHandoff:Read(profile)
    assert(reloaded ~= nil and reloaded.id == newer.id, 'late old write cannot overwrite the new reservation')
    assert(_FormationHandoff:Close(userId, reloaded, 'CANCELLED'), 'new fixture closed')
    log('[VRF][HandoffFailures] PASS bounded transfer wait; late old write and stale unlock fenced')
end)
_FormationService.SaveTimeoutSeconds = previousTimeout
_FormationStorage:ConfigureMakerSaveResponse('', 0)
_FormationStorage:ConfigureMakerFaults(0, 0, 0)
if not ok then log('[VRF][HandoffFailures] FAIL '..tostring(detail)) end
