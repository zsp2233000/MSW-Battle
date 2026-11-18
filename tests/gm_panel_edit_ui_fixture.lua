-- server_main, same Maker Play. Set TOKEN to eight fresh hex digits for all phases.
local TOKEN = ''
local MODE = 'SETUP'
assert(Environment:IsMakerPlay() and TOKEN:match('^%x+$') and #TOKEN == 8, 'Maker and a fresh synthetic token required')
local profile, damaged = 'GM85UI' .. TOKEN, 'GM85BAD' .. TOKEN
local key = 'GM85UILevels'
local service = _GMCommandService
local fixture = service._T.gm85EditFixture
local user = _DataStorageService:GetUserDataStorage(profile)
local corruptUser = _DataStorageService:GetUserDataStorage(damaged)
local audit = _DataStorageService:GetGlobalDataStorage('GMAuditV1')
local function level(value)
    return '{"schema":1,"monsters":{"monster_tank":{"level":' .. value .. ',"experience":0}},"settled":["gm85-ui"]}'
end
local function remove(container, storageKey)
    local code = container:DeleteAndWait(storageKey)
    assert(code == 0 or code == 1000002, 'fixture delete ' .. storageKey)
    local readCode, raw = container:GetAndWait(storageKey)
    assert(readCode == 1000002 or (readCode == 0 and raw == nil), 'fixture gone ' .. storageKey)
end
if MODE == 'SETUP' then
    assert(fixture == nil and not service:IsGM(profile) and not service:IsGM(damaged), 'isolated synthetic players')
    service._T.gm85EditFixture = { key = _MonsterLevelStorage.StorageKey, token = TOKEN }
    assert(user:SetAndWait(key, level(6)) == 0, 'valid UI fixture')
    assert(corruptUser:SetAndWait(key, 'broken <b>literal</b>') == 0, 'corrupt UI fixture')
    _MonsterLevelStorage.StorageKey = key
    log('[VRF][GMPanelEditUIFixture] READY')
    return
end
assert(fixture ~= nil and fixture.token == TOKEN, 'matching fixture required')
if MODE == 'CLEANUP' then
    _MonsterLevelStorage.StorageKey = fixture.key
    remove(user, key)
    remove(corruptUser, key)
    for _, target in ipairs({ profile, damaged }) do
        local code, cursor = audit:GetAndWait(target)
        if code == 0 and cursor ~= nil then
            for slot = 1, assert(tonumber(cursor:match('^(%d+):'))) do
                local prefix = target .. '_' .. slot
                remove(audit, prefix)
                remove(audit, prefix .. '_before')
                remove(audit, prefix .. '_after')
            end
            remove(audit, target)
        else
            assert(code == 1000002 or code == 0, 'read fixture audit cursor')
        end
    end
    service._T.gm85EditFixture = nil
    log('[VRF][GMPanelEditUIFixture] CLEANUP_PASS')
    return
end
assert(MODE == 'CHANGE_FOR_RELOAD' or MODE == 'CHANGE_FOR_FORCE', 'known fixture phase')
assert(user:SetAndWait(key, level(MODE == 'CHANGE_FOR_RELOAD' and 10 or 12)) == 0, 'simulate an external write')
log('[VRF][GMPanelEditUIFixture] ' .. MODE)
