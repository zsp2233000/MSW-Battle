-- Enter the editor first, then server ConfigureMakerFaults(1, 1, 1), then this client probe.
local l = _FormationLobby
local function await(predicate)
    for _ = 1, 100 do if predicate() then return true end wait(.1) end
    return false
end
local function click(path) l:Ui(path):SendEvent(ButtonClickEvent()) end
local originalSlot = l.Snapshot.editSlot
local backup
local ok, detail = pcall(function()
    assert(_UserService.LocalPlayer.CurrentMapName == 'formationsim', 'start in editor before injecting faults')
    _FormationService:RequestSelectSlot(5)
    assert(await(function() return l.Snapshot.editSlot == 5 end), 'fixture slot selected')
    backup = _FormationSchema:CopyUnits(l.Snapshot.draft)
    local saved = _FormationSchema:EncodeDocument(l.Snapshot.saved)
    local units = {{monsterId=l.Snapshot.options[1][1],x=-6,y=-1}}
    _FormationService:RequestDraft(units,l.Snapshot.draftVersion,5)
    assert(await(function() return _FormationSchema:SameUnits(l.Snapshot.draft,units) end), 'valid draft prepared')
    _FormationService:RequestRetryLoad()
    assert(await(function() return l.Snapshot.loadState == 'ERROR' end), 'injected read failure')
    assert(l:Ui('Retry').EnabledInHierarchy and l:Ui('Retry').ButtonComponent.Enable, 'editor retry reachable')
    local retryPosition = l:Ui('Retry').UITransformComponent.anchoredPosition
    assert(retryPosition.x >= 0 and retryPosition.y <= 0, 'retry remains inside top-left screen bounds')
    assert(not l:Ui('Editor/Save').ButtonComponent.Enable and not l:Ui('Editor/Activate').ButtonComponent.Enable
        and not l:Ui('Editor/Catalog/Monster1').ButtonComponent.Enable, 'unconfirmed actions disabled')
    assert(_FormationSchema:EncodeDocument(l.Snapshot.saved) == saved
        and _FormationSchema:SameUnits(l.Snapshot.draft,units), 'read failure retains data')
    click('Retry')
    assert(await(function() return l.Snapshot.loadState == 'READY' end), 'connected retry recovers')
    click('Editor/Save')
    assert(await(function() return l.Snapshot.pending end), 'write pending')
    assert(not l:Ui('Editor/Save').ButtonComponent.Enable and not l:Ui('Editor/Activate').ButtonComponent.Enable
        and not l:Ui('Editor/Slots/Slot2').ButtonComponent.Enable
        and not _MatchProbeInput.action.ButtonComponent.Enable, 'pending operations disabled')
    click('Editor/Back')
    assert(_UserService.LocalPlayer.CurrentMapName == 'formationsim', 'pending save prevents exit')
    assert(await(function() return l.Snapshot.saveState == 'FAILED' and not l.Snapshot.pending end), 'injected save failure')
    assert(_FormationSchema:EncodeDocument(l.Snapshot.saved) == saved
        and _FormationSchema:SameUnits(l.Snapshot.draft,units), 'failed write retains confirmed data and draft')
    assert(l:Ui('Retry').EnabledInHierarchy, 'failed write offers reconciliation')
    click('Retry')
    assert(await(function() return l.Snapshot.loadState == 'READY' end), 'reconcile after failed write')
    assert(l:Ui('Editor/Save').ButtonComponent.Enable, 'retry save available after reconciliation')
    log('[VRF][EditorFailure] PASS read retry; pending controls; failed save retains data')
end)
if backup ~= nil then
    _FormationService:RequestDraft(backup,l.Snapshot.draftVersion,5)
    assert(await(function() return _FormationSchema:SameUnits(l.Snapshot.draft,backup) end), 'fixture draft restored')
    _FormationService:RequestSelectSlot(originalSlot)
    assert(await(function() return l.Snapshot.editSlot == originalSlot end), 'original slot restored')
end
if not ok then log('[VRF][EditorFailure] FAIL '..tostring(detail)) end
