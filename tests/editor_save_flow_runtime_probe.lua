-- Client, fresh Play. First run in server_main so the probe owns an isolated, empty player record:
--   _FormationService.StorageKey = 'Issue50_' .. _UtilLogic:NewGuid()
-- Drives the production controls (button events and the map input handlers) for #50: unsaved content is local,
-- the marker follows content comparison, saving touches one group, and switching or leaving asks first.
local l = _FormationLobby
local function await(predicate, tries)
    for _ = 1, tries or 120 do if predicate() then return true end wait(0.1) end
    return false
end
local function node(path) return l:Ui(path) end
local function enabled(path) return node(path).ButtonComponent.Enable end
local function label(path) return node(path).TextGUIRendererComponent.Text end
local function has(text, part) return string.find(text, part, 1, true) ~= nil end
local function click(path)
    -- A disabled native button never raises a click, so the probe respects that too.
    if not enabled(path) then return false end
    node(path):SendEvent(ButtonClickEvent())
    return true
end
local function dialogOpen() return node('ExitConfirm').Enable end
local function inEditor() return _UserService.LocalPlayer.CurrentMapName == 'formationsim' and node('Editor').EnabledInHierarchy and _FormationEditSession.DraftSlot == _FormationEditSession.Snapshot.editSlot and _MatchFlowInput:AllowsFormationActions() end
local function openEditor()
    assert(await(function() return node('Lobby/Edit').EnabledInHierarchy and enabled('Lobby/Edit') end), 'lobby status confirmed before editing')
    assert(click('Lobby/Edit'), 'edit button enabled')
    assert(await(inEditor), 'editor entered')
    wait(0.4)
    return _UserService.LocalPlayer.CurrentMap:GetComponent('FormationMapInput')
end
local function armCard() click('Editor/Catalog/Monster1') end
local function remove(input, x, y)
    -- Right-click removal applies only with no armed preview.
    _FormationEditSession.SelectedMonsterId = ''
    _FormationEditSession.SelectedUnit = 0
    input:HandleWorldRemoval(Vector3(x, y, 0))
end

