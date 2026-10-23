-- Client after slots probe. Server first: ConfigureMakerFaults(0, 0, 2).
local l = _FormationLobby
local function await(predicate)
    for index = 1, 100 do if predicate() then return true end wait(0.1) end
    return false
end
local function click(path) _EntityService:GetEntityByPath('/ui/FormationGroup/' .. path):SendEvent(ButtonClickEvent()) end
local function selectSlot(slot)
    click('Editor/Slots/Slot' .. tostring(slot))
    assert(await(function() return l.Snapshot.editSlot == slot end), 'select slot')
end
local ok, detail = pcall(function()
    click('Lobby/Edit')
    assert(await(function() return _UserService.LocalPlayer.CurrentMapName == 'formationsim' end), 'enter editor')
    local input = _UserService.LocalPlayer.CurrentMap:GetComponent('FormationMapInput')
    selectSlot(2)
    assert(l.Snapshot.saveState == 'UNSAVED', 'second slot has unsaved draft from flow')
    local savingVersion = l.Snapshot.draftVersion
    local revision = l.Snapshot.saved.revision
    click('Editor/Save')
    assert(await(function() return l.Snapshot.pending end), 'save pending')
    assert(l.Snapshot.pendingSlot == 2 and l.Snapshot.pendingKind == 'SAVE', 'pending target observable')
    selectSlot(3)
    click('Editor/Units/Unit1')
    local version = l.Snapshot.draftVersion
    input:HandleWorldClick(Vector3(-5.25, -1.35, 0))
    assert(await(function() return l.Snapshot.draftVersion > version end), 'other draft editable during save')
    version = l.Snapshot.draftVersion
    _FormationService:RequestSave(version, 3)
    assert(await(function() return not l.Snapshot.pending end), 'delayed save confirmed')
    assert(l.Snapshot.editSlot == 3 and l.Snapshot.saveState == 'UNSAVED', 'completion cannot switch or mark other draft saved')
    assert(l.Snapshot.draftVersion == version and math.abs(l.Snapshot.draft[1].y + 1.35) < 0.001, 'other draft unchanged')
    assert(l.Snapshot.saved.revision == revision + 1 and l.Snapshot.saved.activeSlot == 1, 'only requested write completed')
    assert(math.abs(l.Snapshot.saved.slots['2'].units[1].y + 0.35) < 0.001, 'captured second slot saved')
    selectSlot(2)
    assert(l.Snapshot.savedDraftVersion == savingVersion and l.Snapshot.saveState == 'SAVED', 'original slot version confirmed')
    local previous = l.Snapshot.saved.activeSlot
    click('Editor/Activate')
    assert(await(function() return l.Snapshot.pending end), 'activation pending')
    assert(l.Snapshot.saved.activeSlot == previous, 'activation waits for durable acknowledgement')
    selectSlot(3)
    assert(await(function() return not l.Snapshot.pending end), 'activation confirmed')
    assert(l.Snapshot.saved.activeSlot == 2 and l.Snapshot.editSlot == 3, 'captured activation does not switch editor')
    assert(l.Snapshot.saveState == 'UNSAVED', 'activation never saves current draft')
    -- A second group's independent write cannot overwrite the previously saved group.
    revision = l.Snapshot.saved.slots['2'].revision
    click('Editor/Save')
    assert(await(function() return l.Snapshot.pending end), 'third slot save pending')
    selectSlot(4)
    assert(await(function() return not l.Snapshot.pending end), 'third slot save confirmed')
    assert(l.Snapshot.editSlot == 4 and l.Snapshot.saved.activeSlot == 2, 'consecutive writes preserve both selections')
    assert(l.Snapshot.saved.slots['2'].revision == revision, 'third save preserves second saved version')
    assert(math.abs(l.Snapshot.saved.slots['3'].units[1].y + 1.35) < 0.001, 'third saved position confirmed')
end)
log(ok and '[VRF][FormationSlotsDelay] PASS' or '[VRF][FormationSlotsDelay] FAIL ' .. tostring(detail))
