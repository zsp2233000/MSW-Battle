-- server_main in Maker; only a synthetic player's save and audit keys are touched.
assert(Environment:IsMakerPlay(), 'Maker only')
local storage, service = _FormationStorage, _GMCommandService
local profile = 'GM87' .. _UtilLogic:NewGuid():gsub('%-', ''):sub(1, 10)
local formationKey, handoffKey = _FormationService.StorageKey, _FormationHandoff.StorageKey
local gm
for _, player in ipairs(_UserService.Users.Values) do
    if service:IsGM(player.ProfileCode) then gm = player.ProfileCode break end
end
assert(gm and not service:IsGM(profile), 'GM and a unique synthetic player are required')
local datastore = _DataStorageService:GetUserDataStorage(profile)
local audit = _DataStorageService:GetGlobalDataStorage('GMAuditV1')
local function await(predicate)
    for _ = 1, 150 do if predicate() then return true end wait(0.1) end
    return predicate()
end
local function execute(kind, fields, requester)
    local result
    local command = fields or {}
    command.kind, command.profile = kind, profile
    service:Execute(requester or gm, command, function(reply) result = reply end)
    assert(await(function() return result ~= nil end), 'command callback: ' .. kind)
    return result
end
local function read(key)
    local result, raw
    storage:Read(profile, key, function(code, _, value) result, raw = code, value end)
    assert(await(function() return result ~= nil end), 'storage response')
    assert(result == 0 or result == 1000002, 'storage read: ' .. tostring(result))
    return raw
end
local function write(key, expected, raw)
    local result
    storage:Write(profile, key, expected, raw, function(code) result = code end)
    assert(await(function() return result ~= nil end), 'write callback')
    return result
end
local function expect(kind, loaded, fields)
    fields = fields or {}
    fields.expected, fields.expectedExists = loaded.expected, loaded.exists
    return execute(kind, fields)
