-- server_main, fresh Play. Authenticate the Maker GM and mutate a disposable synthetic target.
assert(Environment:IsMakerPlay(), 'Maker only')
local service = _GMCommandService
local boundary = _FormationStorage
local requester = _UserService.UserEntities.Values[1].PlayerComponent.ProfileCode
local target = 'GM85' .. string.sub(string.gsub(_UtilLogic:NewGuid(), '-', ''), 1, 8)
local original = _MonsterLevelStorage.StorageKey
local key = 'GM85Levels'
local user = _DataStorageService:GetUserDataStorage(target)
local audit = _DataStorageService:GetGlobalDataStorage('GMAuditV1')
local function execute(command, snapshot, actor)
    command.profile = target
    if snapshot then command.expected, command.expectedExists = snapshot.expected, snapshot.exists end
    local reply
    service:Execute(actor or requester, command, function(result) reply = result end)
    for _ = 1, 200 do
        if reply then return reply end
        wait(0.1)
    end
    error('callback timed out for ' .. command.kind)
end
local function save(level, experience, snapshot)
    return execute({ kind = 'SAVE_LEVELS', rows = { { monsterId = 'monster_tank', level = level, experience = experience } } }, snapshot)
end
local function load() return execute({ kind = 'LOAD_LEVELS' }) end
local function auditRecord(slot)
    local code, cursor = audit:GetAndWait(target)
    assert(code == 0, 'audit cursor: ' .. tostring(code))
    local prefix = target .. '_' .. (slot or assert(cursor:match('^(%d+):')))
    local metaCode, meta = audit:GetAndWait(prefix)
    local beforeCode, before = audit:GetAndWait(prefix .. '_before')
    local afterCode, after = audit:GetAndWait(prefix .. '_after')
    assert(metaCode == 0 and beforeCode == 0 and afterCode == 0, 'complete audit slot')
    local record = _HttpService:JSONDecode(meta)
    record.before, record.after = before, after
    return record
end
local function assertMissing(container, storageKey)
    local code, raw = container:GetAndWait(storageKey)
    assert(code == 1000002 or (code == 0 and raw == nil), 'expected missing ' .. storageKey .. ': ' .. tostring(code))
end
local function assertStored(expected)
    local code, value = user:GetAndWait(key)
    assert(code == 0 and value == expected, 'expected byte-exact save')
end
local function levels(level, experience, settled)
    return '{"schema":1,"monsters":{"monster_tank":{"level":' .. level .. ',"experience":' .. experience .. '}},"settled":' .. settled .. '}'
