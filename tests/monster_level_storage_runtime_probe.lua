-- server_main; private disposable key, production storage boundary and its existing fault injection.
local function await(predicate, tries)
    for _ = 1, tries or 400 do if predicate() then return true end wait(0.1) end
    return false
end
local service = _MonsterLevelStorage
local original = service.StorageKey
local originalFormation = _FormationService.StorageKey
local profile = _UserService.UserEntities.Values[1].PlayerComponent.ProfileCode
local storage = _DataStorageService:GetUserDataStorage(profile)
local key = 'Issue65Levels_' .. _UtilLogic:NewGuid()
local function read()
    local done, code, document = false, nil, nil
    service:Read(profile, function(c, d) code, document, done = c, d, true end)
    assert(await(function() return done end), 'read callback')
    return code, document
end
local function settle(id, deaths)
    local operation = service:Settle(profile, id, deaths)
    assert(await(function() return operation.status ~= 'PENDING' end), 'bounded settlement completion')
    return operation
end
local ok, detail = pcall(function()
    service.StorageKey = key
    local code, document = read()
    assert(code == 0 and next(document.monsters) == nil and #document.settled == 0, 'new player defaults')
    local missing, raw = storage:GetAndWait(key)
    assert(missing == 1000002 or (missing == 0 and raw == nil), 'read never creates a key')
    local first = settle('first', {monster_tank=3, monster_warrior=1})
    assert(first.status == 'SAVED', 'first creation')
    local expected = _MonsterProgression:ApplyExperience(1, 0, 3)
    local tank = first.monsters.monster_tank
    assert(tank.gained == 3 and tank.before.level == 1 and tank.after.level == expected.level
        and tank.after.experience == expected.experience, 'retained receipt equals progression module')
    local beforeCode, beforeRaw = storage:GetAndWait(key)
    local duplicate = settle('first', {monster_tank=3})
    local afterCode, afterRaw = storage:GetAndWait(key)
    assert(duplicate.status == 'SAVED' and duplicate.duplicate and beforeCode == 0 and afterCode == 0
        and beforeRaw == afterRaw, 'duplicate leaves exact stored bytes unchanged')
    -- Both writers initially see the same bytes; delayed writes force a native CAS conflict.
    _FormationStorage:ConfigureMakerFaults(0, 0, 1)
    local a = service:Settle(profile, 'parallel-a', {monster_tank=2})
    local b = service:Settle(profile, 'parallel-b', {monster_tank=2})
    assert(await(function() return a.status ~= 'PENDING' and b.status ~= 'PENDING' end), 'both concurrent callbacks')
    _FormationStorage:ConfigureMakerFaults(0, 0, 0)
    code, document = read()
    assert(a.status == 'SAVED' and b.status == 'SAVED' and document.monsters.monster_tank.level == 4
        and document.monsters.monster_tank.experience == 1 and (a.attempts > 1 or b.attempts > 1), 'CAS loser re-reads; both matches credited')
    _FormationStorage:ConfigureMakerFaults(0, 1, 0)
    local retried = settle('failed-write', {monster_tank=1})
    assert(retried.status == 'SAVED' and retried.attempts > 1, 'failed write retries')
    _FormationStorage:ConfigureMakerFaults(0, 0, 7)
    local timed = service:Settle(profile, 'timed-write', {monster_tank=1})
    wait(0.2)
    _FormationStorage:ConfigureMakerFaults(0, 0, 0)
    assert(await(function() return timed.status ~= 'PENDING' end) and timed.status == 'SAVED'
        and timed.attempts > 1, 'write timeout retries before delayed original completes')
    wait(8)
    code, document = read()
    assert(code == 0 and document.monsters.monster_tank.level == 4 and document.monsters.monster_tank.experience == 3,
        'late write cannot double credit or overwrite newer data')
    -- The existing acknowledgement injector targets FormationService.StorageKey; aim it at this disposable key only.
    local formationKey = _FormationService.StorageKey
    _FormationService.StorageKey = key
    _FormationStorage:ConfigureMakerSaveResponse('LATE', 8)
    local lateAck = service:Settle(profile, 'late-ack', {monster_tank=1})
    wait(0.5)
    _FormationStorage:ConfigureMakerSaveResponse('', 0)
    _FormationService.StorageKey = formationKey
    assert(await(function() return lateAck.status ~= 'PENDING' end) and lateAck.status == 'SAVED'
        and lateAck.duplicate and lateAck.monsters.monster_tank.before.level == 4
        and lateAck.monsters.monster_tank.after.level == 5, 'committed write with late ack is confirmed once, with its receipt')
    wait(3)
    code, document = read()
    assert(document.monsters.monster_tank.level == 5 and document.monsters.monster_tank.experience == 0, 'late acknowledgement did not credit twice')
    assert(storage:SetAndWait(key, 'broken-json') == 0, 'corruption fixture')
    code, document = read()
    assert(code ~= 0 and document == nil and settle('corrupt', {monster_tank=1}).status == 'FAILED', 'corrupt read and settlement fail')
    local _, unchanged = storage:GetAndWait(key)
    assert(unchanged == 'broken-json', 'corruption preserved')
    assert(storage:SetAndWait(key, '{"schema":99,"monsters":{},"settled":[]}') == 0, 'unknown schema fixture')
    code, document = read()
    assert(code ~= 0 and document == nil, 'unknown schema rejected')
    assert(storage:DeleteAndWait(key) == 0, 'reset isolated key')
    _FormationStorage:ConfigureMakerFaults(1, 0, 0)
    code, document = read()
    assert(code ~= 0 and document == nil, 'read failure never becomes writable default')
    _FormationStorage:ConfigureMakerFaults(0, 20, 0)
    local exhausted = settle('exhausted', {monster_tank=1})
    assert(exhausted.status == 'FAILED' and exhausted.attempts == service.MaxAttempts, 'retry limit terminates')
    _FormationStorage:ConfigureMakerFaults(0, 0, 0)
    local c, value = storage:GetAndWait(key)
    assert(c == 1000002 or (c == 0 and value == nil), 'exhaustion did not invent progress')
    for index = 1, 22 do assert(settle('history-'..index, {}).status == 'SAVED', 'history settlement') end
    code, document = read()
    assert(#document.settled == 20 and document.settled[1] == 'history-3' and document.settled[20] == 'history-22', 'recent twenty match IDs retained')
    assert(storage:DeleteAndWait(key) == 0, 'reset for concurrent first creation')
    _FormationStorage:ConfigureMakerFaults(0, 0, 1)
    local firstA = service:Settle(profile, 'create-a', {monster_tank=1})
    local firstB = service:Settle(profile, 'create-b', {monster_tank=2})
    assert(await(function() return firstA.status ~= 'PENDING' and firstB.status ~= 'PENDING' end), 'both first creations complete')
    _FormationStorage:ConfigureMakerFaults(0, 0, 0)
    code, document = read()
    assert(firstA.status == 'SAVED' and firstB.status == 'SAVED' and document.monsters.monster_tank.level == 3
        and document.monsters.monster_tank.experience == 0 and #document.settled == 2, 'first-creation guard preserves both settlements')
end)
_FormationStorage:ConfigureMakerFaults(0, 0, 0)
_FormationStorage:ConfigureMakerSaveResponse('', 0)
_FormationService.StorageKey = originalFormation
service.StorageKey = original
local cleanup = storage:DeleteAndWait(key)
if not ok then log('[VRF][LevelStorage65] FAIL '..tostring(detail))
elseif cleanup ~= 0 then log('[VRF][LevelStorage65] FAIL cleanup')
else log('[VRF][LevelStorage65] PASS defaults; calculation; idempotency; concurrent CAS; retry; timeout; corruption; bounds; CLEANUP_PASS') end
