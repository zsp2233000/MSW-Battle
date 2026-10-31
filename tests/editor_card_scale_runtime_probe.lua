-- Client: whole-card scale changes hit bounds and nested visuals without accumulating or changing authored text.
local lobby = _FormationLobby
for _ = 1, 100 do
    if #(lobby._T.cards or {}) > 0 then break end
    wait(.1)
end
local catalog = lobby:Ui('Editor/Catalog')
local sizing = catalog.FormationCardLayout
local originalScale = sizing.CardScale
local originalSelection = lobby.SelectedMonsterId
local originalMap = _UserService.LocalPlayer.CurrentMapName
local template = catalog:GetChildByName('Template')
local baseSize = sizing._T.size
local baseFont = template:GetChildByName('MonsterName').TextGUIRendererComponent.FontSize
local baseGap = catalog.ScrollLayoutGroupComponent.GridSpacing
local function close(a,b) return math.abs(a-b) < .02 end
local function width(entity)
    local corners = entity.UITransformComponent:GetWorldCorners()
    return math.abs(corners[3].x-corners[1].x)
end
local ok, detail = pcall(function()
    lobby:Travel('formationsim')
    for _ = 1, 100 do
        if _UserService.LocalPlayer.CurrentMapName == 'formationsim' then break end
        wait(.1)
    end
    assert(_UserService.LocalPlayer.CurrentMapName == 'formationsim', 'editor opened')
    wait(.3)
    local card = lobby._T.cards[1].entity
    local frameWidth = width(card)
    for _, scale in ipairs({.85,.65,1,.85}) do
        sizing.CardScale = scale
        sizing:Apply()
        wait(.15)
        local cell = catalog.ScrollLayoutGroupComponent.CellSize
        assert(close(cell.x,baseSize.x*scale) and close(cell.y,baseSize.y*scale), 'scaled cell')
        assert(close(width(card)/frameWidth,scale/originalScale), 'frame and hit target scale once')
        for _, entry in ipairs(lobby._T.cards) do
            for _, part in ipairs(sizing._T.parts) do
                local transform = entry.entity:GetChildByName(part.name).UITransformComponent
                assert(close(transform.UIScale.x,part.scale.x*scale) and close(transform.UIScale.y,part.scale.y*scale),
                    part.name .. ' scales with frame')
                assert(close(transform.anchoredPosition.x,part.pos.x*scale) and close(transform.anchoredPosition.y,part.pos.y*scale),
                    part.name .. ' keeps proportional placement')
            end
        end
        assert(card:GetChildByName('MonsterName',true).TextGUIRendererComponent.FontSize == baseFont, 'authored font retained')
        assert(sizing._T.size == baseSize, 'authoring baseline retained')
        assert(catalog.ScrollLayoutGroupComponent.GridSpacing == baseGap, 'authored gaps retained')
    end
    card:SendEvent(ButtonClickEvent())
    assert(lobby.SelectedMonsterId == lobby._T.cards[1].monsterId, 'card remains selectable')
    lobby._T.optionsKey = ''
    lobby:BuildOptions(lobby.Snapshot.options)
    wait(.15)
    assert(close(width(lobby._T.cards[1].entity)/frameWidth,.85/originalScale), 'rebuilt cards keep chosen scale')
    sizing.CardScale = -1
    sizing:Apply()
    assert(close(catalog.ScrollLayoutGroupComponent.CellSize.x,baseSize.x*.5), 'invalid small scale is bounded')
end)
sizing.CardScale = originalScale
sizing:Apply()
lobby.SelectedMonsterId = originalSelection
lobby:Render()
if originalMap ~= _UserService.LocalPlayer.CurrentMapName then lobby:Travel(originalMap) end
log(ok and '[VRF][CardScaleProbe] PASS frame, art, text, hit bounds, selection, rebuild and non-cumulative scale'
    or '[VRF][CardScaleProbe] FAIL '..tostring(detail))
