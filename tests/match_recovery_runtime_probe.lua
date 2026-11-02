-- server_main, one connected player in formationlobby. Each run owns unique storage keys.
-- Run RESERVE and CANCEL separately; do not read the handoff between its late write and cancellation.
local MODE = 'RESERVE'
local previousKey, previousTransfer = _FormationService.StorageKey, _FormationHandoff.StorageKey
local previousTimeout = _FormationService.SaveTimeoutSeconds
local userId, previousSlot
local function await(predicate)
    for _ = 1, 150 do if predicate() then return true end wait(0.1) end
    return false
end
local ok, detail = pcall(function()
    local users = _UserService.UserEntities.Values
    assert(#users == 1 and users[1].CurrentMapName == 'formationlobby', 'one lobby player')
    userId = users[1].PlayerComponent.UserId
    assert(not _MatchFlow:IsFormationLocked(userId), 'no live matchmaking attempt')
    _FormationService.StorageKey = 'Recovery52_' .. _UtilLogic:NewGuid()
    _FormationHandoff.StorageKey = 'Recovery52Transfer_' .. _UtilLogic:NewGuid()
    local session = _FormationService:GetSession(userId)
    previousSlot = session.editSlot
    session.editSlot = 1
    _FormationService:Load(session)
    assert(await(function() return session.loadState == 'NEW' and not session.pending end), 'isolated fixture loaded')
    _FormationService:SaveForUser(userId, {{monsterId='monster_tank',x=-5,y=0}}, 1, 0, _UtilLogic:NewGuid())
    assert(await(function() return session.loadState == 'READY' and not session.pending end), 'fixture saved')
    _FormationService:ActivateForUser(userId, 1, session.saved.slots['1'].revision)
    assert(await(function() return session.saved.activeSlot == 1 and not session.pending end), 'fixture active')

    _FormationService.SaveTimeoutSeconds = 1
    if MODE == 'RESERVE' then _FormationStorage:ConfigureMakerFaults(0, 0, 2.5) end
    _MatchFlow:QueueForUser(userId)
    assert(_MatchFlow:IsFormationLocked(userId), 'reservation keeps editing locked')
    if MODE == 'CANCEL' then
        _FormationStorage:ConfigureMakerFaults(0, 0, 2.5)
        _MatchFlow:CancelForUser(userId)
        assert(_MatchFlow:IsFormationLocked(userId), 'unconfirmed cancellation keeps editing locked')
    end
    _FormationStorage:ConfigureMakerFaults(0, 0, 0)
    wait(3)
    -- Retry exactly the visible cancel command; no status/relogin/read is allowed to repair the cache first.
    _MatchFlow:CancelForUser(userId)
    assert(not _MatchFlow:IsFormationLocked(userId), 'cancellation retry unlocks after the late durable write')
    assert(session.saved.slots['1'].revision == 1 and session.saved.activeSlot == 1, 'saved formation unchanged')
end)
_FormationStorage:ConfigureMakerFaults(0, 0, 0)
_FormationService.SaveTimeoutSeconds = previousTimeout
if userId ~= nil and _MatchFlow:IsFormationLocked(userId) then _MatchFlow:Recover(userId) end
_FormationService.StorageKey, _FormationHandoff.StorageKey = previousKey, previousTransfer
local session = userId ~= nil and _FormationService:GetSession(userId) or nil
if session ~= nil then
    session.editSlot = previousSlot or session.editSlot
    _FormationService:Load(session)
    assert(await(function() return session.loadState == 'READY' or session.loadState == 'NEW' end), 'original session restored')
end
log(ok and ('[VRF][Recovery52] PASS late ' .. MODE .. '; cancellation retry unlocks; saved version unchanged')
    or ('[VRF][Recovery52] FAIL late ' .. MODE .. ' ' .. tostring(detail)))
