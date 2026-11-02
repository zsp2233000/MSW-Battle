-- Client: production card events, formal catalog snapshot and map selection; no storage writes.
local l = _FormationLobby
local function await(predicate)
    for _ = 1, 100 do if predicate() then return true end wait(0.1) end
    return false
end
local function click(path) l:Ui(path):SendEvent(ButtonClickEvent()) end
local ok, detail = pcall(function()
    assert(await(function() return #(_FormationEditSession.Snapshot.options or {}) > 0 end), 'catalog loaded')
    if _UserService.LocalPlayer.CurrentMapName == 'formationlobby' then click('Lobby/Edit') end
    assert(await(function() return _UserService.LocalPlayer.CurrentMapName == 'formationsim' end), 'formal editor entered')
    wait(0.3)
    assert(isvalid(l:Ui('Editor/Intel/Stats')), 'visible tactical intelligence exists')
    for _, path in ipairs({'Slots','CatalogDock','Catalog','Intel'}) do
        local rect = l:Ui('Editor/'..path).UITransformComponent
        assert(rect.anchoredPosition.x >= 960, path..' leaves the left deployment half clear')
        assert(rect.anchoredPosition.x + rect.RectSize.x <= 1920
            and -rect.anchoredPosition.y + rect.RectSize.y <= 1080, path..' remains inside the reference screen')
    end
    local kinds = { TANK='坦克', ASSAULT='戰士', SHOOTER='射手' }
    for index, option in ipairs(_FormationEditSession.Snapshot.options) do
        click('Editor/Catalog/Monster' .. tostring(index))
        assert(_FormationEditSession.SelectedMonsterId == option.monsterId and _FormationEditSession.SelectedUnit == 0, 'card selects stable MonsterId')
        for otherIndex, other in ipairs(_FormationEditSession.Snapshot.options) do
            local card = l:Ui('Editor/Catalog/Monster' .. tostring(otherIndex))
            local selected = other.monsterId == option.monsterId
            assert(card.SpriteGUIRendererComponent.ImageRUID.DataId == (selected and '359082ed43c44cc1a597b00b61bafa36' or 'dc14abffdb9f400e819f61b9ab7e6805'), 'only selected card uses the gold base frame')
            local glow = card:GetChildByName('SelectedGlow')
            assert(glow.Enable == selected, 'check mark follows exclusive selection')
            assert(not isvalid(glow:GetChildByName('Border')), 'no frame overlays the card content')
            local frame = card.UITransformComponent.RectSize
            local sign = card:GetChildByName('CardSign').UITransformComponent.RectSize
            assert(sign.x > frame.x and sign.y > frame.y, 'ornament extends beyond the base frame')
        end
        assert(string.find(l:Ui('Editor/Intel/Kind').TextGUIRendererComponent.Text, kinds[option.monsterType], 1, true), 'formal monster kind')
        for statIndex, field in ipairs({'Health','Damage','Interval','Range'}) do
            local value = option[({'maxHp','attackDamage','attackInterval','attackRange'})[statIndex]]
            local stats = l:Ui('Editor/Intel/Stats/'..field..'/Value').TextGUIRendererComponent.Text
            assert(value ~= nil and string.find(stats, tostring(value), 1, true), 'formal combat statistic shown')
            assert(l:Ui('Editor/Intel/Stats/'..field..'/Icon').EnabledInHierarchy, 'stat icon visible')
        end
        assert(l:Ui('Editor/Intel/Name').TextGUIRendererComponent.Text == option.monsterName, 'formal name shown')
    end
    assert(not isvalid(l:Ui('Editor/Intel/Portrait')) and not isvalid(l:Ui('Editor/Intel/Context')),
        'compact intel omits portrait and heading')
    assert(l:Ui('Editor/Intel').UITransformComponent.RectSize.y <= 160, 'compact intel height')
    assert(l:Ui('Editor/Catalog').ScrollLayoutGroupComponent.ConstraintCount == 4, 'four catalog columns')
    local units = _FormationEditSession.Draft
    if #units > 0 then
        local unit = units[1]
        _UserService.LocalPlayer.CurrentMap:GetComponent('FormationMapInput'):HandleWorldClick(Vector3(unit.x, unit.y, 0))
        assert(_FormationEditSession.SelectedUnit == 1, 'world unit selection')
        assert(l:Ui('Editor/Intel/Name').TextGUIRendererComponent.Text == _FormationEditSession:MonsterName(unit.monsterId), 'intel follows selected unit')
    end
    assert(not l:Ui('Editor/Units').Enable, 'technical coordinates start collapsed')
    click('Editor/ToggleUnits')
    assert(l:Ui('Editor/Units').Enable, 'details reachable')
    click('Editor/ToggleUnits')
    assert(l:Ui('Editor/Save').EnabledInHierarchy and l:Ui('Editor/Activate').EnabledInHierarchy, 'save actions visible without details')
    assert(not isvalid(l:Ui('Editor/Remove')) and not isvalid(l:Ui('Editor/AddMode')), 'redundant action buttons removed')
    for _, pair in ipairs({{'Editor/Header','Editor/Title'},{'Editor/Intel','Editor/Save'},{'Editor/CatalogDock','Editor/Catalog'}}) do
        assert(_UILogic:GetSiblingIndex(l:Ui(pair[1]).UITransformComponent)
            < _UILogic:GetSiblingIndex(l:Ui(pair[2]).UITransformComponent), 'background stays behind content')
    end
end)
log(ok and '[VRF][EditorIntel] PASS' or '[VRF][EditorIntel] FAIL ' .. tostring(detail))
