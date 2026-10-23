-- Client with saved slots. Server first: ConfigureMakerFaults(0, 1, 2).
local l = _FormationLobby
local function await(predicate)
    for index = 1, 100 do if predicate() then return true end wait(0.1) end
    return false
end
local function click(path) _EntityService:GetEntityByPath('/ui/FormationGroup/' .. path):SendEvent(ButtonClickEvent()) end
local ok, detail = pcall(function()
    click('Editor/Slots/Slot5')
    assert(await(function() return l.Snapshot.editSlot == 5 end), 'select fifth slot')
    local version = l.Snapshot.draftVersion
    click('Editor/Units/Unit1')
    _UserService.LocalPlayer.CurrentMap:GetComponent('FormationMapInput'):HandleWorldClick(Vector3(-5.25, -2.35, 0))
    assert(await(function() return l.Snapshot.draftVersion > version end), 'edit fifth draft')
    local revision = l.Snapshot.saved.revision
    local active = l.Snapshot.saved.activeSlot
    click('Editor/Save')
    assert(await(function() return l.Snapshot.pending end), 'save pending')
    click('Editor/Slots/Slot1')
    assert(await(function() return l.Snapshot.editSlot == 1 end), 'switch away from saving slot')
    assert(await(function() return not l.Snapshot.pending end), 'save failure confirmed')
    assert(l.Snapshot.editSlot == 1 and l.Snapshot.slots['5'].saveState == 'FAILED', 'failure belongs to fifth slot')
    assert(l.Snapshot.saved.revision == revision and l.Snapshot.saved.activeSlot == active, 'failure preserves document')
    click('Retry')
    assert(await(function() return l.Snapshot.loadState == 'READY' end), 'reconcile')
    click('Editor/Slots/Slot5')
    assert(await(function() return l.Snapshot.editSlot == 5 end), 'return to failed draft')
    assert(l.Snapshot.saveState == 'UNSAVED' and math.abs(l.Snapshot.draft[1].y + 2.35) < 0.001, 'draft survives failure and reload')
    assert(math.abs(l.Snapshot.saved.slots['5'].units[1].y - 0.65) < 0.001, 'saved fifth position preserved')
end)
log(ok and '[VRF][FormationSlotsSaveFailure] PASS' or '[VRF][FormationSlotsSaveFailure] FAIL ' .. tostring(detail))
