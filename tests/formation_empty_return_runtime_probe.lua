-- Client: exercise clearing a saved formation and the connected return-dialog buttons without writing storage.
local ui = _FormationLobby
for attempt = 1, 50 do
    if isvalid(_UserService.LocalPlayer) and ui.Snapshot.saved ~= nil and ui.Snapshot.loadState ~= 'LOADING' then break end
    wait(0.1)
end
local player = _UserService.LocalPlayer
local originalMap = player.CurrentMapName
local original = ui.Snapshot
local slotId = original.editSlot
local originalDraft = _FormationSchema:CopyUnits(original.draft or {})
local saved = original.saved
local function click(path)
    local entity = _EntityService:GetEntityByPath('/ui/FormationGroup/' .. path)
    assert(isvalid(entity) and entity.ButtonComponent.Enable, 'enabled button ' .. path)
    entity:SendEvent(ButtonClickEvent())
end
local function await(test, label)
    for attempt = 1, 50 do if test() then return end wait(0.1) end
    assert(test(), label)
end
local ok, detail = pcall(function()
    assert(saved ~= nil and #saved.slots[tostring(slotId)].units > 0, 'requires an existing saved formation')
    assert(not original.pending, 'requires idle storage')
    for index = 1, 5 do
        if index ~= slotId then
            local info = original.slots[tostring(index)]
            assert(info ~= nil and not info.dirty, 'other drafts must be saved before testing')
        end
    end
    ui:Travel('formationsim')
    await(function() return player.CurrentMapName == 'formationsim' end, 'simulation entered')
    local version = ui.Snapshot.draftVersion
    _FormationService:RequestDraft({}, version, slotId)
    await(function() return ui.Snapshot.draftVersion > version and #ui.Snapshot.draft == 0 end, 'draft cleared')
    click('Editor/Back')
    local dialog = _EntityService:GetEntityByPath('/ui/FormationGroup/ExitConfirm')
    assert(dialog.Enable, 'unsaved clearing opens the return confirmation')
    local save = _EntityService:GetEntityByPath('/ui/FormationGroup/ExitConfirm/Window/SaveAndReturn')
    if save.ButtonComponent.Enable then save:SendEvent(ButtonClickEvent()) end
    wait(0.2)
    local message = _EntityService:GetEntityByPath('/ui/FormationGroup/ExitConfirm/Window/Message').TextGUIRendererComponent.Text
    assert(not save.ButtonComponent.Enable and string.find(message, '空編隊', 1, true) ~= nil,
        'empty formation needs a visible explanation and a disabled save-and-return button')
    local messageEntity = _EntityService:GetEntityByPath('/ui/FormationGroup/ExitConfirm/Window/Message')
    assert(messageEntity.TextGUIRendererComponent:GetPreferredHeight(message, messageEntity.UITransformComponent.RectSize.x)
        <= messageEntity.UITransformComponent.RectSize.y, 'the explanation fits the confirmation window')
    assert(not ui.Snapshot.pending, 'no invalid save is pending')
    click('ExitConfirm/Window/ContinueEditing')
    assert(not dialog.Enable, 'continue editing closes the confirmation')
    local otherSlot = slotId == 1 and 2 or 1
    _FormationService:RequestSelectSlot(otherSlot)
    await(function() return ui.Snapshot.editSlot == otherSlot end, 'clean alternative slot selected')
    click('Editor/Back')
    assert(save.ButtonComponent.Enable, 'a clean selected slot does not block saving another dirty slot')
    click('ExitConfirm/Window/SaveAndReturn')
    await(function() return ui.Snapshot.editSlot == slotId end, 'batch return selects the dirty slot')
    message = _EntityService:GetEntityByPath('/ui/FormationGroup/ExitConfirm/Window/Message').TextGUIRendererComponent.Text
    assert(dialog.Enable and not save.ButtonComponent.Enable and string.find(message, '空編隊', 1, true) ~= nil,
        'a batch that reaches an empty draft retains its actionable confirmation')
    click('ExitConfirm/Window/ContinueEditing')
    click('Editor/Back')
    click('ExitConfirm/Window/ReturnWithoutSave')
    await(function() return player.CurrentMapName == 'formationlobby' end, 'return without saving remains available')
    assert(#ui.Snapshot.draft == 0, 'cleared draft survives returning to the lobby')
    assert(ui.Snapshot.saved.revision == saved.revision and ui.Snapshot.saved.activeSlot == saved.activeSlot,
        'saved data and active selection remain unchanged')
end)
ui:ContinueEditing()
if ui.Snapshot.editSlot == slotId and not ui.Snapshot.pending then
    local version = ui.Snapshot.draftVersion
    _FormationService:RequestDraft(originalDraft, version, slotId)
    await(function() return ui.Snapshot.draftVersion > version or _FormationSchema:SameUnits(ui.Snapshot.draft, originalDraft) end, 'original draft restored')
end
if player.CurrentMapName ~= originalMap then ui:Travel(originalMap) end
log(ok and '[VRF][EmptyReturn] PASS' or '[VRF][EmptyReturn] FAIL ' .. tostring(detail))
