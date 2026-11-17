-- server_main, fresh Play. The requester stays the real GM; every save uses a short synthetic target.
assert(Environment:IsMakerPlay(), 'Maker only')
local function await(predicate)
    for _ = 1, 200 do if predicate() then return true end wait(0.1) end
    return predicate()
end
local service = _GMCommandService
local storage = _FormationStorage
local requester = _UserService.UserEntities.Values[1].PlayerComponent.ProfileCode
local target = 'GM85' .. string.sub(string.gsub(_UtilLogic:NewGuid(), '-', ''), 1, 8)
local original = _MonsterLevelStorage.StorageKey
local key = 'GM85L' .. string.sub(string.gsub(_UtilLogic:NewGuid(), '-', ''), 1, 8)
local user = _DataStorageService:GetUserDataStorage(target)
local audit = _DataStorageService:GetGlobalDataStorage('GMAuditV1')
local function execute(command)
    command.profile = target
    local result = nil
    service:Execute(requester, command, function(reply) result = reply end)
    assert(await(function() return result ~= nil end), 'callback '..command.kind)
    return result
end
local function read(container, storageKey)
    local done, code, value = false, nil, nil
    container:GetAsync(storageKey, function(resultCode, loadedKey, raw) code, value, done = resultCode, raw, true end)
    assert(await(function() return done end), 'read')
    return code, value
end
local function records()
    local code, raw = read(audit, target)
    assert(code == 0 and raw ~= nil, 'synthetic audit readable')
    return _HttpService:JSONDecode(raw), raw