end
local ok, detail = pcall(function()
    assert(service:IsGM(requester) and not service:IsGM(target), 'real GM and non-GM synthetic target')
    assertMissing(user, key)
    assertMissing(audit, target)
    _MonsterLevelStorage.StorageKey = key
    for _, kind in ipairs({ 'LOAD_LEVELS', 'SAVE_LEVELS', 'RESET_LEVELS', 'DELETE_LEVELS', 'FORCE_SAVE_LEVELS' }) do
        assert(execute({ kind = kind }, nil, target).status == 'FORBIDDEN', 'whitelist ' .. kind)
    end
    local absent = load()
    assert(absent.status == 'READY' and absent.exists == false, 'missing save')
    assert(save(31, 0, absent).status == 'INVALID_PROGRESS', 'invalid level rejected')
    assertMissing(user, key)
    assertMissing(audit, target)

    local valid = levels(6, 2, '["first"]')
    local changed = levels(7, 1, '["first","second"]')
    assert(user:SetAndWait(key, valid) == 0, 'load fixture')
    local opened = load()
    assert(save(6, 6, opened).status == 'INVALID_PROGRESS', 'invalid experience rejected')
    assertStored(valid)
    local saved = save(8, 3, opened)
    assert(saved.status == 'SAVED', 'save: ' .. tostring(saved.status) .. '/' .. tostring(saved.code))
    assertStored(saved.expected)
    local document = _MonsterLevelStorage:Decode(saved.expected)
    assert(document.monsters.monster_tank.level == 8 and document.monsters.monster_tank.experience == 3, 'edit round-trips')
    local first = auditRecord()
    assert(first.before == valid and first.after == saved.expected and first.outcome == 'SAVED'
        and first.gm == requester and first.target == target and first.key == key and first.timeMs > 0, 'all audit fields')

    assert(user:SetAndWait(key, changed) == 0, 'concurrent settlement')
    local conflict = save(9, 0, saved)
    assert(conflict.status == 'CONFLICT' and conflict.expected == changed and load().expected == changed, 'conflict and reload')
    local forced = execute({ kind = 'FORCE_SAVE_LEVELS', action = 'SAVE_LEVELS',
        rows = { { monsterId = 'monster_tank', level = 9, experience = 0 } } }, saved)
    assert(forced.status == 'SAVED' and auditRecord().before == changed, 'force audits exactly what it overwrote')
    local reset = execute({ kind = 'FORCE_SAVE_LEVELS', action = 'RESET_LEVELS' }, saved)
    document = _MonsterLevelStorage:Decode(reset.expected)
    assert(reset.status == 'SAVED' and next(document.monsters) == nil and #document.settled == 2
        and document.settled[1] == 'first' and document.settled[2] == 'second', 'reset retains settled matches')
    for _, row in ipairs(reset.rows) do assert(row.level == 1 and row.experience == 0, 'reset defaults') end

    boundary:ConfigureMakerAuditFailures(1)
    assert(save(4, 1, reset).status == 'AUDIT_FAILED', 'audit failure surfaced')
    assertStored(reset.expected)
    local last = auditRecord()
    assert(last.after == reset.expected, 'audit failure leaves trail unchanged')
    for _, code in ipairs({ 1000004, 1000005 }) do
        boundary:ConfigureMakerFailureCode(code)
        boundary:ConfigureMakerFaults(1, 0, 0)
        local readFailed = save(4, 1, reset)
        assert(readFailed.status == 'STORAGE_ERROR' and readFailed.code == code, 'read error surfaced')
        boundary:ConfigureMakerFaults(0, 1, 0)
        local writeFailed = save(4, 1, reset)
        assert(writeFailed.status == 'STORAGE_ERROR' and writeFailed.code == code, 'write error surfaced')
        assertStored(reset.expected)
    end
    boundary:ConfigureMakerFaults(0, 0, 0)
    boundary:ConfigureMakerFailureCode(1000004)

    local corrupt = ('broken "save"\n'):rep(350)
    assert(user:SetAndWait(key, corrupt) == 0, 'corrupt fixture')
    local damaged = load()
    assert(damaged.status == 'CORRUPT' and damaged.raw == corrupt, 'corruption round-trips as literal bytes')
    local repaired = execute({ kind = 'SAVE_LEVELS', raw = levels(3, 1, '["recovered"]') }, damaged)
    assert(repaired.status == 'SAVED' and auditRecord().before == corrupt, 'repair with recoverable before-content')
    local refused = execute({ kind = 'FORCE_SAVE_LEVELS', action = 'DELETE_LEVELS' }, damaged)
    assert(refused.status == 'NOT_CORRUPT', 'force delete refuses a healthy save')
    assertStored(repaired.expected)
    assert(user:SetAndWait(key, '') == 0, 'empty corrupt fixture')
    local empty = load()
    assert(empty.status == 'CORRUPT' and empty.exists and empty.expected == '', 'empty bytes differ from absent')
    assert(save(2, 0, absent).status == 'CONFLICT', 'absent expectation cannot overwrite empty bytes')
    local removed = execute({ kind = 'DELETE_LEVELS' }, empty)
    local deletion = auditRecord()
    assert(removed.status == 'SAVED' and removed.exists == false and deletion.beforeExists
        and not deletion.afterExists and deletion.before == '' and deletion.after == '', 'empty corrupt save deleted and audited')
    assertMissing(user, key)

    local seed = { [target] = '19:abc' }
    for slot = 8, 19 do
        local prefix = target .. '_' .. slot
        seed[prefix] = '{"outcome":"SAVED","id":"seed"}'
        seed[prefix .. '_before'] = ''
        seed[prefix .. '_after'] = ''
    end
    assert(audit:BatchSetAndWait(seed) == 0, 'retention fixture')
    local slot20 = save(2, 0, load())
    assert(slot20.status == 'SAVED' and auditRecord(20).after == slot20.expected, 'first creation and slot 20')
    local wrapped = save(2, 1, slot20)
    assert(wrapped.status == 'SAVED' and auditRecord(1).after == wrapped.expected, 'slot 1 replaced')
    assert(auditRecord(2).before == changed and auditRecord(20).after == slot20.expected, 'next oldest and prior write retained')
    assertMissing(audit, target .. '_21')
end)
boundary:ConfigureMakerAuditFailures(0)
boundary:ConfigureMakerFaults(0, 0, 0)
boundary:ConfigureMakerFailureCode(1000004)
_MonsterLevelStorage.StorageKey = original
local cleaned, cleanupError = pcall(function()
    local code = user:DeleteAndWait(key)
    assert(code == 0 or code == 1000002, 'delete level fixture')
    assertMissing(user, key)
    local keys = { target }
    for slot = 1, 20 do
        local prefix = target .. '_' .. slot
        table.insert(keys, prefix)
        table.insert(keys, prefix .. '_before')
        table.insert(keys, prefix .. '_after')
    end
    audit:BatchDeleteAndWait(keys)
    for _, storageKey in ipairs(keys) do assertMissing(audit, storageKey) end
end)
if ok and cleaned then
    log('[VRF][GMLevelWriteProbe] PASS save; validation; conflict; force; reset; audit; repair; delete; retention; errors; CLEANUP_PASS')
else
    log_error('[VRF][GMLevelWriteProbe] FAIL ' .. tostring(detail) .. ' cleanup=' .. tostring(cleaned) .. ' ' .. tostring(cleanupError))
end
