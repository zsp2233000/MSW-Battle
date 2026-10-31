-- Client: native grid dimensions drive the authored card subtree without runtime resizing code.
local l = _FormationLobby
for _ = 1, 100 do if #(l._T.cards or {}) > 0 then break end wait(.1) end
local layout = l:Ui('Editor/Catalog').ScrollLayoutGroupComponent
local original = layout.CellSize
local map = _UserService.LocalPlayer.CurrentMapName
local selected = l.SelectedMonsterId
local function close(a,b) return math.abs(a-b)<.05 end
local ok, detail = pcall(function()
    l:Travel('formationsim')
    for _ = 1, 100 do if _UserService.LocalPlayer.CurrentMapName == 'formationsim' then break end wait(.1) end
    assert(_UserService.LocalPlayer.CurrentMapName == 'formationsim','editor opened')
    for _, size in ipairs({Vector2(149,216),Vector2(181,263),Vector2(213,309),original}) do
        layout.CellSize = size
        for _ = 1, 30 do
            local ready = true
            for _, entry in ipairs(l._T.cards) do
                entry.entity.UITransformComponent:GetWorldCorners()
                if not close(entry.entity.UITransformComponent.RectSize.x,size.x) then ready = false end
            end
            if ready then break end
            wait(.1)
        end
        for _, entry in ipairs(l._T.cards) do
            local card = entry.entity
            card:GetChildByName('CardSign').UITransformComponent:GetWorldCorners()
            card:GetChildByName('MonsterName').UITransformComponent:GetWorldCorners()
            card:GetChildByName('SelectedGlow').UITransformComponent:GetWorldCorners()
            local sign = card:GetChildByName('CardSign').UITransformComponent.RectSize
            local name = card:GetChildByName('MonsterName').UITransformComponent.RectSize
            local glow = card:GetChildByName('SelectedGlow').UITransformComponent.RectSize
            local viewport = card:GetChildByName('PortraitViewport')
            viewport:GetChildByName('Portrait').UITransformComponent:GetWorldCorners()
            local portrait = viewport:GetChildByName('Portrait').UITransformComponent.RectSize
            assert(close(card.UITransformComponent.RectSize.x,size.x),'native hit bounds')
            assert(close(sign.x,size.x+13.5) and close(sign.y,size.y+9),'ornament follows parent')
            assert(close(name.x,size.x-24) and close(name.y,28),'name follows width and keeps readable height')
            assert(close(glow.x,size.x) and close(glow.y,size.y),'selection follows parent')
            assert(portrait.x>=100 and portrait.y>=100,'portrait stays readable at 149x216')
            local artCorners = viewport:GetChildByName('Portrait').UITransformComponent:GetWorldCorners()
            local nameCorners = card:GetChildByName('MonsterName').UITransformComponent:GetWorldCorners()
            local kindCorners = card:GetChildByName('Identity').UITransformComponent:GetWorldCorners()
            assert(artCorners[1].y > nameCorners[2].y,'portrait stays above name')
            assert(nameCorners[1].y > kindCorners[2].y,'name stays above kind')
            assert(card:GetChildByName('MonsterName').TextGUIRendererComponent.BestFit,'name auto fits')
        end
    end
    local card = l._T.cards[1]
    card.entity:SendEvent(ButtonClickEvent())
    assert(l.SelectedMonsterId==card.monsterId,'selection works')
    layout.CellSize = Vector2(181,263)
    l._T.optionsKey = ''
    l:BuildOptions(l.Snapshot.options)
    wait(.3)
    l._T.cards[1].entity:GetChildByName('MonsterName').UITransformComponent:GetWorldCorners()
    assert(close(layout.CellSize.x,181),'rebuild preserves authored cell size')
    assert(close(l._T.cards[1].entity:GetChildByName('MonsterName').UITransformComponent.RectSize.x,157),'rebuilt content fits')
end)
layout.CellSize = original
l.SelectedMonsterId = selected
l:Render()
if _UserService.LocalPlayer.CurrentMapName ~= map then l:Travel(map) end
log(ok and '[VRF][CardResize] PASS 149x216 through 213x309, readable art, separated labels, selection and rebuild'
    or '[VRF][CardResize] FAIL '..tostring(detail))