end
local valid = '{"schema":1,"monsters":{"monster_tank":{"level":6,"experience":2}},"settled":["gm85-settled"]}'
local changed = '{"schema":1,"monsters":{"monster_tank":{"level":7,"experience":1}},"settled":["gm85-settled","gm85-later"]}'
local repaired = '{"schema":1,"monsters":{"monster_tank":{"level":3,"experience":1}},"settled":["gm85-repaired"]}'
local ok, detail = pcall(function()
    assert(service:IsGM(requester) and not service:IsGM(target), 'real requester, synthetic target')
    _MonsterLevelStorage.StorageKey = key
    local rejected = execute({ kind = 'SAVE_LEVELS', expected = '', rows = { { monsterId = 'monster_tank', level = 31, experience = 0 } } })
    assert(rejected.status == 'INVALID_PROGRESS', 'invalid rejected')
    local code, raw = read(user, key)
    assert(code == 1000002 or raw == nil, 'invalid write created nothing')
    assert(user:SetAndWait(key, valid) == 0, 'fixture')
    local saved = execute({ kind = 'SAVE_LEVELS', expected = valid, rows = { { monsterId = 'monster_tank', level = 8, experience = 3 } } })
    code, raw = read(user, key)
    local trail = records()
    assert(saved.status == 'SAVED' and raw == saved.expected and raw:find('gm85-settled', 1, true), 'save preserves settled list')
    assert(trail[1].before == valid and trail[1].outcome == 'SAVED' and trail[1].gm == requester, 'audit result recorded')
    assert(user:SetAndWait(key, changed) == 0, 'later settlement')
    local conflict = execute({ kind = 'SAVE_LEVELS', expected = saved.expected, rows = { { monsterId = 'monster_tank', level = 9, experience = 0 } } })
    assert(conflict.status == 'CONFLICT' and conflict.expected == changed, 'conflict returns current bytes')
    local forced = execute({ kind = 'FORCE_SAVE_LEVELS', expected = saved.expected, rows = { { monsterId = 'monster_tank', level = 9, experience = 0 } } })
    code, raw = read(user, key)
    trail = records()
    assert(forced.status == 'SAVED' and trail[#trail].before == changed and trail[#trail].outcome == 'SAVED', 'force records overwritten version')
    local reset = execute({ kind = 'RESET_LEVELS', expected = forced.expected })
    code, raw = read(user, key)
    assert(reset.status == 'SAVED' and raw:find('"level":1', 1, true) and raw:find('gm85-later', 1, true), 'reset keeps both settled matches')
    storage:ConfigureMakerAuditFailures(1)
    local blocked = execute({ kind = 'SAVE_LEVELS', expected = reset.expected, rows = { { monsterId = 'monster_tank', level = 4, experience = 1 } } })
    code, raw = read(user, key)
    assert(blocked.status == 'AUDIT_FAILED' and raw == reset.expected, 'audit failure leaves save untouched')
    storage:ConfigureMakerFaults(1, 0, 0)
    local readFailed = execute({ kind = 'SAVE_LEVELS', expected = reset.expected, rows = { { monsterId = 'monster_tank', level = 4, experience = 1 } } })
    assert(readFailed.status == 'STORAGE_ERROR', 'read error is not success')
    storage:ConfigureMakerFaults(0, 1, 0)
    local writeFailed = execute({ kind = 'SAVE_LEVELS', expected = reset.expected, rows = { { monsterId = 'monster_tank', level = 4, experience = 1 } } })
    code, raw = read(user, key)
    assert((writeFailed.status == 'STORAGE_ERROR' or writeFailed.status == 'AUDIT_INCOMPLETE') and raw == reset.expected, 'write error is not success')
    storage:ConfigureMakerFaults(0, 0, 0)
    assert(user:SetAndWait(key, 'broken-save') == 0, 'corrupt fixture')
    local refused = execute({ kind = 'DELETE_LEVELS', expected = valid })
    assert(refused.status == 'NOT_CORRUPT' or refused.status == 'CONFLICT', 'stale delete cannot remove changed save')
    local removed = execute({ kind = 'DELETE_LEVELS', expected = 'broken-save' })
    code, raw = read(user, key)
    trail = records()
    assert(removed.status == 'SAVED' and removed.exists == false and (code == 1000002 or raw == nil), 'corrupt save deleted')
    assert(trail[#trail].before == 'broken-save' and trail[#trail].after == '', 'delete audits absence, not its marker')
    local fixture = {}
    for index = 1, 19 do table.insert(fixture, { gm = 'seed', outcome = 'SAVED', index = index }) end
    assert(audit:SetAndWait(target, _HttpService:JSONEncode(fixture)) == 0, 'retention fixture')
    local seededCode, seededRaw = read(audit, target)
    local first = execute({ kind = 'SAVE_LEVELS', expected = '', rows = { { monsterId = 'monster_tank', level = 2, experience = 0 } } })
    local secondExpectedCode, secondExpected = read(user, key)
    assert(first.status == 'SAVED' and secondExpectedCode == 0, 'first retention write')
    local second = execute({ kind = 'SAVE_LEVELS', expected = secondExpected, rows = { { monsterId = 'monster_tank', level = 2, experience = 1 } } })
    trail = records()
    assert(second.status == 'SAVED' and #trail == 20 and trail[1].index == 2 and trail[20].outcome == 'SAVED', 'latest 20 retained')
    assert(user:SetAndWait(key, 'broken-save') == 0, 'second corrupt fixture')
    local forcedDelete = execute({ kind = 'FORCE_SAVE_LEVELS', action = 'DELETE_LEVELS', expected = 'stale-corrupt' })
    code, raw = read(user, key)
    assert(forcedDelete.status == 'SAVED' and (code == 1000002 or raw == nil), 'forced delete removes current corrupt save')
    assert(user:SetAndWait(key, second.expected) == 0, 'healthy restored')
    local refusedForce = execute({ kind = 'FORCE_SAVE_LEVELS', action = 'DELETE_LEVELS', expected = 'broken-save' })
    code, raw = read(user, key)
    assert(refusedForce.status == 'NOT_CORRUPT' and raw == forcedReset.expected, 'forced delete refuses a healthy save')
    local forcedReset = execute({ kind = 'FORCE_SAVE_LEVELS', action = 'RESET_LEVELS', expected = 'stale-reset' })
    code, raw = read(user, key)
    assert(forcedReset.status == 'SAVED' and raw:find('"level":1', 1, true) and raw:find('gm85-later', 1, true), 'forced reset keeps settled list')
    local healthy = execute({ kind = 'SAVE_LEVELS', expected = forcedReset.expected, raw = repaired })
    code, raw = read(user, key)
    assert(healthy.status == 'INVALID_PROGRESS' and raw == forcedReset.expected, 'raw repair cannot replace a healthy save')
end)
storage:ConfigureMakerAuditFailures(0)
storage:ConfigureMakerFaults(0, 0, 0)
_MonsterLevelStorage.StorageKey = original
local levelCleanup = user:DeleteAndWait(key)
local auditCleanup = audit:DeleteAndWait(target)
local levelCode, levelRaw = user:GetAndWait(key)
local auditCode, auditRaw = audit:GetAndWait(target)
local requesterAuditCode, requesterAuditRaw = audit:GetAndWait(requester)
if ok and (levelCleanup == 0 or levelCleanup == 1000002) and (auditCleanup == 0 or auditCleanup == 1000002)
    and (levelCode == 1000002 or levelRaw == nil) and (auditCode == 1000002 or auditRaw == nil)
    and requesterAuditRaw == nil then
    log('[VRF][GMLevelWriteProbe] PASS save; conflict; force; reset; audit; delete; retention; errors; CLEANUP_PASS')
else log_error('[VRF][GMLevelWriteProbe] FAIL '..tostring(detail)..' requesterAudit='..tostring(requesterAuditCode)) end
