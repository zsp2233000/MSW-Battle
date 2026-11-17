-- server_main, fresh Play; only a disposable key is written, then deleted even on assertion failure.
assert(Environment:IsMakerPlay(), 'Maker only')
local function await(predicate)
    for _ = 1, 150 do if predicate() then return true end wait(0.1) end
    return predicate()
end
local service = _GMCommandService
local profile = _UserService.UserEntities.Values[1].PlayerComponent.ProfileCode
local original = _MonsterLevelStorage.StorageKey
local key = 'Issue84GM_' .. _UtilLogic:NewGuid()
local storage = _DataStorageService:GetUserDataStorage(profile)
local function execute(requester, kind, target)
    local result = nil
    service:Execute(requester, { kind = kind, profile = target or '' }, function(reply) result = reply end)
    assert(await(function() return result ~= nil end), 'command callback: '..kind)
    return result
end
local valid = '{"schema":1,"monsters":{"monster_tank":{"level":6,"experience":2}},"settled":["gm84-already-settled"]}'
local corrupt = 'broken <b>literal</b>\n{"schema":99}'
local ok, detail = pcall(function()
    assert(service:IsGM(profile), 'connected Maker account is whitelisted')
    _MonsterLevelStorage.StorageKey = key
    _FormationStorage:ConfigureMakerFaults(1, 0, 0)
    for _, kind in ipairs({ 'IDENTITY', 'LOAD_LEVELS', 'SAVE', 'FORCE_SAVE', 'RESET_LEVELS', 'DELETE', 'LIST_RECORDS', 'RESTORE', 'UNKNOWN' }) do
        assert(execute('GM84NOTALLOWED', kind, profile).status == 'FORBIDDEN', 'non-GM refused: '..kind)
    end
    assert(execute(profile, 'IDENTITY').profile == profile, 'identity comes back to GM')
    assert(execute(profile, 'UNKNOWN').status == 'INVALID_COMMAND', 'unsupported commands refused')
    local failed = execute(profile, 'LOAD_LEVELS')
    assert(failed.status == 'STORAGE_ERROR' and failed.code == 1000004, 'denied/identity/unknown commands made no read; storage error surfaced')
    _FormationStorage:ConfigureMakerFaults(0, 0, 0)
    local absent = execute(profile, 'LOAD_LEVELS')
    local data = _DataService:GetTable('MonsterData')
    assert(absent.status == 'READY' and absent.exists == false and #absent.rows == data:GetRowCount(), 'absent save lists all data-table monsters')
    local seen = {}
    for _, row in ipairs(absent.rows) do
        assert(row.level == 1 and row.experience == 0 and not seen[row.monsterId], 'unique default row')
        seen[row.monsterId] = true
    end
    for index = 1, data:GetRowCount() do assert(seen[data:GetRow(index):GetItem('MonsterId')], 'all monster ids included') end
    local missing, raw = storage:GetAndWait(key)
    assert(missing == 1000002 or (missing == 0 and raw == nil), 'load did not create missing save')
    assert(storage:SetAndWait(key, valid) == 0, 'valid fixture')
    for _, target in ipairs({ '', profile }) do
        local reply = execute(profile, 'LOAD_LEVELS', target)
        assert(reply.status == 'READY' and reply.exists and reply.profile == profile, 'self and explicit ProfileCode both load')
        for _, row in ipairs(reply.rows) do
            if row.monsterId == 'monster_tank' then assert(row.level == 6 and row.experience == 2, 'stored progression')
            else assert(row.level == 1 and row.experience == 0, 'unstored monster defaults') end
        end
    end
    local code, unchanged = storage:GetAndWait(key)
    assert(code == 0 and unchanged == valid, 'valid save and settled list unchanged byte-for-byte')
    assert(execute(profile, 'LOAD_LEVELS', '***').status == 'INVALID_PROFILE', 'invalid target refused')
    assert(storage:SetAndWait(key, corrupt) == 0, 'corrupt fixture')
    local broken = execute(profile, 'LOAD_LEVELS', profile)
    assert(broken.status == 'CORRUPT' and broken.raw == corrupt and broken.rows == nil, 'raw corrupt save returned without invented defaults')
    code, unchanged = storage:GetAndWait(key)
    assert(code == 0 and unchanged == corrupt, 'corrupt save unchanged byte-for-byte')
end)
_FormationStorage:ConfigureMakerFaults(0, 0, 0)
_MonsterLevelStorage.StorageKey = original
local cleanup = storage:DeleteAndWait(key)
local missing, remaining = storage:GetAndWait(key)
if ok and (cleanup == 0 or cleanup == 1000002) and (missing == 1000002 or (missing == 0 and remaining == nil)) then
    log('[VRF][GMPanelServerProbe] PASS permission; defaults; explicit target; self; valid; corrupt; error; CLEANUP_PASS')
else log_error('[VRF][GMPanelServerProbe] FAIL '..tostring(detail)..' cleanup='..tostring(cleanup)) end
