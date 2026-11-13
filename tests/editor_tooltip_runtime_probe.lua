-- Client; run with the same SEEDED mode as editor_intel and the isolated server fixture.
local SEEDED = true
local expected = SEEDED and {
    monster_tank = {5, 3, 456, 9, 13}, monster_shooter = {30, 0, 241, 64, 96},
    monster_warrior = {1, 0, 220, 20, 30},
} or {monster_tank = {1, 0, 400, 8, 12}, monster_shooter = {1, 0, 120, 32, 48}, monster_warrior = {1, 0, 220, 20, 30}}
local l = _FormationLobby
local ok, detail = pcall(function()
    for _=1,100 do if #(_FormationEditSession.Snapshot.options or {}) > 1 then break end wait(.1) end
    l:Travel('formationsim')
    for _=1,100 do if _UserService.LocalPlayer.CurrentMapName == 'formationsim' then break end wait(.1) end
    wait(.3)
    local selected, unit = _FormationEditSession.SelectedMonsterId, _FormationEditSession.SelectedUnit
    assert(_FormationEditSession.Snapshot.levelLoadState == 'READY', 'personal levels loaded')
    local first, second = l:Ui('Editor/Catalog/Monster1'), l:Ui('Editor/Catalog/Monster2')
    local popup = l:Ui('CardTooltip')
    assert(not popup.Enable, 'hidden before hover')
    for index, option in ipairs(_FormationEditSession.Snapshot.options) do
        l:Ui('Editor/Catalog/Monster'..index):SendEvent(UITouchEnterEvent())
        local progress = assert(expected[option.monsterId], 'formal fixture monster')
        local label = 'Lv.'..progress[1]..' '..(progress[1] == 30 and 'MAX' or (progress[2]..'/'..progress[1]))
        assert(string.find(l:Ui('CardTooltip/Kind').TextGUIRendererComponent.Text, label, 1, true), 'hovered saved level and experience')
        assert(l:Ui('CardTooltip/Stats/Health/Value').TextGUIRendererComponent.Text == tostring(progress[3]), 'hovered scaled health')
        assert(l:Ui('CardTooltip/Stats/Damage/Value').TextGUIRendererComponent.Text == progress[4]..'～'..progress[5], 'hovered scaled damage')
        l:Ui('Editor/Catalog/Monster'..index):SendEvent(UITouchExitEvent())
    end
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
    assert(popup.Enable and l:Ui('CardTooltip/Name').TextGUIRendererComponent.Text == _FormationEditSession.Snapshot.options[2].monsterName, 'late exit cannot hide next card')
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
    _FormationCatalogCards:BuildOptions({})
    _FormationCatalogCards:BuildOptions(_FormationEditSession.Snapshot.options)
    assert(not popup.Enable, 'rebuild clears stale hover')
end)
_FormationEditorSlide.Collapsed = false
l:SetEnabled('CardTooltip', false)
l:Render()
log(ok and '[VRF][CardTooltip] PASS hover data, independent selection, exit, collapse, bounds and rebuild'
    or '[VRF][CardTooltip] FAIL '..tostring(detail))
