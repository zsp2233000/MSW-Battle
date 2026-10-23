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
    local input = _UserService.LocalPlayer.CurrentMap:GetComponent('FormationMapInput')
    check(isvalid(input), 'world input component attached')
    -- Clear the draft through the formal draft command; confirmed content remains separate.
    local version = lobby.Snapshot.draftVersion
    _FormationService:RequestDraft({}, version, 1)
    untilState(function() return lobby.Snapshot.draftVersion > version end)
    click('Editor/Catalog/Monster1')
    version = lobby.Snapshot.draftVersion
    input:HandleWorldClick(Vector3(-4.35, 0.65, 0))
    check(untilState(function() return lobby.Snapshot.draftVersion > version end), 'world click places first unit outside former UI grid')
    version = lobby.Snapshot.draftVersion
    input:HandleWorldClick(Vector3(-3.45, 0.65, 0))
    check(untilState(function() return lobby.Snapshot.draftVersion > version end), 'duplicate monster allowed')
    input:HandleWorldClick(Vector3(-4.35, 0.65, 0))
    version = lobby.Snapshot.draftVersion
    input:HandleWorldClick(Vector3(-5.25, -0.35, 0))
    check(untilState(function() return lobby.Snapshot.draftVersion > version end), 'world selection moves a unit')
    check(math.abs(lobby.Snapshot.draft[1].x + 5.25) < 0.001 and math.abs(lobby.Snapshot.draft[1].y + 0.35) < 0.001, 'fractional world coordinates retained')
    check(untilState(function() return input.PreviewCount == 2 end), 'two private world previews')
    local preview = _EntityService:GetEntityByPath('/maps/formationsim/FormationPreview_1')
    check(isvalid(preview) and math.abs(preview.TransformComponent.Position.x + 5.25) < 0.001, 'preview follows exact position')
    check(preview.SpriteRendererComponent.SpriteRUID == lobby.Snapshot.options[1][3], 'formal idle animation rendered')
    check(preview:GetComponent('BattleUnit') == nil, 'preview has no combat state')
    click('Editor/Save')
    check(untilState(function() return lobby.Snapshot.saveState == 'SAVED' end), 'persistent success acknowledged')
    check(#lobby.Snapshot.saved.slots['1'].units == 2, 'confirmed formation contains two units')
    check(lobby.Snapshot.saved.activeSlot == initialActive, 'saving does not activate')
    for index = 1, 5 do check(lobby.Snapshot.saved.slots[tostring(index)].id == index, 'stable slot ' .. index) end
    click('Editor/Activate')
    check(untilState(function() return lobby.Snapshot.saved.activeSlot == 1 and not lobby.Snapshot.pending end), 'activation independently persisted')
    click('Editor/AddMode')
    version = lobby.Snapshot.draftVersion
    input:HandleWorldClick(Vector3(-2.25, -1.35, 0))
    check(untilState(function() return lobby.Snapshot.draftVersion > version end), 'new draft after save')
    check(lobby.Snapshot.saveState == 'UNSAVED' and #lobby.Snapshot.saved.slots['1'].units == 2, 'draft cannot change confirmed formation')
    click('Editor/Back')
    check(untilState(function() return _UserService.LocalPlayer.CurrentMapName == 'formationlobby' end), 'returns to lobby')
    check(not isvalid(preview), 'private previews removed on departure')
    click('Lobby/Edit')
    check(untilState(function() return _UserService.LocalPlayer.CurrentMapName == 'formationsim' end), 'returns to simulation')
    input = _UserService.LocalPlayer.CurrentMap:GetComponent('FormationMapInput')
    check(untilState(function() return input.PreviewCount == 3 end), 'previews restored on reentry')
    version = lobby.Snapshot.draftVersion
    input:HandleWorldRemoval(Vector3(-2.25, -1.35, 0))
    check(untilState(function() return lobby.Snapshot.draftVersion > version end), 'world removal updates draft')
    check(#lobby.Snapshot.draft == 2, 'world removal removes exactly one')
    version = lobby.Snapshot.draftVersion
    input:HandleWorldClick(Vector3(-2.25, -1.35, 0))
    check(untilState(function() return lobby.Snapshot.draftVersion > version end), 'world replacement remains unsaved')
    check(#lobby.Snapshot.draft == 3 and #lobby.Snapshot.saved.slots['1'].units == 2, 'same-login transition retains unsaved draft')
end)
if not ok then failures = failures + 1 log('[VRF][FormationFlow] exception=' .. tostring(detail)) end
log(failures == 0 and '[VRF][FormationFlow] PASS' or '[VRF][FormationFlow] FAILURES=' .. failures)