end
local ok, detail = pcall(function()
    assert(read(formationKey) == nil and read(handoffKey) == nil, 'empty synthetic keys')
    for _, kind in ipairs({'LOAD_FORMATIONS', 'LOAD_HANDOFF', 'SAVE_FORMATIONS', 'DELETE_FORMATIONS', 'DELETE_HANDOFF',
        'RESTORE_FORMATIONS', 'RESTORE_HANDOFF', 'FORCE_SAVE_LEVELS'}) do
        assert(execute(kind, nil, profile).status == 'FORBIDDEN', 'authorization: ' .. kind)
    end
    local doc = _FormationSchema:EmptyDocument()
    local valid = _FormationSchema:EncodeDocument(doc)
    local absent = execute('LOAD_FORMATIONS')
    assert(absent.status == 'READY' and not absent.exists, 'absent formation')
    assert(expect('SAVE_FORMATIONS', absent, {raw = valid}).status == 'SAVED', 'valid JSON saves')
    local loaded = execute('LOAD_FORMATIONS')
    assert(loaded.status == 'READY' and loaded.raw == valid and read(formationKey) == valid, 'exact JSON round trip')
    assert(expect('SAVE_FORMATIONS', loaded, {raw = '{"schema":2}'}).status == 'INVALID_FORMATIONS', 'invalid formation rejected')
    assert(read(formationKey) == valid, 'invalid JSON leaves save unchanged')

    local damaged = 'broken <b>literal</b>'
    assert(write(formationKey, valid, damaged) == 0, 'external corrupt replacement creates stale expectation')
    local conflict = expect('DELETE_FORMATIONS', loaded)
    assert(conflict.status == 'CONFLICT' and conflict.raw == damaged, 'stale delete returns actual bytes')
    local corrupt = execute('LOAD_FORMATIONS')
    assert(corrupt.status == 'CORRUPT' and corrupt.raw == damaged, 'damaged bytes visible')
    assert(execute('FORCE_SAVE_LEVELS', {action = 'SAVE_FORMATIONS', raw = valid}).status == 'SAVED', 'force supports repair')
    local history = execute('LIST_AUDIT')
    assert(history.status == 'HISTORY_READY' and #history.records == 2, 'force records successful writes only')
    local repair = history.records[1]
    assert(repair.key == formationKey and repair.action == 'SAVE_FORMATIONS', 'record identifies formation changes')
    local restored = expect('RESTORE_FORMATIONS', execute('LOAD_FORMATIONS'), {recordId = repair.id})
    assert(restored.status == 'SAVED' and restored.corrupt and read(formationKey) == damaged, 'restore uses actual prior bytes')

    local guard
    storage:BeginExclusive(profile, formationKey, function(code, acquired)
        assert(code == 0, 'acquire delete guard')
        guard = acquired
    end)
    assert(guard, 'formation guard acquired')
    local blocked = write(formationKey, damaged, valid)
    storage:EndExclusive(guard)
    assert(blocked == 1000007 and read(formationKey) == damaged, 'normal writer cannot race the delete guard')

    corrupt = execute('LOAD_FORMATIONS')
    storage:ConfigureMakerAuditFailures(1)
    assert(expect('DELETE_FORMATIONS', corrupt).status == 'AUDIT_FAILED' and read(formationKey) == damaged, 'no audit means no delete')
    storage:ConfigureMakerFailureCode(1000005)
    storage:ConfigureMakerFaults(0, 1, 0)
    local failed = expect('DELETE_FORMATIONS', corrupt)
    assert(failed.status == 'STORAGE_ERROR' and failed.code == 1000005 and read(formationKey) == damaged, 'delete fault returned')
    local cleared = expect('DELETE_FORMATIONS', corrupt)
    assert(cleared.status == 'SAVED' and not cleared.exists and read(formationKey) == nil, 'clear corrupt formation')
    assert(write(formationKey, damaged, valid) == 2000000 and read(formationKey) == nil,
        'logged-in player with stale bytes cannot recreate cleared formation')

    local handoff = '{"state":"TRANSFER","probe":true}'
    assert(write(handoffKey, '', handoff) == 0, 'setup handoff')
    loaded = execute('LOAD_HANDOFF')
    assert(loaded.status == 'READY' and loaded.raw == handoff, 'handoff view')
    assert(expect('SAVE_HANDOFF', loaded, {raw = '{}'}).status == 'INVALID_COMMAND', 'reject handoff saves')
    assert(execute('FORCE_SAVE_LEVELS', {action = 'SAVE_HANDOFF', raw = '{}'}).status == 'INVALID_COMMAND', 'reject forced handoff saves')
    assert(read(handoffKey) == handoff, 'handoff unchanged')
    assert(expect('DELETE_HANDOFF', loaded).status == 'SAVED' and read(handoffKey) == nil, 'delete handoff')
    history = execute('LIST_AUDIT')
    assert(history.status == 'HISTORY_READY' and history.records[1].key == handoffKey
        and history.records[1].action == 'DELETE_HANDOFF' and history.records[1].outcome == 'SAVED'
        and history.records[2].key == formationKey and history.records[2].action == 'DELETE_FORMATIONS'
        and history.records[2].outcome == 'SAVED', 'both deletions are retained in the same audit list')
    local handoffRecord = history.records[1].id
    assert(execute('RESTORE_HANDOFF', {recordId = handoffRecord}).status == 'INVALID_COMMAND', 'handoff restore refused')
    assert(execute('FORCE_SAVE_LEVELS', {action = 'RESTORE_HANDOFF', recordId = handoffRecord}).status == 'INVALID_COMMAND',
        'forced handoff restore refused')
    assert(read(handoffKey) == nil, 'handoff stays deleted')
end)

storage:ConfigureMakerAuditFailures(0)
storage:ConfigureMakerFaults(0, 0, 0)
storage:ConfigureMakerFailureCode(1000004)
local function remove(container, key)
    local code = container:DeleteAndWait(key)
    assert(code == 0 or code == 1000002, 'cleanup: ' .. key)
    local readCode, raw = container:GetAndWait(key)
    assert(readCode == 1000002 or (readCode == 0 and raw == nil), 'cleanup confirmed: ' .. key)
end
remove(datastore, formationKey)
remove(datastore, handoffKey)
local cursorCode, cursor = audit:GetAndWait(profile)
assert(cursorCode == 0 or cursorCode == 1000002, 'read cleanup cursor')
if cursor ~= nil then
    for slot = 1, assert(tonumber(cursor:match('^(%d+):'))) do
        local prefix = profile .. '_' .. slot
        for _, suffix in ipairs({'', '_before', '_after'}) do remove(audit, prefix .. suffix) end
    end
    remove(audit, profile)
end
assert(ok, tostring(detail))
log('[VRF][GMSaveItemsServerProbe] PASS validation; corruption; clear; handoff; conflict; audit; delete fault; CLEANUP_PASS')
