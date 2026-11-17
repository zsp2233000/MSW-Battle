-- server_main, Maker only. SETUP before the edit UI probe; rerun with CLEANUP=true afterwards.
local CLEANUP = false
assert(Environment:IsMakerPlay(), 'Maker only')
local service = _GMCommandService
local fixture = service._T.gm85EditFixture
if CLEANUP then
    assert(fixture ~= nil, 'fixture was set up in this Play')
    _MonsterLevelStorage.StorageKey = fixture.original
    for _, profile in ipairs({ fixture.profile, 'GM85CORRUPT', 'GM85ABSENT' }) do
        local storage = _DataStorageService:GetUserDataStorage(profile)
        local code = storage:DeleteAndWait(fixture.key)
        assert(code == 0 or code == 1000002, 'fixture delete')
        local missing, raw = storage:GetAndWait(fixture.key)
        assert(missing == 1000002 or (missing == 0 and raw == nil), 'fixture key gone')
    end
    service._T.gm85EditFixture = nil
    log('[VRF][GMPanelEditUIFixture] CLEANUP_PASS')
    return
end
assert(fixture == nil, 'clean up the existing fixture first')
fixture = { original = _MonsterLevelStorage.StorageKey, key = 'Issue85GM_UI_' .. _UtilLogic:NewGuid(),
    profile = _UserService.UserEntities.Values[1].PlayerComponent.ProfileCode }
service._T.gm85EditFixture = fixture
local valid = '{"schema":1,"monsters":{"monster_tank":{"level":6,"experience":2}},"settled":["gm85-already-settled"]}'
assert(_DataStorageService:GetUserDataStorage(fixture.profile):SetAndWait(fixture.key, valid) == 0, 'valid UI fixture')
assert(_DataStorageService:GetUserDataStorage('GM85CORRUPT'):SetAndWait(fixture.key, 'broken <b>literal</b>\n{"schema":99}') == 0, 'corrupt UI fixture')
_MonsterLevelStorage.StorageKey = fixture.key
log('[VRF][GMPanelEditUIFixture] READY isolated=' .. fixture.key)
