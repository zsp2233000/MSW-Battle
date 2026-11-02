-- server_main，單玩家且無儲存進行中的全新 Play；不呼叫儲存或故障注入 API，也不改 StorageKey。
-- pending 使用暫時的記憶體夾具；所有請求都必須在派送寫入前被拒絕。
local service = _FormationService
local record = nil
local previousResult, previousMessage = nil, nil
local captured = false
local function await(predicate)
    for _ = 1, 150 do
        if predicate() then return true end
        wait(0.1)
    end
    return false
end
local function rejected(name, units, slotId, revision, reason)
    local before = _FormationSchema:EncodeDocument(record.saved)
    local raw, epoch, pending = record.raw, record.writeEpoch, record.pending
    local writer = service._T.writers[record.profile]
    local id = _UtilLogic:NewGuid()
    service:SaveForUser(record.userId, units, slotId, revision, id)
    local result = record.result
    assert(result ~= nil and result.requestId == id and result.kind == 'SAVE'
        and result.slotId == slotId and result.status == 'REJECTED', name .. ' 拒絕回覆可正確關聯')
    assert(string.find(record.message, reason, 1, true) ~= nil, name .. ' 拒絕原因正確')
    assert(_FormationSchema:EncodeDocument(record.saved) == before and record.raw == raw, name .. ' 五組內容、版本與出戰選擇不變')
    assert(record.writeEpoch == epoch and record.pending == pending and service._T.writers[record.profile] == writer, name .. ' 未派送新寫入或解除既有鎖')
    log('[VRF][Save50R] ' .. name .. ' REJECTED unchanged=true')
end

local ok, detail = pcall(function()
    assert(Environment:IsMakerPlay(), '限 Maker Play')
    local users = _UserService.UserEntities.Values
    assert(#users == 1, '只允許單玩家驗證')
    record = service:GetSession(users[1].PlayerComponent.UserId)
    assert(record ~= nil, '玩家 session 存在')
    assert(await(function() return record.loadState == 'NEW' or record.loadState == 'READY' end), '初始讀取成功')
    assert(not record.pending and not record.transferLocked and service._T.writers[record.profile] == nil, '沒有儲存或交接進行中')
    previousResult, previousMessage = record.result, record.message
    captured = true
    local catalog = service:GetCatalog()
    local monsterId = catalog:GetDeploymentOptions()[1].monsterId
    local revision = record.saved.slots[tostring(record.editSlot)].revision
    local units = {{monsterId = monsterId, x = -5, y = 0}}
    assert(_FormationSchema:ValidateUnits(units, catalog, false) ~= nil, '單位夾具合法')
    rejected('stale-revision', units, record.editSlot, revision - 1, '版本已更新')
    local seven = {}
    for index = 1, 7 do seven[index] = {monsterId = monsterId, x = -7 + (index - 1) * 0.5, y = 1} end
    assert(_FormationSchema:ValidateUnits({seven[1], seven[2], seven[3], seven[4], seven[5], seven[6]}, catalog, false) ~= nil, '前六單位合法，排除地形或間距造成的拒絕')
    rejected('seven-units', seven, record.editSlot, revision, '一至六個單位')
    local otherSlot = record.editSlot == 1 and 2 or 1
    rejected('wrong-slot', units, otherSlot, record.saved.slots[tostring(otherSlot)].revision, '目前選取的組別')
    record.pending = true
    rejected('pending', units, record.editSlot, revision, '尚未完成')
end)

if captured then
    record.pending = false
    record.result, record.message = previousResult, previousMessage
    service:Publish(record)
end
log(ok and '[VRF][Save50R] PASS' or ('[VRF][Save50R] FAIL ' .. tostring(detail)))
