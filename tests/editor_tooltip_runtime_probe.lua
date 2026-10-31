-- Client: native hover subscriptions, isolated previews and popup lifecycle; no storage writes.
local l = _FormationLobby
local ok, detail = pcall(function()
    for _=1,100 do if #(l.Snapshot.options or {}) > 1 then break end wait(.1) end
    l:Travel('formationsim')
    for _=1,100 do if _UserService.LocalPlayer.CurrentMapName == 'formationsim' then break end wait(.1) end
    wait(.3)
    local selected, unit = l.SelectedMonsterId, l.SelectedUnit
    local first, second = l._T.cards[1].entity, l._T.cards[2].entity
    local popup = l:Ui('CardTooltip')
    assert(not popup.Enable, 'hidden before hover')
    first:SendEvent(UITouchEnterEvent())
    assert(popup.EnabledInHierarchy, 'enter shows tooltip')
    assert(l:Ui('CardTooltip/Name').TextGUIRendererComponent.Text == l.Snapshot.options[1][2], 'hovered name')
    for index, field in ipairs({'Health','Damage','Interval','Range'}) do
        local value = l:Ui('CardTooltip/Stats/'..field..'/Value').TextGUIRendererComponent.Text
        assert(string.find(value,tostring(l.Snapshot.options[1][index+4]),1,true), 'hovered value '..field)
    end
    assert(l.SelectedMonsterId == selected and l.SelectedUnit == unit, 'hover preserves selection')
    second:SendEvent(UITouchEnterEvent())
    first:SendEvent(UITouchExitEvent())
    assert(popup.Enable and l._T.hoverCard == second, 'late exit cannot hide next card')
    second:SendEvent(UITouchExitEvent())
    assert(not popup.Enable, 'exit hides tooltip')
    first:SendEvent(UITouchEnterEvent())
    l._T.editorCollapsed = true
    l:Render()
    l:UpdateCardTooltip()
    assert(not popup.Enable, 'collapse hides tooltip')
    l._T.editorCollapsed = false
    l:Render()
    first:SendEvent(UITouchEnterEvent())
    local p,s = popup.UITransformComponent.anchoredPosition,popup.UITransformComponent.RectSize
    local canvas = l.root.UITransformComponent.RectSize
    assert(p.x >= -canvas.x/2 and p.x+s.x <= canvas.x/2
        and p.y <= canvas.y/2 and p.y-s.y >= -canvas.y/2, 'popup stays inside canvas')
    assert(not popup.CanvasGroupComponent.BlocksRaycasts, 'popup cannot intercept pointer')
    l._T.optionsKey = ''
    l:BuildOptions(l.Snapshot.options)
    assert(not popup.Enable and l._T.hoverCard == nil, 'rebuild clears stale hover')
end)
l._T.editorCollapsed = false
l._T.hoverCard = nil
l:SetEnabled('CardTooltip', false)
l:Render()
log(ok and '[VRF][CardTooltip] PASS hover data, independent selection, exit, collapse, bounds and rebuild'
    or '[VRF][CardTooltip] FAIL '..tostring(detail))
