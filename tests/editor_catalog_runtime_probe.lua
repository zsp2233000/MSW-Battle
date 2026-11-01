-- Client, guarded 18-row MonsterData fixture: identity, intelligence, real scrolling and last-row selection.
local l = _FormationLobby
local function await(predicate)
    for _=1,300 do if predicate() then return true end wait(.1) end
    return false
end
local ok, detail = pcall(function()
    assert(await(function() return #(_FormationEditSession.Snapshot.options or {}) == 18 end), 'formal overflow catalog received')
    if _UserService.LocalPlayer.CurrentMapName == 'formationlobby' then l:Ui('Lobby/Edit'):SendEvent(ButtonClickEvent()) end
    assert(await(function() return _UserService.LocalPlayer.CurrentMapName == 'formationsim' end), 'editor entered')
    wait(.3)
    local byId = {}
    for index, option in ipairs(_FormationEditSession.Snapshot.options) do
        byId[option[1]] = {index=index,option=option}
    end
    for id, expected in pairs({monster_tank={'RenamedTank',300,10,2,.65},probe_tank_variant={'VariantTank',650,25,1.3,.8}}) do
        local row = byId[id]
        l:Ui('Editor/Catalog/Monster'..row.index):SendEvent(ButtonClickEvent())
        assert(_FormationEditSession.SelectedMonsterId == id, 'same-type stable identity selected')
        assert(l:Ui('Editor/Intel/Name').TextGUIRendererComponent.Text == expected[1], 'renamed formal name')
        for index, field in ipairs({'Health','Damage','Interval','Range'}) do
            local stats=l:Ui('Editor/Intel/Stats/'..field..'/Value').TextGUIRendererComponent.Text
            assert(string.find(stats,tostring(expected[index+1]),1,true), 'independent profile stat')
        end
    end
    local layout=l:Ui('Editor/Catalog').ScrollLayoutGroupComponent
    layout:ResetScrollPosition(UITransformAxis.Vertical)
    wait(.2)
    log('[VRF][EditorCatalog] WHEEL_READY cursor=(1305,600) delta=-1 x60, 250ms apart; right viewport gap')
    assert(await(function() return layout:GetScrollNormalizedPosition().y > .8 end), 'native mouse wheel reaches last row')
    local last=_FormationEditSession.Snapshot.options[18]
    local card=l:Ui('Editor/Catalog/Monster18')
    card:SendEvent(ButtonClickEvent())
    assert(_FormationEditSession.SelectedMonsterId == last[1] and l:Ui('Editor/Intel/Name').TextGUIRendererComponent.Text == last[2], 'last card reachable and correct')
    assert(card:GetChildByName('SelectedGlow').Enable, 'last row selection feedback')
end)
log(ok and '[VRF][EditorCatalog] PASS' or '[VRF][EditorCatalog] FAIL '..tostring(detail))
