-- Server_main after a connected player has saved and activated a V2 formation.
local ok, detail = pcall(function()
    local userId, transfer
    for _, user in ipairs(_UserService.UserEntities.Values) do
        local captured = _FormationService:CaptureTransfer(user.PlayerComponent.UserId)
        if captured ~= nil then userId, transfer = user.PlayerComponent.UserId, captured break end
    end
    assert(transfer ~= nil, 'requires a loaded formation')
    transfer.coordinateSchema = nil
    assert(not _FormationService:ImportTransfer(userId, transfer), 'legacy handoff rejected')
    transfer.coordinateSchema = 2
    local saved = transfer.saved
    transfer.saved = string.gsub(saved, '"schema":2', '"schema":1', 1)
    assert(not _FormationService:ImportTransfer(userId, transfer), 'legacy saved schema rejected')
    transfer.saved = saved
    local slot = tostring(transfer.editSlot)
    local draft = _HttpService:JSONDecode(transfer.drafts)[slot]
    local tiles = _EntityService:GetEntityByPath('/maps/map01/RectTileMap').RectTileMapComponent
    local original = tiles:ToCellPosition(Vector3(-2.25,0.25,0))
    local mirror = tiles:ToCellPosition(Vector3(_FormationMapLayout:MirrorX(-2.25),0.25,0))
    local originalName, mirrorName = tiles:GetTile(original).Name, tiles:GetTile(mirror).Name
    local function reject(label)
        _FormationService:UpdateDraftForUser(userId, {{monsterId='monster_tank',x=-2.25,y=0.25}}, draft.version, transfer.editSlot)
        local after = _FormationService:CaptureTransfer(userId)
        assert(_HttpService:JSONDecode(after.drafts)[slot].version == draft.version, label)
    end
    local tested, reason = pcall(function()
        tiles:RemoveTile(original)
        reject('missing original rejected')
        tiles:SetTile(originalName, original)
        tiles:RemoveTile(mirror)
        reject('missing mirror rejected')
        tiles:SetTile('Baram_10048', mirror)
        reject('mirror wall rejected')
    end)
    tiles:SetTile(originalName, original)
    tiles:SetTile(mirrorName, mirror)
    assert(tested, tostring(reason))
    log('[VRF][CenteredTransfer] PASS old handoffs and invalid original/mirror terrain rejected; native tiles restored')
end)
if not ok then log('[VRF][CenteredTransfer] FAIL ' .. tostring(detail)) end
