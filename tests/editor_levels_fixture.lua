-- server_main; SETUP once, then SEEDED/NEW/FAILURE/CORRUPT, finally CLEANUP.
-- After each data change the client requests RequestRetryLoad (or returns to the lobby).
-- Never run SETUP twice in one Play; originals are printed for emergency restoration.
local MODE = 'SETUP'
local levels, formations = _MonsterLevelStorage, _FormationService
local storage = nil
if MODE == 'SETUP' then
    assert(#_UserService.UserEntities.Values == 1, 'SETUP before adding a peer')
    storage = _DataStorageService:GetUserDataStorage(_UserService.UserEntities.Values[1].PlayerComponent.ProfileCode)
else
    for _, player in ipairs(_UserService.UserEntities.Values) do
        local candidate = _DataStorageService:GetUserDataStorage(player.PlayerComponent.ProfileCode)
        local code, raw = candidate:GetAndWait(levels.StorageKey..'_originals')
        if code == 0 and raw ~= nil then storage = candidate break end
    end
    assert(storage ~= nil, 'original fixture owner is in this room')
end
local ok, detail = pcall(function()
    if MODE == 'SETUP' then
        assert(not string.find(levels.StorageKey, 'Issue66_'), 'fixture already active')
        local originalLevels, originalFormations = levels.StorageKey, formations.StorageKey
        local key = 'Issue66_'.._UtilLogic:NewGuid()
        local originals = _HttpService:JSONEncode({levels=originalLevels, formations=originalFormations})
        assert(storage:SetAndWait(key..'_originals', originals) == 0, 'retain original keys')
        log('[VRF][EditorLevels] original levels='..originalLevels..' formations='..originalFormations)
        levels.StorageKey, formations.StorageKey = key, key..'_formations'
    elseif MODE == 'CLEANUP' then
        local key = levels.StorageKey
        assert(string.find(key, 'Issue66_', 1, true) == 1, 'isolated fixture only')
        local code, raw = storage:GetAndWait(key..'_originals')
        assert(code == 0, 'original keys retained')
        local originals = _HttpService:JSONDecode(raw)
        levels.StorageKey, formations.StorageKey = originals.levels, originals.formations
        _FormationStorage:ConfigureMakerFaults(0, 0, 0)
        assert(storage:DeleteAndWait(key) == 0, 'delete level fixture')
        assert(storage:DeleteAndWait(key..'_formations') == 0, 'delete formation fixture')
        assert(storage:DeleteAndWait(key..'_originals') == 0, 'delete retained keys')
    else
        assert(string.find(levels.StorageKey, 'Issue66_', 1, true) == 1, 'isolated fixture only')
        if MODE == 'SEEDED' then
            assert(storage:SetAndWait(levels.StorageKey, levels:Encode({schema=1, monsters={
                monster_tank={level=5, experience=3}, monster_shooter={level=30, experience=0},
            }, settled={}})) == 0, 'seed different levels and absent monster')
        elseif MODE == 'NEW' then
            assert(storage:DeleteAndWait(levels.StorageKey) == 0, 'missing level key')
        elseif MODE == 'FAILURE' then
            _FormationStorage:ConfigureMakerFaults(1, 0, 0)
        elseif MODE == 'CORRUPT' then
            assert(storage:SetAndWait(levels.StorageKey, 'broken-json') == 0, 'damaged fixture')
        elseif MODE == 'CHECK_CORRUPT' then
            local code, raw = storage:GetAndWait(levels.StorageKey)
            assert(code == 0 and raw == 'broken-json', 'lobby leaves damaged bytes unchanged')
        elseif MODE == 'CHECK_NEW' then
            local code, raw = storage:GetAndWait(levels.StorageKey)
            assert(code == 1000002 or (code == 0 and raw == nil), 'lobby never writes new-player defaults')
        else error('unknown mode') end
    end
end)
log(ok and '[VRF][EditorLevels] '..MODE..' PASS' or '[VRF][EditorLevels] '..MODE..' FAIL '..tostring(detail))
