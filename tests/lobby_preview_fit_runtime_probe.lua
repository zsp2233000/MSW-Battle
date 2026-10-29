-- Client: select a saved group with at least two units; catches white backgrounds and portrait overlap.
local ok, detail = pcall(function()
    local l = _FormationLobby
    for attempt = 1, 100 do if l:HasValidActive() then break end wait(0.1) end
    assert(l:HasValidActive(), 'valid saved active fixture')
    local units = l.Snapshot.saved.slots[tostring(l.Snapshot.editSlot)].units
    assert(#units >= 2, 'use the crowded saved formation shown in the bug report')
    local opaque, overlaps = 0, 0
    local rectangles = {}
    for index = 1, #units do
        local marker = l:Ui('Lobby/Command/Field/Unit' .. tostring(index))
        local background = marker:GetComponent('SpriteGUIRendererComponent')
        if isvalid(background) and background.Enable and background.Color.a > 0 then opaque = opaque + 1 end
        local portrait = marker:GetChildByName('Portrait', false)
        local pos, offset, size = marker.UITransformComponent.anchoredPosition, portrait.UITransformComponent.anchoredPosition, portrait.UITransformComponent.RectSize
        rectangles[index] = {x=pos.x+offset.x, y=pos.y+offset.y, w=size.x, h=size.y}
    end
    for first = 1, #rectangles do
        for second = first + 1, #rectangles do
            local a, b = rectangles[first], rectangles[second]
            if math.abs(a.x-b.x) < (a.w+b.w)/2 and math.abs(a.y-b.y) < (a.h+b.h)/2 then overlaps = overlaps + 1 end
        end
    end
    log('[VRF][LobbyPreviewFit] opaqueBackgrounds=' .. tostring(opaque) .. ' overlappingPairs=' .. tostring(overlaps))
    assert(opaque == 0 and overlaps == 0, 'no white backing or overlapping monster portraits')
    local field = l:Ui('Lobby/Command/Field').UITransformComponent.RectSize
    local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
    for _, rect in ipairs(rectangles) do
        minX, maxX = math.min(minX, rect.x), math.max(maxX, rect.x)
        minY, maxY = math.min(minY, rect.y), math.max(maxY, rect.y)
        assert(math.abs(rect.x) + rect.w/2 <= field.x/2-48, 'portrait stays inside horizontal frame')
        assert(rect.y + rect.h/2 <= field.y/2-48 and rect.y-rect.h/2 >= -field.y/2+64, 'portrait clears frame and footer')
    end
    assert(maxX-minX >= field.x*0.5 or maxY-minY >= field.y*0.5, 'formation uses the available preview instead of a small central cluster')
    for first = 1, #units do
        for second = first+1, #units do
            local dx, dy = units[second].x-units[first].x, units[second].y-units[first].y
            local sx, sy = rectangles[second].x-rectangles[first].x, rectangles[second].y-rectangles[first].y
            assert(math.abs(sx*dy-sy*dx) < 0.02 and sx*dx+sy*dy > 0, 'uniform projection preserves real relative placement')
        end
    end
    log('[VRF][LobbyPreviewFit] PASS transparent backgrounds; fitted formation; no portrait overlap; true relative placement')
end)
if not ok then log('[VRF][LobbyPreviewFit] FAIL ' .. tostring(detail)) end
