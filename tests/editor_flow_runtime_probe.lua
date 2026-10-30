-- Client, isolated FormationService.StorageKey: actual controls, draft validation, save and return.
local l = _FormationLobby
local function await(predicate)
    for _ = 1, 120 do if predicate() then return true end wait(0.1) end
    return false
end
local function click(path) l:Ui(path):SendEvent(ButtonClickEvent()) end
local function change(action)
    local version, sequence = l.Snapshot.draftVersion, l.ObservedSequence
    action()
    assert(await(function() return l.ObservedSequence > sequence end), 'server replies to draft command')
    return l.Snapshot.draftVersion > version
end
local ok, detail = pcall(function()
    if l:Ui('ExitConfirm').Enable then click('ExitConfirm/Window/ContinueEditing') end
    _FormationService:RequestRetryLoad()
    assert(await(function() return l.Snapshot.loadState == 'NEW' end), 'isolated new-player fixture')
    for slot = 2, 5 do
        _FormationService:RequestSelectSlot(slot)
        assert(await(function() return l.Snapshot.editSlot == slot end), 'select isolated fixture slot')
        if #l.Snapshot.draft > 0 then
            assert(change(function() _FormationService:RequestDraft({}, l.Snapshot.draftVersion, slot) end), 'clear other login draft fixture')
        end
    end
    _FormationService:RequestSelectSlot(1)
    assert(await(function() return l.Snapshot.editSlot == 1 end), 'select first fixture slot')
    if #(l.Snapshot.draft or {}) > 0 then
        assert(change(function() _FormationService:RequestDraft({}, l.Snapshot.draftVersion, l.Snapshot.editSlot) end), 'clear login draft fixture')
    end
    click('Lobby/Edit')
    assert(await(function() return _UserService.LocalPlayer.CurrentMapName == 'formationsim' end), 'real simulation entered')
    wait(.3)
    local input = _UserService.LocalPlayer.CurrentMap:GetComponent('FormationMapInput')
    click('Editor/Catalog/Monster1')
    local chosen = l.SelectedMonsterId
    assert(change(function() input:HandleWorldClick(Vector3(-5,0,0)) end), 'first unit placed')
    assert(change(function() input:HandleWorldClick(Vector3(-3,0,0)) end), 'duplicate unit placed')
    assert(l.Snapshot.draft[1].monsterId == chosen and l.Snapshot.draft[2].monsterId == chosen, 'repeated identity retained')
    input:HandleWorldClick(Vector3(-5,0,0))
    assert(change(function() input:HandleWorldClick(Vector3(-5.25,1.25,0)) end), 'selected unit moved')
    assert(l.Snapshot.draft[1].x == -5.25 and l.Snapshot.draft[1].y == 1.25, 'fractional positions retained')
    input:HandleWorldRemoval(Vector3(-5.25,1.25,0))
    assert(await(function() return #l.Snapshot.draft == 1 end), 'world removal action')
    for index=1,5 do
        click('Editor/Catalog/Monster1')
        assert(change(function() input:HandleWorldClick(Vector3(-2-index,2,0)) end), 'unit added to six')
    end
    click('Editor/Catalog/Monster1')
    assert(not change(function() input:HandleWorldClick(Vector3(-6,0,0)) end), 'seventh unit rejected')
    assert(#l.Snapshot.draft == 6 and string.find(l:Ui('Status').TextGUIRendererComponent.Text,'無法放置',1,true), 'capacity reason visible')
    input:HandleWorldClick(Vector3(-3,0,0))
    assert(not change(function() input:HandleWorldClick(Vector3(5,0,0)) end), 'enemy-side position rejected')
    local illegal = _FormationSchema:CopyUnits(l.Snapshot.draft)
    illegal[1].x, illegal[1].y = illegal[2].x + .2, illegal[2].y
    assert(not change(function() _FormationService:RequestDraft(illegal,l.Snapshot.draftVersion,l.Snapshot.editSlot) end), 'sub-minimum spacing rejected by authority')
    illegal[1].x = illegal[2].x + .3
    assert(change(function() _FormationService:RequestDraft(illegal,l.Snapshot.draftVersion,l.Snapshot.editSlot) end), '0.3 spacing accepted')
    click('Editor/Save')
    assert(await(function() return l.Snapshot.saveState == 'SAVED' and not l.Snapshot.pending end), 'save confirmed')
    assert(#l.Snapshot.saved.slots['1'].units == 6 and l.Snapshot.saved.activeSlot == 0, 'save does not activate')
    click('Editor/Activate')
    assert(await(function() return l.Snapshot.saved.activeSlot == 1 and not l.Snapshot.pending end), 'explicit activation confirmed')
    click('Editor/Back')
    assert(await(function() return _UserService.LocalPlayer.CurrentMapName == 'formationlobby' end), 'clean return works')
    click('Lobby/Edit')
    assert(await(function() return _UserService.LocalPlayer.CurrentMapName == 'formationsim' end), 'editor reentry')
    wait(.3)
    input = _UserService.LocalPlayer.CurrentMap:GetComponent('FormationMapInput')
    input:HandleWorldClick(Vector3(-3.7,2,0))
    assert(l.SelectedUnit > 0, 'saved world unit selectable')
    assert(change(function() input:HandleWorldClick(Vector3(-6,-1,0)) end), 'new unsaved move')
    click('Editor/Back')
    assert(l:Ui('ExitConfirm').EnabledInHierarchy, 'unsaved return confirms')
    click('ExitConfirm/Window/ContinueEditing')
    assert(not l:Ui('ExitConfirm').Enable, 'continue editing')
    click('Editor/Back')
    click('ExitConfirm/Window/ReturnWithoutSave')
    assert(await(function() return _UserService.LocalPlayer.CurrentMapName == 'formationlobby' end), 'return without save')
    assert(l.Snapshot.slots['1'].dirty and #l.Snapshot.saved.slots['1'].units == 6, 'login draft preserved separately')
end)
log(ok and '[VRF][EditorFlow] PASS' or '[VRF][EditorFlow] FAIL ' .. tostring(detail))
