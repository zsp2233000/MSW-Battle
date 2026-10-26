-- server_main, with a dedicated Maker virtual player whose saved active formation is ready.
local ok, detail = pcall(function()
    assert(_FormationHandoff ~= nil, 'FormationHandoff interface is required')
    local player
    for _, user in ipairs(_UserService.UserEntities.Values) do
        if user.PlayerComponent.ProfileCode == 'hf2601' then player = user break end
    end
    assert(isvalid(player), 'requires the dedicated hf2601 virtual player')
    local userId, profile = player.PlayerComponent.UserId, player.PlayerComponent.ProfileCode
    local ticket = _FormationHandoff:Read(profile)
    assert(ticket ~= nil and (ticket.data == nil or ticket.data.state == 'CANCELLED' or ticket.data.state == 'RETURNED'), 'no unfinished fixture match')
    ticket.data = {schema=1, profile=profile, attempt=_UtilLogic:NewGuid(), requestId=_UtilLogic:NewGuid(), source=_WorldInstanceService.WorldInstanceId, adapter='local', state='QUEUED', started=DateTime.UtcNow.Elapsed, expires=0, matchKey=''}
    assert(_FormationHandoff:Reserve(userId, ticket), 'reserve the confirmed active formation')
    assert(ticket.data.transfer == nil and ticket.raw == nil, 'ticket exposes metadata only')
    local original = _FormationHandoff:Roster(ticket.id)
    assert(original ~= nil and #original == 1 and original[1].x == -3.25, 'known queue-time formation')
    original[1].x = -7.25
    assert(_FormationHandoff:Roster(ticket.id)[1].x == -3.25, 'rosters are detached')
    local session = _FormationService:GetSession(userId)
    local slot = session.editSlot
    _FormationService:UpdateDraftForUser(userId, {{monsterId='monster_tank',x=-4.25,y=-1.25}}, session.drafts[tostring(slot)].version, slot)
    assert(_FormationHandoff:Seal(userId, ticket, function() return true end), 'seal the latest draft')
    assert(_FormationHandoff:Roster(ticket.id)[1].x == -3.25, 'sealing never replaces the queue-time formation')
    assert(session.drafts[tostring(slot)].savedVersion == session.drafts[tostring(slot)].version, 'automatic save confirmed')
    assert(_FormationHandoff:Close(userId, ticket, 'CANCELLED'), 'close the fixture reservation')
    assert(_FormationHandoff:Roster(ticket.id) == nil, 'closed tickets cannot supply a roster')
    log('[VRF][HandoffReserve] PASS metadata-only ticket; immutable detached roster; automatic save; close')
end)
if not ok then log('[VRF][HandoffReserve] FAIL '..tostring(detail)) end