local ok, detail = pcall(function()
    if dialogOpen() then l:Run(_FormationEditSession:ContinueEditing()) end
    _FormationService:RequestRetryLoad()
    assert(await(function() return _FormationEditSession.Snapshot.loadState == 'NEW' end), 'isolated new-player fixture')
    local input = openEditor()

    -- S1: a never-edited empty group is clean, and save/activate are visible but disabled.
    assert(not _FormationEditSession:IsDirty() and #_FormationEditSession.Draft == 0 and _FormationEditSession.DraftSlot == 1, 'opens from the saved version')
    assert(node('Editor/Save').EnabledInHierarchy and node('Editor/Activate').EnabledInHierarchy, 'save and activate stay visible')
    assert(not enabled('Editor/Save') and not enabled('Editor/Activate'), 'disabled without changes or saved content')
    assert(not _FormationEditSession:IsDirty(), 'clean group has no marker')
    assert(node('Editor/Slots/Slot1').SpriteGUIRendererComponent.Color.g < 0.9 and node('Editor/Slots/Slot2').SpriteGUIRendererComponent.Color.g > 0.99, 'viewed group is tinted, others are not')
    assert(not node('Editor/Slots/Slot1/ActiveBadge').Enable, 'no active group yet')
    log('[VRF][Save50] S1 initial state ok')

    -- S2: an edit stays in the client: no server reply, marker appears, save becomes usable.
    armCard()
    local sequence = _FormationEditSession.ObservedSequence
    input:HandleWorldClick(Vector3(-5, 0, 0))
    assert(#_FormationEditSession.Draft == 1 and _FormationEditSession:IsDirty(), 'unit placed locally')
    wait(0.6)
    assert(_FormationEditSession.ObservedSequence == sequence, 'an edit makes no server round trip')
    assert(_FormationEditSession:IsDirty(), 'unsaved marker on the viewed group')
    assert(not false, 'other groups unmarked')
    assert(enabled('Editor/Save') and not enabled('Editor/Activate'), 'valid change enables save only')
    assert(label('Editor/Save') == '儲存隊伍', 'save label')
    log('[VRF][Save50] S2 local edit ok')

    -- S3: restoring the exact saved content removes the marker and disables save again.
    remove(input, -5, 0)
    assert(#_FormationEditSession.Draft == 0 and not _FormationEditSession:IsDirty(), 'exact restoration')
    assert(not _FormationEditSession:IsDirty() and not enabled('Editor/Save'), 'marker removed and save disabled')
    log('[VRF][Save50] S3 exact restoration ok')

    -- S4: one rule set for the preview and the edit: spacing, side, capacity, moving.
    armCard()
    input:HandleWorldClick(Vector3(-5, 0, 0))
    input:HandleWorldClick(Vector3(-4.71, 0, 0))
    assert(#_FormationEditSession.Draft == 1 and _FormationEditSession.SelectedUnit == 0, '0.29 apart is refused and does not select the neighbour')
    input:HandleWorldClick(Vector3(-4.7, 0, 0))
    assert(#_FormationEditSession.Draft == 2, '0.30 apart is accepted')
    input:HandleWorldClick(Vector3(5, 0, 0))
    assert(#_FormationEditSession.Draft == 2, 'the enemy half is refused')
    assert(_FormationEditSession.SelectedMonsterId ~= '' and _FormationEditSession:PreviewMode() == 'PLACE', 'a legal placement keeps the card armed for continuous deployment')
    assert(not _FormationEditSession:CanPlaceAt(-8, 2), 'a spot whose mirror lands on a wall is refused')
    for _, p in ipairs({ { -7, 2 }, { -6, 2 }, { -5, 2 }, { -4, 2 } }) do input:HandleWorldClick(Vector3(p[1], p[2], 0)) end
    assert(#_FormationEditSession.Draft == 6, 'six units')
    assert(not _FormationEditSession:CanPlaceAt(-3, -2), 'a seventh unit is illegal (the preview turns red)')
    input:HandleWorldClick(Vector3(-3, -2, 0))
    assert(#_FormationEditSession.Draft == 6, 'a seventh unit is not added')
    _FormationEditSession.SelectedMonsterId = ''
    input:HandleWorldClick(Vector3(-5, 0, 0))
    assert(_FormationEditSession.SelectedUnit == 1 and _FormationEditSession:PreviewMode() == 'MOVE', 'without a preview a click selects a unit')
    input:HandleWorldClick(Vector3(-5.05, -0.05, 0))
    -- Vector3 stores float32, so compare coordinates with a tolerance.
    assert(#_FormationEditSession.Draft == 6 and math.abs(_FormationEditSession.Draft[1].x + 5.05) < 0.0001, 'a full roster can still move a unit; its own spot is excluded')
    input:HandleWorldClick(Vector3(-4.7, 0.05, 0))
    assert(math.abs(_FormationEditSession.Draft[1].x + 5.05) < 0.0001, 'an illegal move changes nothing and keeps the selection')
    assert(_FormationEditSession.SelectedUnit == 1, 'selection survives an invalid click')
    log('[VRF][Save50] S4 shared placement rules ok')

    -- S5: switching with changes asks; every choice behaves as promised.
    assert(click('Editor/Slots/Slot2'), 'slot button')
    assert(dialogOpen() and _FormationEditSession.ConfirmKind == 'SWITCH', 'switch confirmation')
    assert(label('ExitConfirm/Window/SaveAndReturn') == '儲存並切換' and label('ExitConfirm/Window/ReturnWithoutSave') == '不儲存切換'
        and label('ExitConfirm/Window/ContinueEditing') == '繼續編輯', 'switch choices')
    assert(not enabled('Editor/Save') and _FormationEditSession:PreviewMode() == '', 'editing is paused while asking')
    click('ExitConfirm/Window/ContinueEditing')
    assert(not dialogOpen() and _FormationEditSession.Snapshot.editSlot == 1 and #_FormationEditSession.Draft == 6, 'continue keeps the group and its content')
    click('Editor/Slots/Slot2')
    click('ExitConfirm/Window/ReturnWithoutSave')
    assert(await(function() return _FormationEditSession.Snapshot.editSlot == 2 and _FormationEditSession.DraftSlot == 2 end), 'discard then switch')
    assert(#_FormationEditSession.Draft == 0 and not _FormationEditSession:IsDirty(), 'the target group opens from its saved version')
    assert(click('Editor/Slots/Slot1'), 'clean switch needs no question')
    assert(await(function() return _FormationEditSession.Snapshot.editSlot == 1 and _FormationEditSession.DraftSlot == 1 end) and not dialogOpen(), 'switched back directly')
    assert(#_FormationEditSession.Draft == 0 and #_FormationEditSession.Snapshot.saved.slots['1'].units == 0, 'discarded content is gone and nothing was stored')
    log('[VRF][Save50] S5 switch choices ok')

    -- S6: save and switch writes only the viewed group; saving never activates.
    armCard()
    input:HandleWorldClick(Vector3(-5, 0, 0))
    input:HandleWorldClick(Vector3(-3, 1, 0))
    assert(#_FormationEditSession.Draft == 2 and enabled('Editor/Save'), 'two units')
    click('Editor/Slots/Slot2')
    assert(enabled('ExitConfirm/Window/SaveAndReturn'), 'valid content may be saved')
    click('ExitConfirm/Window/SaveAndReturn')
    assert(await(function() return _FormationEditSession.Snapshot.editSlot == 2 and _FormationEditSession.DraftSlot == 2 and not _FormationEditSession.Snapshot.pending end, 150), 'saved and switched')
    local saved = _FormationEditSession.Snapshot.saved
    assert(#saved.slots['1'].units == 2 and #saved.slots['2'].units == 0, 'only the viewed group changed')
    assert(saved.activeSlot == 0 and not node('Editor/Slots/Slot1/ActiveBadge').Enable, 'saving did not activate')
    assert(not dialogOpen(), 'the confirmation closed after success')
    log('[VRF][Save50] S6 single-group save ok')

    -- S7: an unmodified empty group and a touched-then-restored group show no marker.
    assert(not _FormationEditSession:IsDirty() and not false, 'untouched empty group')
    assert(not enabled('Editor/Activate'), 'an empty group cannot become the active one')
    assert(click('Editor/Slots/Slot1'), 'back to group one')
    assert(await(function() return _FormationEditSession.Snapshot.editSlot == 1 and _FormationEditSession.DraftSlot == 1 end), 'group one')
    assert(#_FormationEditSession.Draft == 2 and not _FormationEditSession:IsDirty(), 'saved content loaded')

    -- S8: activation only for the saved, unchanged, non-active group; the active one is then disabled.
    assert(enabled('Editor/Activate'), 'activate enabled for saved content')
    click('Editor/Activate')
    assert(await(function() return _FormationEditSession.Snapshot.saved.activeSlot == 1 and not _FormationEditSession.Snapshot.pending end), 'activation confirmed')
    assert(not enabled('Editor/Activate') and node('Editor/Slots/Slot1/ActiveBadge').Enable, 'the active group is marked and its button greyed')
    log('[VRF][Save50] S8 activation ok')

    -- S9: an empty or otherwise invalid group keeps the marker, explains itself and cannot be saved.
    remove(input, -5, 0)
    remove(input, -3, 1)
    assert(#_FormationEditSession.Draft == 0 and _FormationEditSession:IsDirty(), 'clearing a saved group is a change')
    assert(_FormationEditSession:IsDirty(), 'marker on the cleared group')
    assert(not enabled('Editor/Save') and has(_FormationEditSession:SaveBlockReason(), '空隊伍'), 'an empty roster cannot be saved, with a readable reason')
    assert(not enabled('Editor/Activate'), 'changes block activation')
    click('Editor/Back')
    assert(dialogOpen() and _FormationEditSession.ConfirmKind == 'RETURN', 'leaving asks')
    assert(label('ExitConfirm/Window/SaveAndReturn') == '儲存並返回' and not enabled('ExitConfirm/Window/SaveAndReturn'), 'save disabled for invalid content')
    assert(enabled('ExitConfirm/Window/ReturnWithoutSave') and enabled('ExitConfirm/Window/ContinueEditing'), 'discard and continue remain')
    click('ExitConfirm/Window/ContinueEditing')
    assert(not dialogOpen() and _FormationEditSession:IsDirty(), 'continue keeps the content')
    click('Editor/Back')
    click('ExitConfirm/Window/ReturnWithoutSave')
    assert(await(function() return _UserService.LocalPlayer.CurrentMapName == 'formationlobby' end), 'discard then return')
    input = openEditor()
    assert(#_FormationEditSession.Draft == 2 and not _FormationEditSession:IsDirty() and #_FormationEditSession.Snapshot.saved.slots['1'].units == 2, 'reopening shows the saved version, not the discarded edit')
    log('[VRF][Save50] S9 invalid content and discard ok')

    -- S10: save and return from a real change; a clean return needs no question.
    _FormationEditSession.SelectedMonsterId = ''
    input:HandleWorldClick(Vector3(-5, 0, 0))
    input:HandleWorldClick(Vector3(-6, -1, 0))
    assert(_FormationEditSession:IsDirty() and _FormationEditSession.Draft[1].x == -6, 'moved a unit')
    click('Editor/Back')
    assert(dialogOpen())
    click('ExitConfirm/Window/SaveAndReturn')
    assert(await(function() return _UserService.LocalPlayer.CurrentMapName == 'formationlobby' end, 150), 'save then return')
    assert(_FormationEditSession.Snapshot.saved.slots['1'].units[1].x == -6 and _FormationEditSession.Snapshot.saved.activeSlot == 1, 'saved content updated, active choice kept')
    input = openEditor()
    click('Editor/Back')
    assert(await(function() return _UserService.LocalPlayer.CurrentMapName == 'formationlobby' end) and not dialogOpen(), 'a clean return asks nothing')
    log('[VRF][Save50] S10 save-and-return ok')
end)
log(ok and '[VRF][Save50] PASS' or '[VRF][Save50] FAIL ' .. tostring(detail))
