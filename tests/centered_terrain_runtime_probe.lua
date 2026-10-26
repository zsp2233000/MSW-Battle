-- Server: run once in server_main and once in a live matched server_instance_* before returning.
local ok, detail = pcall(function()
    local names = _RoomService:IsInstanceRoom() and {'matchprobe'} or {'template', 'formationsim', 'formationlobby'}
    for _, name in ipairs(names) do
        local tiles = _EntityService:GetEntityByPath('/maps/' .. name .. '/RectTileMap').RectTileMapComponent
        assert(tiles.GridSize == Vector2(1,1) and not tiles.IsOddGridPosition, 'native unit grid')
        local count, total, minX, maxX, minY, maxY = 0, 0, math.huge, -math.huge, math.huge, -math.huge
        for _, cell in ipairs(tiles:GetAllTilePositions():ToTable()) do
            total = total + 1
            local position = tiles:ToWorldPosition(cell)
            if not tiles:GetTile(cell).IsCollidable then
                count = count + 1
                minX, maxX = math.min(minX, position.x - 0.5), math.max(maxX, position.x + 0.5)
                minY, maxY = math.min(minY, position.y - 0.5), math.max(maxY, position.y + 0.5)
                local mirror = tiles:GetTile(tiles:ToCellPosition(Vector3(_FormationMapLayout:MirrorX(position.x), position.y, 0)))
                assert(mirror ~= nil and not mirror.IsCollidable, 'mirrored native tile is walkable')
            end
        end
        assert(total == 209 and count == 153 and maxX-minX == 17 and maxY-minY == 9, 'current 209-tile terrain with 17 by 9 walkable area')
        assert((minX+maxX)/2 == 0.5, 'horizontal reflection center')
        for y = -5, 5 do
            assert(tiles:GetTile(Vector2Int(-9,y)).IsCollidable and tiles:GetTile(Vector2Int(9,y)).IsCollidable, 'symmetric side walls')
        end
        for x = -9, 9 do
            assert(tiles:GetTile(Vector2Int(x,-5)).IsCollidable and tiles:GetTile(Vector2Int(x,5)).IsCollidable, 'outer horizontal walls')
        end
        log('[VRF][CenteredTerrain] PASS map=' .. name .. ' tiles=' .. total .. ' walkable=' .. count .. ' bounds=' .. minX .. ',' .. maxX .. ',' .. minY .. ',' .. maxY .. ' mirror=1-x')
    end
end)
if not ok then log('[VRF][CenteredTerrain] FAIL ' .. tostring(detail)) end
