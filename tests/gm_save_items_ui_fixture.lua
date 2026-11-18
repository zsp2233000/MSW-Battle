-- server_main. Use the same fresh eight-digit hexadecimal TOKEN in the client probe.
local TOKEN = ''
local CLEANUP = false
assert(Environment:IsMakerPlay() and #TOKEN == 8 and TOKEN:match('^%x+$'), 'Maker and synthetic token required')
local profile = 'GM87UI' .. TOKEN
local formationKey, handoffKey = _FormationService.StorageKey, _FormationHandoff.StorageKey
local user = _DataStorageService:GetUserDataStorage(profile)
local audit = _DataStorageService:GetGlobalDataStorage('GMAuditV1')
local function remove(container, key)
    local code = container:DeleteAndWait(key)
    assert(code == 0 or code == 1000002, 'delete fixture key ' .. key)
    local readCode, raw = container:GetAndWait(key)
    assert(readCode == 1000002 or (readCode == 0 and raw == nil), 'fixture key gone ' .. key)
end
if CLEANUP then
    remove(user, formationKey)
    remove(user, handoffKey)
    local code, cursor = audit:GetAndWait(profile)
    assert(code == 0 or code == 1000002, 'read fixture audit cursor')
    if cursor ~= nil then
        for slot = 1, assert(tonumber(cursor:match('^(%d+):'))) do
            local prefix = profile .. '_' .. slot
            for _, suffix in ipairs({'', '_before', '_after'}) do remove(audit, prefix .. suffix) end
        end
        remove(audit, profile)
    end
    log('[VRF][GMSaveItemsUIFixture] CLEANUP_PASS')
    return
end
for _, key in ipairs({formationKey, handoffKey}) do
    local code, raw = user:GetAndWait(key)
    assert(code == 1000002 or (code == 0 and raw == nil), 'expected fresh synthetic fixture')
end
assert(user:SetAndWait(formationKey, 'broken <b>literal</b>') == 0, 'setup malformed formation')
assert(user:SetAndWait(handoffKey, '{"state":"TRANSFER","probe":true}') == 0, 'setup read-only handoff')
log('[VRF][GMSaveItemsUIFixture] READY ' .. profile)
