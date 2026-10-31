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
    local revision = session.saved.slots[tostring(session.editSlot)].revision
    assert(_FormationHandoff:Seal(userId, ticket, function() return true end), 'seal confirmed content')
    assert(_FormationHandoff:Roster(ticket.id)[1].x == -3.25, 'sealing never replaces the queue-time formation')
    assert(session.saved.slots[tostring(session.editSlot)].revision == revision, 'matching writes nothing')
    local capture = _FormationHandoff:Capture(userId)
    assert(capture ~= nil and capture.saved ~= nil and capture.drafts == nil and capture.autoSaveMessage == nil, 'the handoff carries confirmed content only')
    assert(_FormationHandoff:Close(userId, ticket, 'CANCELLED'), 'close the fixture reservation')
    assert(_FormationHandoff:Roster(ticket.id) == nil, 'closed tickets cannot supply a roster')
    log('[VRF][HandoffReserve] PASS metadata-only ticket; immutable detached roster; no automatic save; no unsaved content in the handoff; close')
end)
if not ok then log('[VRF][HandoffReserve] FAIL '..tostring(detail)) end
