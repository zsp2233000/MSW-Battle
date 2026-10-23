-- Server: run once in server_main and once in a live matched server_instance_* before returning.
local ok, detail = pcall(function()
    local names = _RoomService:IsInstanceRoom() and {'matchprobe'} or {'map01', 'formationsim'}
    for _, name in ipairs(names) do
        local tiles = _EntityService:GetEntityByPath('/maps/' .. name .. '/RectTileMap').RectTileMapComponent
        assert(tiles.GridSize == Vector2(1,1) and not tiles.IsOddGridPosition, 'native unit grid')
        local count, minX, maxX, minY, maxY = 0, math.huge, -math.huge, math.huge, -math.huge
        for _, cell in ipairs(tiles:GetAllTilePositions():ToTable()) do
            local position = tiles:ToWorldPosition(cell)
            if position.y >= -8 and position.y < 8 and not tiles:GetTile(cell).IsCollidable then
                count = count + 1
                minX, maxX = math.min(minX, position.x - 0.5), math.max(maxX, position.x + 0.5)
                minY, maxY = math.min(minY, position.y - 0.5), math.max(maxY, position.y + 0.5)
                local mirror = tiles:GetTile(tiles:ToCellPosition(Vector3(-position.x, position.y, 0)))
                assert(mirror ~= nil and not mirror.IsCollidable, 'mirrored native tile is walkable')
            end
        end
        assert(count == 480 and minX == -15 and maxX == 15 and minY == -8 and maxY == 8, 'exact centered rectangle')
        for y = -9, 8 do
            assert(tiles:GetTile(Vector2Int(-16,y)).IsCollidable and tiles:GetTile(Vector2Int(15,y)).IsCollidable, 'symmetric side walls')
        end
        for x = -16, 15 do
            assert(tiles:GetTile(Vector2Int(x,-9)).IsCollidable and tiles:GetTile(Vector2Int(x,8)).IsCollidable, 'outer horizontal walls')
        end
        log('[VRF][CenteredTerrain] PASS map=' .. name .. ' walkable=480 bounds=-15,15,-8,8 centre=0,0')
    end
end)
if not ok then log('[VRF][CenteredTerrain] FAIL ' .. tostring(detail)) end
