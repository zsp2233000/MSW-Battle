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
    local function edit(x)
        local session = _FormationService:GetSession(userId)
        local slot = session.editSlot
        _FormationService:UpdateDraftForUser(userId, {{monsterId='monster_tank',x=x,y=-1.25}}, session.drafts[tostring(slot)].version, slot)
        return session
    end
    local ticket = reserve()
    local original = _FormationHandoff:Roster(ticket.id)[1].x
    local session = edit(-5.25)
    _FormationStorage:ConfigureMakerSaveResponse('FAIL', 0)
    assert(_FormationHandoff:Seal(userId, ticket, function() return true end), 'save failure does not block sealing')
    _FormationStorage:ConfigureMakerSaveResponse('', 0)
    assert(_FormationHandoff:Roster(ticket.id)[1].x == original, 'save failure retains the fixed roster')
    assert(string.find(ticket.notice, '失敗', 1, true), 'failure notice is not success')
    ticket.data.state = 'TRANSFER'
    assert(_FormationHandoff:Store(ticket), 'handoff confirmed')
    ticket.data.state = 'RETURNING'
    assert(_FormationHandoff:Store(ticket), 'return confirmed')
    assert(_FormationHandoff:Restore(userId, ticket.id), 'draft restored')
    session = edit(-6.25)
    _FormationStorage:ConfigureMakerFaults(0, 1, 0)
    assert(not _FormationHandoff:Close(userId, ticket, 'RETURNED'), 'cleanup failure surfaced')
    assert(_FormationHandoff:Restore(userId, ticket.id), 'restore retry acknowledged')
    assert(session.drafts[tostring(session.editSlot)].units[1].x == -6.25, 'cleanup retry preserves later edits')
    assert(_FormationHandoff:Close(userId, ticket, 'RETURNED'), 'cleanup retry confirmed')
    log('[VRF][HandoffFailures] PASS save failure continues; cleanup retries preserve newer drafts')
    _FormationService:Load(session)
    for attempt = 1, 200 do if session.loadState == 'READY' and not session.pending then break end wait(0.1) end
    assert(session.loadState == 'READY', 'failed save reconciled before the next match')

    ticket = reserve()
    _FormationService.SaveTimeoutSeconds = 1
    _FormationStorage:ConfigureMakerSaveResponse('LATE', 2)
    assert(_FormationHandoff:Seal(userId, ticket, function() return true end), 'save timeout still seals')
    assert(string.find(ticket.notice, '逾時', 1, true), 'timeout reported honestly')
    local savedRevision = session.saved.revision
    wait(2.5)
    assert(session.saved.revision == savedRevision and session.transferLocked == ticket.id, 'late acknowledgement cannot mutate sealed state')
    _FormationStorage:ConfigureMakerSaveResponse('', 0)
    _FormationService.SaveTimeoutSeconds = previousTimeout
    assert(_FormationHandoff:Close(userId, ticket, 'CANCELLED'), 'timeout fixture closed')
    _FormationService:Load(session)
    for attempt = 1, 200 do if session.loadState == 'READY' and not session.pending then break end wait(0.1) end
    assert(session.loadState == 'READY', 'ambiguous save reconciled')
    log('[VRF][HandoffFailures] PASS save timeout retains drafts; late acknowledgement fenced')

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
