-- Run in server_main with one idle lobby player. All fixtures use disposable keys.
local function await(predicate)
    for _ = 1, 400 do if predicate() then return true end wait(0.05) end
    return false
end
local user = _UserService.UserEntities.Values[1]
local userId, profile = user.PlayerComponent.UserId, user.PlayerComponent.ProfileCode
local storage = _DataStorageService:GetUserDataStorage(profile)
local originalFormation, originalLevels, originalTransfer = _FormationService.StorageKey, _MonsterLevelStorage.StorageKey, _FormationHandoff.StorageKey
local suffix = _UtilLogic:NewGuid():sub(1, 8)
local formationKey, levelKey, transferKey = 'I67F_'..suffix, 'I67L_'..suffix, 'I67T_'..suffix
local ok, detail = pcall(function()
    assert(user.CurrentMapName == 'formationlobby' and not _MatchFlow:IsFormationLocked(userId), 'idle lobby required')
    _FormationService.StorageKey, _MonsterLevelStorage.StorageKey, _FormationHandoff.StorageKey = formationKey, levelKey, transferKey
    local session = _FormationService:GetSession(userId)
    _FormationService:Load(session)
    _FormationService:LoadLevels(session)
    assert(await(function() return session.initialized and session.loadState == 'NEW' and session.levelLoadState == 'READY' end), 'new fixture loaded')
    local units = {{monsterId='monster_tank',x=-3,y=-1}, {monsterId='monster_tank',x=-4,y=0}, {monsterId='monster_warrior',x=-5,y=1}}
    _FormationService:SaveForUser(userId, units, 1, session.saved.slots['1'].revision, _UtilLogic:NewGuid())
    assert(await(function() return not session.pending end) and #session.saved.slots['1'].units == 3, 'fixture saved')
    _FormationService:ActivateForUser(userId, 1, session.saved.slots['1'].revision)
    assert(await(function() return not session.pending end) and session.saved.activeSlot == 1, 'fixture activated')
    assert(storage:SetAndWait(levelKey, _MonsterLevelStorage:Encode({schema=1, monsters={monster_tank={level=5,experience=0},monster_warrior={level=8,experience=0}},settled={}})) == 0, 'seed levels after lobby cache load')
    _MatchFlow:QueueForUser(userId)
    local ticket = _MatchFlow._T.records[userId]
    assert(ticket and ticket.data.state == 'QUEUED', 'queue accepted')
    local roster = _FormationHandoff:Roster(ticket.id)
    assert(roster and roster[1].level == 5 and roster[2].level == 5 and roster[3].level == 8, 'queue re-reads and freezes per-monster levels')
    assert(storage:SetAndWait(levelKey, _MonsterLevelStorage:Encode({schema=1, monsters={monster_tank={level=30,experience=0}},settled={}})) == 0, 'later progress changed')
    roster[1].level = 29
    local retained = _FormationHandoff:Roster(ticket.id)
    assert(retained[1].level == 5 and retained[2].level == 5 and retained[3].level == 8, 'later saves and returned-table edits cannot change this match')
    _MatchFlow:CancelForUser(userId)
    assert(not _MatchFlow:IsFormationLocked(userId), 'cancel releases queue lock')
    local transfer = _FormationService:ExportConfirmed(userId)
    transfer.fixed = _HttpService:JSONEncode(units)
    local catalog = _FormationService:GetCatalog()
    local legacy = _FormationHandoff:DecodeTransfer(transfer, catalog)
    assert(legacy and legacy.units[1].level == 1 and legacy.units[3].level == 1, 'old in-flight transfers default to Lv1')
    for _, invalid in ipairs({false, {}, {monster_tank=0,monster_warrior=8}, {monster_tank=31,monster_warrior=8}, {monster_tank=1.5,monster_warrior=8}}) do
        transfer.levels = invalid
        assert(_FormationHandoff:DecodeTransfer(transfer, catalog) == nil, 'invalid new level snapshots fail closed')
    end
    local opened = _FormationHandoff:OpenForUser(userId)
    _FormationStorage:ConfigureMakerFaults(1, 0, 0)
    assert(not _FormationHandoff:Reserve(userId, opened, {attempt=_UtilLogic:NewGuid(),requestId=_UtilLogic:NewGuid(),source=_WorldInstanceService.WorldInstanceId,adapter='local'})
        and opened.failure == 'MONSTER_LEVELS_READ_FAILED' and not _FormationHandoff:IsLocked(profile), 'transport read failure blocks reservation and releases lock')
    _FormationStorage:ConfigureMakerFaults(0, 0, 0)
    assert(storage:SetAndWait(levelKey, 'broken-json') == 0, 'corrupt level fixture')
    _MatchFlow:QueueForUser(userId)
    assert(_MatchFlow._T.records[userId] == nil and not _MatchFlow:IsFormationLocked(userId), 'full queue rejects corrupt levels')
    local view = _MatchFlowState:Present({state='IDLE',reasonCode='MONSTER_LEVELS_READ_FAILED',started=0,players=0},
        {now=DateTime.UtcNow.Elapsed,pending=false,ready=true,hasActive=true,inLobby=true,formation={pending=false}})
    assert(string.find(_HttpService:JSONEncode(view), '讀取怪物等級失敗', 1, true), 'visible queue error explains level failure')
    assert(storage:DeleteAndWait(levelKey) == 0, 'new player fixture')
    _MatchFlow:QueueForUser(userId)
    local fresh = _MatchFlow._T.records[userId]
    assert(fresh and _FormationHandoff:Roster(fresh.id)[1].level == 1, 'new player can queue at Lv1')
    local missing, raw = storage:GetAndWait(levelKey)
    assert(missing == 1000002 or (missing == 0 and raw == nil), 'queue read does not create progression data')
    local battle = _EntityService:GetEntityByPath('/maps/template'):GetComponent('script.BattleSession')
    local prepared = battle:PrepareMatchedRoster(retained, false)
    assert(prepared and prepared[1].profile.Level == 5 and prepared[3].profile.Level == 8, 'battle accepts sealed levels')
    assert(catalog:GetProfile('monster_tank').Level == nil, 'battle never mutates catalog defaults')
end)
_FormationStorage:ConfigureMakerFaults(0, 0, 0)
if _MatchFlow._T.records[userId] ~= nil then _MatchFlow:CancelForUser(userId) end
_FormationService.StorageKey, _MonsterLevelStorage.StorageKey, _FormationHandoff.StorageKey = originalFormation, originalLevels, originalTransfer
local cleaned = true
for _, key in ipairs({formationKey,levelKey,transferKey}) do
    local code = storage:DeleteAndWait(key)
    cleaned = cleaned and (code == 0 or code == 1000002)
end
local session = _FormationService:GetSession(userId)
_FormationService:Load(session)
_FormationService:LoadLevels(session)
if not ok then log('[VRF][MatchedLevels67] FAIL '..tostring(detail))
elseif not cleaned then log('[VRF][MatchedLevels67] FAIL fixture cleanup')
else log('[VRF][MatchedLevels67] PASS fresh queue levels; immutable snapshot; legacy Lv1; invalid snapshot; read failures; new player; battle roster; CLEANUP_PASS') end
