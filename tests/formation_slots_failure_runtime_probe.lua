-- Client after delayed probe. Server first: ConfigureMakerFaults(0, 1, 2).
local l = _FormationLobby
local function await(predicate)
    for index = 1, 100 do if predicate() then return true end wait(0.1) end
    return false
end
local function click(path) _EntityService:GetEntityByPath('/ui/FormationGroup/' .. path):SendEvent(ButtonClickEvent()) end
local ok, detail = pcall(function()
    local active = l.Snapshot.saved.activeSlot
    assert(active == 2 and l.Snapshot.editSlot == 4, 'delayed probe setup')
    local revision = l.Snapshot.saved.revision
    click('Editor/Activate')
    assert(await(function() return l.Snapshot.pending end), 'activation in flight')
    assert(l.Snapshot.saved.activeSlot == active, 'no optimistic activation')
    click('Editor/Slots/Slot5')
    assert(await(function() return l.Snapshot.editSlot == 5 end), 'switch while activation pending')
    local input = _UserService.LocalPlayer.CurrentMap:GetComponent('FormationMapInput')
    click('Editor/Units/Unit1')
    local version = l.Snapshot.draftVersion
    input:HandleWorldClick(Vector3(-5.25, -2.35, 0))
    assert(await(function() return l.Snapshot.draftVersion > version end), 'retain independent fifth draft')
    assert(await(function() return not l.Snapshot.pending end), 'failure acknowledged')
    assert(l.Snapshot.saved.activeSlot == 2 and l.Snapshot.saved.revision == revision, 'failure preserves previous activation and document')
    assert(l.Snapshot.editSlot == 5 and l.Snapshot.saveState == 'UNSAVED', 'failure cannot switch editor or lose draft')
    assert(l.Snapshot.loadState == 'CONFLICT' and string.find(l.Snapshot.message, '1000004'), 'failure explains cause and retry')
    click('Retry')
    assert(await(function() return l.Snapshot.loadState == 'READY' end), 'reconcile before retry')
    assert(l.Snapshot.editSlot == 5 and math.abs(l.Snapshot.draft[1].y + 2.35) < 0.001, 'read preserves all drafts')
    assert(l.Snapshot.saved.activeSlot == 2, 'read preserves active selection')
    click('Editor/Slots/Slot4')
    assert(await(function() return l.Snapshot.editSlot == 4 end), 'return activation target')
    click('Editor/Activate')
    assert(await(function() return l.Snapshot.saved.activeSlot == 4 and not l.Snapshot.pending end), 'explicit activation retry succeeds')
    click('Editor/Slots/Slot5')
    assert(await(function() return l.Snapshot.editSlot == 5 end), 'fifth draft remains available')
    assert(l.Snapshot.saveState == 'UNSAVED' and l.Snapshot.saved.activeSlot == 4, 'activation does not save another draft')
end)
log(ok and '[VRF][FormationSlotsFailure] PASS' or '[VRF][FormationSlotsFailure] FAIL ' .. tostring(detail))
