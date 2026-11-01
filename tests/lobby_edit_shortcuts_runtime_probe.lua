-- Client: connected lobby clicks, authoritative selection and real map travel. No storage writes.
local function await(predicate)
    for index = 1, 100 do if predicate() then return true end wait(0.1) end
    return false
end
local l = _FormationLobby
local function click(path) l:Ui(path):SendEvent(ButtonClickEvent()) end
local function slot(index) click('Lobby/Slots/Slot' .. tostring(index)) end
local function back()
    click('Editor/Back')
    wait(0.3)
    if l:Ui('ExitConfirm').EnabledInHierarchy then click('ExitConfirm/Window/ReturnWithoutSave') end
    assert(await(function() return _UserService.LocalPlayer.CurrentMapName == 'formationlobby' and l:Ui('Lobby').EnabledInHierarchy end), 'return to lobby')
    wait(0.2)
end
local ok, detail = pcall(function()
    assert(await(function() return _FormationEditSession.Snapshot.loadState == 'READY' or _FormationEditSession.Snapshot.loadState == 'NEW' end), 'load')
    assert(_UserService.LocalPlayer.CurrentMapName == 'formationlobby', 'lobby fixture')
    local original = _FormationEditSession.Snapshot.editSlot
    local active = _FormationEditSession.Snapshot.saved.activeSlot
    local target = original == 1 and 2 or 1
    slot(target)
    assert(await(function() return _FormationEditSession.Snapshot.editSlot == target end), 'single click selects')
    wait(0.5)
    assert(_UserService.LocalPlayer.CurrentMapName == 'formationlobby', 'single click stays in lobby')
    slot(target)
    wait(0.1)
    slot(target)
    assert(await(function() return _UserService.LocalPlayer.CurrentMapName == 'formationsim' end), 'double click opens preparation')
    assert(_FormationEditSession.Snapshot.editSlot == target, 'double click edits the clicked slot')
    back()
    slot(1)
    wait(0.1)
    slot(2)
    wait(0.5)
    assert(_UserService.LocalPlayer.CurrentMapName == 'formationlobby' and _FormationEditSession.Snapshot.editSlot == 2, 'different rapid clicks only select')
    slot(3)
    wait(0.5)
    slot(3)
    wait(0.5)
    assert(_UserService.LocalPlayer.CurrentMapName == 'formationlobby', 'slow repeated clicks do not open')
    slot(4)
    click('Lobby/Edit')
    assert(await(function() return _UserService.LocalPlayer.CurrentMapName == 'formationsim' end), 'nearby edit button opens preparation')
    assert(_FormationEditSession.Snapshot.editSlot == 4, 'edit button waits for the requested selection')
    back()
    assert(_FormationEditSession.Snapshot.saved.activeSlot == active, 'shortcuts never activate')
    slot(original)
    assert(await(function() return _FormationEditSession.Snapshot.editSlot == original end), 'restore selection')
    wait(0.4)
    log('[VRF][LobbyEditShortcuts] PASS single/double/different/slow clicks; selected-slot edit; no activation')
end)
if not ok then log('[VRF][LobbyEditShortcuts] FAIL ' .. tostring(detail)) end
