-- server_main, one connected player in formationlobby. Owns unique storage keys and restores them afterwards.
-- A reconnected player's cancel overlaps the disconnect cleanup's native cancellation; neither may strand the lock.
local previousKey, previousTransfer = _FormationService.StorageKey, _FormationHandoff.StorageKey
local userId, previousSlot
local function await(predicate)
    for _ = 1, 150 do if predicate() then return true end wait(0.1) end
    return false
end
local ok, detail = pcall(function()
    local users = _UserService.UserEntities.Values
    assert(#users == 1 and users[1].CurrentMapName == 'formationlobby', 'one lobby player')
    userId = users[1].PlayerComponent.UserId
    assert(not _MatchProbe:IsFormationLocked(userId), 'no live matchmaking attempt')
    _FormationService.StorageKey = 'Reconnect52_' .. _UtilLogic:NewGuid()
    _FormationHandoff.StorageKey = 'Reconnect52Transfer_' .. _UtilLogic:NewGuid()
    local session = _FormationService:GetSession(userId)
    previousSlot = session.editSlot
    session.editSlot = 1
    _FormationService:Load(session)
    assert(await(function() return session.loadState == 'NEW' and not session.pending end), 'isolated fixture loaded')
    _FormationService:SaveForUser(userId, {{monsterId='monster_tank',x=-5,y=0}}, 1, 0, _UtilLogic:NewGuid())
    assert(await(function() return session.loadState == 'READY' and not session.pending end), 'fixture saved')
    _FormationService:ActivateForUser(userId, 1, session.saved.slots['1'].revision)
    assert(await(function() return session.saved.activeSlot == 1 and not session.pending end), 'fixture active')
    _MatchProbe:QueueForUser(userId)
    assert(_MatchProbe:IsFormationLocked(userId), 'queued')
    _MatchProbe:ConfigureMakerCancelFaults(0, 2)
    _TimerService:SetTimerOnce(function() _MatchProbe:Depart(userId) end, 0.1)
    wait(0.5)
    -- Same effect as HandleUserReconnectEvent, while Depart is still waiting on the cancellation reply.
    _MatchProbe._T.offline[userId] = nil
    _MatchProbe:CancelForUser(userId)
    assert(await(function() return not _MatchProbe:IsFormationLocked(userId) end), 'overlapping cancel strands the formation lock')
    log('[VRF][Reconnect52] PASS overlapping cancel leaves no stuck lock')
end)
_MatchProbe:ConfigureMakerCancelFaults(0, 0)
if not ok then log('[VRF][Reconnect52] FAIL ' .. tostring(detail)) end
if userId ~= nil then _MatchProbe._T.busy[userId] = nil _MatchProbe._T.records[userId] = nil end
_FormationService.StorageKey, _FormationHandoff.StorageKey = previousKey, previousTransfer
local session = userId ~= nil and _FormationService:GetSession(userId) or nil
if session ~= nil then
    session.editSlot = previousSlot or session.editSlot
    _FormationService:Load(session)
    await(function() return session.loadState == 'READY' or session.loadState == 'NEW' end)
    log('[VRF][Reconnect52] original session reloaded state=' .. session.loadState)
end
