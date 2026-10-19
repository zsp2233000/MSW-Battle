-- Client context. Uses connected UI events and public read-only observations.
local failures = 0
local function check(value, message)
    if not value then failures = failures + 1 log('[VRF][FormationFlow] FAIL ' .. message) end
end
local function untilState(predicate)
    for index = 1, 100 do if predicate() then return true end wait(0.1) end
    return false
end
local function ui(path) return _EntityService:GetEntityByPath('/ui/FormationGroup/' .. path) end
local function click(path) ui(path):SendEvent(ButtonClickEvent()) end
local lobby = _FormationLobby
local ok, detail = pcall(function()
    check(untilState(function() return lobby.Snapshot.loadState == 'NEW' or lobby.Snapshot.loadState == 'READY' end), 'load completes')
    check(#lobby.Snapshot.options == 3, 'formal MonsterCatalog options')
    local initialActive = lobby.Snapshot.saved.activeSlot
    click('Lobby/Edit')
    check(untilState(function() return _UserService.LocalPlayer.CurrentMapName == 'formationsim' end), 'simulation map entered')
    -- Clear the draft through the formal draft command; confirmed content remains separate.
    local version = lobby.Snapshot.draftVersion
    _FormationService:RequestDraft({}, version)
    untilState(function() return lobby.Snapshot.draftVersion > version end)
    click('Editor/Catalog/Monster1')
    version = lobby.Snapshot.draftVersion
    click('Editor/Board/Cell1_1')
    check(untilState(function() return lobby.Snapshot.draftVersion > version end), 'connected board places first unit')
    version = lobby.Snapshot.draftVersion
    click('Editor/Board/Cell3_1')
    check(untilState(function() return lobby.Snapshot.draftVersion > version end), 'duplicate monster allowed')
    click('Editor/Units/Unit1')
    version = lobby.Snapshot.draftVersion
    click('Editor/Board/Cell2_3')
    check(untilState(function() return lobby.Snapshot.draftVersion > version end), 'connected unit row moves a unit')
    check(lobby.Snapshot.draft[1].x == -2 and lobby.Snapshot.draft[1].y == 0, 'relative coordinates observed')
    click('Editor/Save')
    check(untilState(function() return lobby.Snapshot.saveState == 'SAVED' end), 'persistent success acknowledged')
    check(#lobby.Snapshot.saved.slots['1'].units == 2, 'confirmed formation contains two units')
    check(lobby.Snapshot.saved.activeSlot == initialActive, 'saving does not activate')
    for index = 1, 5 do check(lobby.Snapshot.saved.slots[tostring(index)].id == index, 'stable slot ' .. index) end
    click('Editor/Activate')
    check(untilState(function() return lobby.Snapshot.saved.activeSlot == 1 and not lobby.Snapshot.pending end), 'activation independently persisted')
    click('Editor/AddMode')
    version = lobby.Snapshot.draftVersion
    click('Editor/Board/Cell5_5')
    check(untilState(function() return lobby.Snapshot.draftVersion > version end), 'new draft after save')
    check(lobby.Snapshot.saveState == 'UNSAVED' and #lobby.Snapshot.saved.slots['1'].units == 2, 'draft cannot change confirmed formation')
    click('Editor/Back')
    check(untilState(function() return _UserService.LocalPlayer.CurrentMapName == 'formationlobby' end), 'returns to lobby')
    click('Lobby/Edit')
    check(untilState(function() return _UserService.LocalPlayer.CurrentMapName == 'formationsim' end), 'returns to simulation')
    check(#lobby.Snapshot.draft == 3 and #lobby.Snapshot.saved.slots['1'].units == 2, 'same-login transition retains unsaved draft')
end)
if not ok then failures = failures + 1 log('[VRF][FormationFlow] exception=' .. tostring(detail)) end
log(failures == 0 and '[VRF][FormationFlow] PASS' or '[VRF][FormationFlow] FAILURES=' .. failures)
