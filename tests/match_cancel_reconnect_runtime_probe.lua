-- server_main, one connected player in formationlobby. Owns unique storage keys and restores them afterwards.
-- Reconnecting during disconnect cleanup must not strand the lock, unlock an unconfirmed queue, or leave stale state.
-- Then in client, log _MatchFlowInput.Snapshot.state, Busy and AllowsFormationActions(): a settled run shows IDLE, false, true.
local previousKey, previousTransfer = _FormationService.StorageKey, _FormationHandoff.StorageKey
local userId, previousSlot
local function await(predicate, tries)
    for _ = 1, tries or 150 do if predicate() then return true end wait(0.1) end
    return false
end
local function reconnect()
    local event = UserReconnectEvent()
    event.UserId = userId
    _UserService:SendEvent(event)
end
local ok, detail = pcall(function()
    local users = _UserService.UserEntities.Values
    assert(#users == 1 and users[1].CurrentMapName == 'formationlobby', 'one lobby player')
    userId = users[1].PlayerComponent.UserId
    local profile = users[1].PlayerComponent.ProfileCode
    assert(not _MatchFlow:IsFormationLocked(userId), 'no live matchmaking attempt')
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

    _MatchFlow:QueueForUser(userId)
    assert(_MatchFlow:IsFormationLocked(userId), 'queued')
    _MatchFlow:ConfigureMakerCancelFaults(0, 2)
    _TimerService:SetTimerOnce(function() _MatchFlow:Depart(userId) end, 0.1)
    wait(0.5)
    reconnect()
    assert(_MatchFlow:Player(userId) ~= nil, 'reconnect event restores availability')
    _MatchFlow:CancelForUser(userId)
    assert(await(function() return not _MatchFlow:IsFormationLocked(userId) end), 'overlapping cancel strands the formation lock')
    log('[VRF][Reconnect52] PASS OVERLAP cleanup finishes; no stuck lock')
    wait(1) -- Let the post-cleanup recovery read settle before the next case.

    -- Server-side cancel with no live record reads the durable ticket and must still release its own lock.
    _MatchFlow._T.records[userId] = nil
    _MatchFlow:CancelForUser(userId)
    assert(_MatchFlow._T.busy[userId] == nil, 'cancel of a durable-only ticket strands busy')
    log('[VRF][Reconnect52] PASS DURABLE cancel releases busy')

    -- Reconnected while the failing cancellation is in flight: the queue stays live and locked, and a retry can finish it.
    _MatchFlow:ConfigureMakerCancelFaults(1, 2)
    _MatchFlow:QueueForUser(userId)
    assert(_MatchFlow:IsFormationLocked(userId), 'queued again')
    _TimerService:SetTimerOnce(function() _MatchFlow:Depart(userId) end, 0.1)
    wait(0.5)
    reconnect()
    wait(2.5)
    assert(_MatchFlow:IsFormationLocked(userId) and _MatchFlow:StateForUser(userId) == 'QUEUED', 'failed cleanup keeps an online player locked on the live queue')
    _MatchFlow:ConfigureMakerCancelFaults(0, 0)
    _MatchFlow:CancelForUser(userId)
    assert(not _MatchFlow:IsFormationLocked(userId), 'retry after failed cleanup unlocks')
    log('[VRF][Reconnect52] PASS FAILED_ONLINE queue retained; retry confirmed')

    -- Failed while still offline: the ticket stays locked until the reconnect resolves it.
    _MatchFlow:ConfigureMakerCancelFaults(1, 0)
    _MatchFlow:QueueForUser(userId)
    _MatchFlow:Depart(userId)
    assert(_MatchFlow:IsFormationLocked(userId), 'failed offline cleanup keeps the ticket locked')
    reconnect()
    -- The Maker adapter closes its stale queue here; the native adapter keeps the ticket for a visible cancel.
    assert(await(function()
        local ticket = _FormationHandoff:Read(profile)
        return ticket ~= nil and ticket.data ~= nil and ticket.data.state == 'CANCELLED' and not _MatchFlow:IsFormationLocked(userId)
    end, 60), 'reconnect resolves the retained ticket')
    log('[VRF][Reconnect52] PASS FAILED_OFFLINE locked until reconnect recovery')
end)
_MatchFlow:ConfigureMakerCancelFaults(0, 0)
if not ok then log('[VRF][Reconnect52] FAIL ' .. tostring(detail)) end
if userId ~= nil then _MatchFlow._T.offline[userId] = nil _MatchFlow._T.busy[userId] = nil _MatchFlow._T.records[userId] = nil end
_FormationService.StorageKey, _FormationHandoff.StorageKey = previousKey, previousTransfer
local session = userId ~= nil and _FormationService:GetSession(userId) or nil
if session ~= nil then
    session.editSlot = previousSlot or session.editSlot
    _FormationService:Load(session)
    await(function() return session.loadState == 'READY' or session.loadState == 'NEW' end)
    log('[VRF][Reconnect52] original session reloaded state=' .. session.loadState)
end
