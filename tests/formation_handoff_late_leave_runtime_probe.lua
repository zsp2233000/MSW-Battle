-- server_main after the dedicated hf2601 player has returned and restored its session.
local ok, detail = pcall(function()
    local player
    for _, user in ipairs(_UserService.UserEntities.Values) do
        if user.PlayerComponent.ProfileCode == 'hf2601' then player = user break end
    end
    assert(isvalid(player) and player.CurrentMapName == 'formationlobby', 'dedicated player returned')
    local userId = player.PlayerComponent.UserId
    local session = _FormationService:GetSession(userId)
    assert(session ~= nil and session.initialized, 'restored session is ready')
    local sessionId, revision = session.sessionId, session.saved.revision
    local slot, version = session.editSlot, session.drafts[tostring(session.editSlot)].version
    local draft = _FormationSchema:CopyUnits(session.drafts[tostring(slot)].units)
    local leave = UserLeaveEvent()
    leave.UserId = userId
    _FormationService:HandleUserLeaveEvent(leave)
    wait(0.2)
    local restored = _FormationService:GetSession(userId)
    assert(restored ~= nil and restored.initialized and restored.sessionId == sessionId, 'late leave retains the connected restored session')
    assert(restored.saved.revision == revision and restored.editSlot == slot, 'confirmed save and editor selection retained')
    assert(restored.drafts[tostring(slot)].version == version and _FormationSchema:SameUnits(restored.drafts[tostring(slot)].units, draft), 'draft contents and version retained')
    log('[VRF][HandoffLateLeave] PASS delayed leave cannot clear the connected restored session')
end)
if not ok then log('[VRF][HandoffLateLeave] FAIL '..tostring(detail)) end
