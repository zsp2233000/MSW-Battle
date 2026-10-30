-- Client from formationlobby: authoring values survive renders and map changes; no storage writes.
local l, m = _FormationLobby, _MatchProbeInput
local function await(predicate)
    for _ = 1, 100 do if predicate() then return true end wait(.1) end
    return false
end
local function click(path) l:Ui(path):SendEvent(ButtonClickEvent()) end
local changed = {}
local nameTemplate = l:Ui('Editor/Catalog/Template/MonsterName')
local originalFont = nameTemplate.TextGUIRendererComponent.FontSize
local originalState, originalSummary, originalMessage = m.State, m.FixedSummary, m.Message
local function keepAuthored(entity)
    local transform = entity.UITransformComponent
    local entry = {entity=entity, pos=transform.anchoredPosition, size=transform.RectSize}
    entry.customPos = Vector2(entry.pos.x + 1, entry.pos.y - 1)
    entry.customSize = Vector2(entry.size.x + 2, entry.size.y + 2)
    transform.anchoredPosition, transform.RectSize = entry.customPos, entry.customSize
    table.insert(changed, entry)
end
local function assertAuthored()
    for _, entry in ipairs(changed) do
        local transform = entry.entity.UITransformComponent
        assert(transform.anchoredPosition == entry.customPos and transform.RectSize == entry.customSize,
            entry.entity.Name .. ' authoring geometry was overwritten')
    end
end
local ok, detail = pcall(function()
    assert(await(function() return #(l.Snapshot.options or {}) > 0 and m._T.panel ~= nil
        and not m._T.pending and not m.Busy end), 'catalog and screen ready')
    assert(_UserService.LocalPlayer.CurrentMapName == 'formationlobby', 'start in lobby')
    assert(l:Ui('Lobby').EnabledInHierarchy and not l:Ui('Editor').Enable
        and not l:Ui('EditorControls').Enable and not l:Ui('Editor/Catalog/Template').Enable, 'authoring preview hidden in play')
    assert(#l._T.cards == #l.Snapshot.options, 'template is excluded from runtime cards')
    for _, path in ipairs({'Status','Retry','ReturnLobby','EditorControls/Status','EditorControls/Retry','EditorControls/Toggle'}) do
        keepAuthored(l:Ui(path))
    end
    for _, screen in ipairs({'Match','EditorMatch','BattleMatch'}) do
        local panel = m.root:GetChildByName(screen)
        keepAuthored(panel)
        for _, child in ipairs({'Action','Status','FixedSummary'}) do keepAuthored(panel:GetChildByName(child)) end
    end
    nameTemplate.TextGUIRendererComponent.FontSize = originalFont + 3
    l._T.optionsKey = ''
    l:BuildOptions(l.Snapshot.options)
    click('Lobby/Edit')
    assert(await(function() return _UserService.LocalPlayer.CurrentMapName == 'formationsim'
        and m._T.panel.Name == 'EditorMatch' and not m._T.pending end), 'editor layout selected on map transition')
    wait(.3)
    for _, card in ipairs(l._T.cards) do
        assert(card.entity:GetChildByName('MonsterName').TextGUIRendererComponent.FontSize == originalFont + 3,
            'generated card inherits authored template font')
    end
    assert(not l:Ui('Status').Enable and l:Ui('EditorControls/Status').EnabledInHierarchy, 'editor status owns its layout')
    click('EditorControls/Toggle')
    assert(not l:Ui('Editor').Enable and l:Ui('EditorControls/Toggle').EnabledInHierarchy, 'collapsed panel can be expanded')
    click('EditorControls/Toggle')
    assert(l:Ui('Editor').EnabledInHierarchy and not l:Ui('Editor/Catalog/Template').Enable, 'expand shows generated cards only')
    for _, route in ipairs({{'matchprobe','BattleMatch'},{'formationlobby','Match'},{'formationsim','EditorMatch'}}) do
        m:SelectScreen(route[1])
        m.State, m.FixedSummary, m.Message = 'RESULT_WIN', 'authoring probe', ''
        m:Render()
        assert(m._T.panel.Name == route[2] and m.action == m._T.panel:GetChildByName('Action'), 'action belongs to selected screen')
        assert(m.action.TextGUIRendererComponent.Text == '返回大廳', 'selected action receives state')
        assert(string.find(m._T.panel:GetChildByName('FixedSummary').TextGUIRendererComponent.Text, 'authoring probe', 1, true),
            'selected summary receives data')
        for _, name in ipairs({'Match','EditorMatch','BattleMatch'}) do
            assert(m.root:GetChildByName(name).Enable == (name == route[2]), 'exactly one screen enabled')
        end
    end
    m.State, m.FixedSummary, m.Message = originalState, originalSummary, originalMessage
    l:Render()
    m:Render()
    assertAuthored()
    click('Editor/Back')
    if l:Ui('ExitConfirm').Enable then click('ExitConfirm/Window/ReturnWithoutSave') end
    assert(await(function() return _UserService.LocalPlayer.CurrentMapName == 'formationlobby'
        and m._T.panel.Name == 'Match' end), 'lobby layout restored on return')
    l:Render()
    assertAuthored()
end)
for _, entry in ipairs(changed) do
    entry.entity.UITransformComponent.anchoredPosition = entry.pos
    entry.entity.UITransformComponent.RectSize = entry.size
end
nameTemplate.TextGUIRendererComponent.FontSize = originalFont
l._T.optionsKey = ''
l:BuildOptions(l.Snapshot.options)
m.State, m.FixedSummary, m.Message = originalState, originalSummary, originalMessage
m:SelectScreen(_UserService.LocalPlayer.CurrentMapName)
l:Render()
m:Render()
log(ok and '[VRF][EditorAuthoring] PASS preview hidden; authored layout and card fonts retained; screen routing' or '[VRF][EditorAuthoring] FAIL '..tostring(detail))
