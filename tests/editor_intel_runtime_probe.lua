-- Client: production card events, formal catalog snapshot and map selection; no storage writes.
local l = _FormationLobby
local function await(predicate)
    for _ = 1, 100 do if predicate() then return true end wait(0.1) end
    return false
end
local function click(path) l:Ui(path):SendEvent(ButtonClickEvent()) end
local ok, detail = pcall(function()
    assert(await(function() return #(l.Snapshot.options or {}) > 0 end), 'catalog loaded')
    if _UserService.LocalPlayer.CurrentMapName == 'formationlobby' then click('Lobby/Edit') end
    assert(await(function() return _UserService.LocalPlayer.CurrentMapName == 'formationsim' end), 'formal editor entered')
    wait(0.3)
    assert(isvalid(l:Ui('Editor/Intel/Stats')), 'visible tactical intelligence exists')
    for _, path in ipairs({'Slots','Header','CatalogDock','Catalog','Intel','Save','Activate','AddMode','Remove','Back','ToggleUnits','Units','Title','Summary','Help','Roster','Selection'}) do
        local rect = l:Ui('Editor/'..path).UITransformComponent
        assert(rect.anchoredPosition.x >= 960, path..' leaves the left deployment half clear')
        assert(rect.anchoredPosition.x + rect.RectSize.x <= 1920
            and -rect.anchoredPosition.y + rect.RectSize.y <= 1080, path..' remains inside the reference screen')
    end
    local kinds = { TANK='坦克', ASSAULT='戰士', SHOOTER='射手' }
    for index, option in ipairs(l.Snapshot.options) do
        click('Editor/Catalog/Monster' .. tostring(index))
        assert(l.SelectedMonsterId == option[1] and l.SelectedUnit == 0, 'card selects stable MonsterId')
        local stats = l:Ui('Editor/Intel/Stats').TextGUIRendererComponent.Text
        assert(string.find(stats, kinds[option[4]], 1, true), 'formal monster kind')
        for _, value in ipairs({option[5], option[6], option[7], option[8]}) do
            assert(value ~= nil and string.find(stats, tostring(value), 1, true), 'formal combat statistic shown')
        end
        assert(l:Ui('Editor/Intel/Name').TextGUIRendererComponent.Text == option[2], 'formal name shown')
    end
    local units = l.Snapshot.draft
    if #units > 0 then
        local unit = units[1]
        _UserService.LocalPlayer.CurrentMap:GetComponent('FormationMapInput'):HandleWorldClick(Vector3(unit.x, unit.y, 0))
        assert(l.SelectedUnit == 1, 'world unit selection')
        assert(l:Ui('Editor/Intel/Name').TextGUIRendererComponent.Text == l:MonsterName(unit.monsterId), 'intel follows selected unit')
    end
    assert(not l:Ui('Editor/Units').Enable, 'technical coordinates start collapsed')
    click('Editor/ToggleUnits')
    assert(l:Ui('Editor/Units').Enable, 'details reachable')
    click('Editor/ToggleUnits')
    assert(l:Ui('Editor/Save').Enable and l:Ui('Editor/Remove').Enable, 'common actions visible without details')
    assert(l:Ui('Editor/Remove').ButtonComponent.Enable == (l.SelectedUnit > 0), 'remove requires a selected unit')
    for _, pair in ipairs({{'Editor/Header','Editor/Title'},{'Editor/Intel','Editor/Save'},{'Editor/CatalogDock','Editor/Catalog'}}) do
        assert(_UILogic:GetSiblingIndex(l:Ui(pair[1]).UITransformComponent)
            < _UILogic:GetSiblingIndex(l:Ui(pair[2]).UITransformComponent), 'background stays behind content')
    end
end)
log(ok and '[VRF][EditorIntel] PASS' or '[VRF][EditorIntel] FAIL ' .. tostring(detail))
