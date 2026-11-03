-- Client: native hover subscriptions, isolated previews and popup lifecycle; no storage writes.
local l = _FormationLobby
local ok, detail = pcall(function()
    for _=1,100 do if #(_FormationEditSession.Snapshot.options or {}) > 1 then break end wait(.1) end
    l:Travel('formationsim')
    for _=1,100 do if _UserService.LocalPlayer.CurrentMapName == 'formationsim' then break end wait(.1) end
    wait(.3)
    local selected, unit = _FormationEditSession.SelectedMonsterId, _FormationEditSession.SelectedUnit
    local first, second = _FormationCatalogCards._T.cards[1].entity, _FormationCatalogCards._T.cards[2].entity
    local popup = l:Ui('CardTooltip')
    assert(not popup.Enable, 'hidden before hover')
    first:SendEvent(UITouchEnterEvent())
    assert(popup.EnabledInHierarchy, 'enter shows tooltip')
    assert(l:Ui('CardTooltip/Name').TextGUIRendererComponent.Text == _FormationEditSession.Snapshot.options[1].monsterName, 'hovered name')
    for index, field in ipairs({'Health','Damage','Interval','Range'}) do
        local value = l:Ui('CardTooltip/Stats/'..field..'/Value').TextGUIRendererComponent.Text
        local option = _FormationEditSession.Snapshot.options[1]
        local expected = option[({'maxHp','attackDamageMin','attackInterval','attackRange'})[index]]
        if field == 'Damage' then expected = string.format('%d～%d', option.attackDamageMin, option.attackDamageMax) end
        assert(string.find(value,tostring(expected),1,true), 'hovered value '..field)
        if field == 'Damage' then assert(value == expected, 'complete hovered damage interval') end
    end
    assert(_FormationEditSession.SelectedMonsterId == selected and _FormationEditSession.SelectedUnit == unit, 'hover preserves selection')
    second:SendEvent(UITouchEnterEvent())
    first:SendEvent(UITouchExitEvent())
    assert(popup.Enable and _FormationCatalogCards._T.hoverCard == second, 'late exit cannot hide next card')
    second:SendEvent(UITouchExitEvent())
    assert(not popup.Enable, 'exit hides tooltip')
    first:SendEvent(UITouchEnterEvent())
    _FormationEditorSlide.Collapsed = true
    l:Render()
    _FormationCatalogCards:UpdateCardTooltip()
    assert(not popup.Enable, 'collapse hides tooltip')
    _FormationEditorSlide.Collapsed = false
    l:Render()
    first:SendEvent(UITouchEnterEvent())
    local p,s = popup.UITransformComponent.anchoredPosition,popup.UITransformComponent.RectSize
    local canvas = l.root.UITransformComponent.RectSize
    assert(p.x >= -canvas.x/2 and p.x+s.x <= canvas.x/2
        and p.y <= canvas.y/2 and p.y-s.y >= -canvas.y/2, 'popup stays inside canvas')
    assert(not popup.CanvasGroupComponent.BlocksRaycasts, 'popup cannot intercept pointer')
    _FormationCatalogCards._T.optionsKey = ''
    _FormationCatalogCards:BuildOptions(_FormationEditSession.Snapshot.options)
    assert(not popup.Enable and _FormationCatalogCards._T.hoverCard == nil, 'rebuild clears stale hover')
end)
_FormationEditorSlide.Collapsed = false
_FormationCatalogCards._T.hoverCard = nil
l:SetEnabled('CardTooltip', false)
l:Render()
log(ok and '[VRF][CardTooltip] PASS hover data, independent selection, exit, collapse, bounds and rebuild'
    or '[VRF][CardTooltip] FAIL '..tostring(detail))
