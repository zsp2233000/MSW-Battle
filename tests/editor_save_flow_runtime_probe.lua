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
local function inEditor() return _UserService.LocalPlayer.CurrentMapName == 'formationsim' and l.DraftSlot == l.Snapshot.editSlot end
local function openEditor()
    assert(click('Lobby/Edit'), 'edit button enabled')
    assert(await(inEditor), 'editor entered')
    wait(0.4)
    return _UserService.LocalPlayer.CurrentMap:GetComponent('FormationMapInput')
end
local function armCard() click('Editor/Catalog/Monster1') end
local function remove(input, x, y)
    -- Right-click removal applies only with no armed preview.
    l.SelectedMonsterId = ''
    l.SelectedUnit = 0
    input:HandleWorldRemoval(Vector3(x, y, 0))
end

local ok, detail = pcall(function()
    if dialogOpen() then l:ContinueEditing() end
    _FormationService:RequestRetryLoad()
    assert(await(function() return l.Snapshot.loadState == 'NEW' end), 'isolated new-player fixture')
    local input = openEditor()

    -- S1: a never-edited empty group is clean, and save/activate are visible but disabled.
    assert(not l:IsDirty() and #l.Draft == 0 and l.DraftSlot == 1, 'opens from the saved version')
    assert(node('Editor/Save').EnabledInHierarchy and node('Editor/Activate').EnabledInHierarchy, 'save and activate stay visible')
    assert(not enabled('Editor/Save') and not enabled('Editor/Activate'), 'disabled without changes or saved content')
    assert(not has(label('Editor/Slots/Slot1'), '*'), 'clean group has no marker')
    assert(node('Editor/Slots/Slot1/EditFrame').Enable and not node('Editor/Slots/Slot2/EditFrame').Enable, 'viewed group has the highlight frame')
    assert(not node('Editor/Slots/Slot1/ActiveBadge').Enable, 'no active group yet')
    log('[VRF][Save50] S1 initial state ok')

    -- S2: an edit stays in the client: no server reply, marker appears, save becomes usable.
    armCard()
    local sequence = l.ObservedSequence
    input:HandleWorldClick(Vector3(-5, 0, 0))
    assert(#l.Draft == 1 and l:IsDirty(), 'unit placed locally')
    wait(0.6)
    assert(l.ObservedSequence == sequence, 'an edit makes no server round trip')
    assert(has(label('Editor/Slots/Slot1'), '*'), 'unsaved marker on the viewed group')
    assert(not has(label('Editor/Slots/Slot2'), '*'), 'other groups unmarked')
    assert(enabled('Editor/Save') and not enabled('Editor/Activate'), 'valid change enables save only')
    assert(label('Editor/Save') == '儲存隊伍', 'save label')
    log('[VRF][Save50] S2 local edit ok')

    -- S3: restoring the exact saved content removes the marker and disables save again.
    remove(input, -5, 0)
    assert(#l.Draft == 0 and not l:IsDirty(), 'exact restoration')
    assert(not has(label('Editor/Slots/Slot1'), '*') and not enabled('Editor/Save'), 'marker removed and save disabled')
    log('[VRF][Save50] S3 exact restoration ok')

    -- S4: one rule set for the preview and the edit: spacing, side, capacity, moving.
    armCard()
    input:HandleWorldClick(Vector3(-5, 0, 0))
    input:HandleWorldClick(Vector3(-4.71, 0, 0))
    assert(#l.Draft == 1 and l.SelectedUnit == 0, '0.29 apart is refused and does not select the neighbour')
    input:HandleWorldClick(Vector3(-4.7, 0, 0))
    assert(#l.Draft == 2, '0.30 apart is accepted')
    input:HandleWorldClick(Vector3(5, 0, 0))
    assert(#l.Draft == 2, 'the enemy half is refused')
    assert(l.SelectedMonsterId ~= '' and l:PreviewMode() == 'PLACE', 'a legal placement keeps the card armed for continuous deployment')
    assert(not l:CanPlaceAt(-8, 2), 'a spot whose mirror lands on a wall is refused')
    for _, p in ipairs({ { -7, 2 }, { -6, 2 }, { -5, 2 }, { -4, 2 } }) do input:HandleWorldClick(Vector3(p[1], p[2], 0)) end
    assert(#l.Draft == 6, 'six units')
    assert(not l:CanPlaceAt(-3, -2), 'a seventh unit is illegal (the preview turns red)')
    input:HandleWorldClick(Vector3(-3, -2, 0))
    assert(#l.Draft == 6, 'a seventh unit is not added')
    l.SelectedMonsterId = ''
    input:HandleWorldClick(Vector3(-5, 0, 0))
    assert(l.SelectedUnit == 1 and l:PreviewMode() == 'MOVE', 'without a preview a click selects a unit')
    input:HandleWorldClick(Vector3(-5.05, -0.05, 0))
    -- Vector3 stores float32, so compare coordinates with a tolerance.
    assert(#l.Draft == 6 and math.abs(l.Draft[1].x + 5.05) < 0.0001, 'a full roster can still move a unit; its own spot is excluded')
    input:HandleWorldClick(Vector3(-4.7, 0.05, 0))
    assert(math.abs(l.Draft[1].x + 5.05) < 0.0001, 'an illegal move changes nothing and keeps the selection')
    assert(l.SelectedUnit == 1, 'selection survives an invalid click')
    log('[VRF][Save50] S4 shared placement rules ok')

    -- S5: switching with changes asks; every choice behaves as promised.
    assert(click('Editor/Slots/Slot2'), 'slot button')
    assert(dialogOpen() and l._T.confirmKind == 'SWITCH', 'switch confirmation')
    assert(label('ExitConfirm/Window/SaveAndReturn') == '儲存並切換' and label('ExitConfirm/Window/ReturnWithoutSave') == '不儲存切換'
        and label('ExitConfirm/Window/ContinueEditing') == '繼續編輯', 'switch choices')
    assert(not enabled('Editor/Save') and l:PreviewMode() == '', 'editing is paused while asking')
    click('ExitConfirm/Window/ContinueEditing')
    assert(not dialogOpen() and l.Snapshot.editSlot == 1 and #l.Draft == 6, 'continue keeps the group and its content')
    click('Editor/Slots/Slot2')
    click('ExitConfirm/Window/ReturnWithoutSave')
    assert(await(function() return l.Snapshot.editSlot == 2 and l.DraftSlot == 2 end), 'discard then switch')
    assert(#l.Draft == 0 and not l:IsDirty(), 'the target group opens from its saved version')
    assert(click('Editor/Slots/Slot1'), 'clean switch needs no question')
    assert(await(function() return l.Snapshot.editSlot == 1 and l.DraftSlot == 1 end) and not dialogOpen(), 'switched back directly')
    assert(#l.Draft == 0 and #l.Snapshot.saved.slots['1'].units == 0, 'discarded content is gone and nothing was stored')
    log('[VRF][Save50] S5 switch choices ok')

    -- S6: save and switch writes only the viewed group; saving never activates.
    armCard()
    input:HandleWorldClick(Vector3(-5, 0, 0))
    input:HandleWorldClick(Vector3(-3, 1, 0))
    assert(#l.Draft == 2 and enabled('Editor/Save'), 'two units')
    click('Editor/Slots/Slot2')
    assert(enabled('ExitConfirm/Window/SaveAndReturn'), 'valid content may be saved')
    click('ExitConfirm/Window/SaveAndReturn')
    assert(await(function() return l.Snapshot.editSlot == 2 and l.DraftSlot == 2 and not l.Snapshot.pending end, 150), 'saved and switched')
    local saved = l.Snapshot.saved
    assert(#saved.slots['1'].units == 2 and #saved.slots['2'].units == 0, 'only the viewed group changed')
    assert(saved.activeSlot == 0 and not node('Editor/Slots/Slot1/ActiveBadge').Enable, 'saving did not activate')
    assert(not dialogOpen(), 'the confirmation closed after success')
    log('[VRF][Save50] S6 single-group save ok')

    -- S7: an unmodified empty group and a touched-then-restored group show no marker.
    assert(not l:IsDirty() and not has(label('Editor/Slots/Slot2'), '*'), 'untouched empty group')
    assert(not enabled('Editor/Activate'), 'an empty group cannot become the active one')
    assert(click('Editor/Slots/Slot1'), 'back to group one')
    assert(await(function() return l.Snapshot.editSlot == 1 and l.DraftSlot == 1 end), 'group one')
    assert(#l.Draft == 2 and not l:IsDirty(), 'saved content loaded')

    -- S8: activation only for the saved, unchanged, non-active group; the active one is then disabled.
    assert(enabled('Editor/Activate'), 'activate enabled for saved content')
    click('Editor/Activate')
    assert(await(function() return l.Snapshot.saved.activeSlot == 1 and not l.Snapshot.pending end), 'activation confirmed')
    assert(not enabled('Editor/Activate') and node('Editor/Slots/Slot1/ActiveBadge').Enable, 'the active group is marked and its button greyed')
    log('[VRF][Save50] S8 activation ok')

    -- S9: an empty or otherwise invalid group keeps the marker, explains itself and cannot be saved.
    remove(input, -5, 0)
    remove(input, -3, 1)
    assert(#l.Draft == 0 and l:IsDirty(), 'clearing a saved group is a change')
    assert(has(label('Editor/Slots/Slot1'), '*'), 'marker on the cleared group')
    assert(not enabled('Editor/Save') and has(l:SaveBlockReason(), '空隊伍'), 'an empty roster cannot be saved, with a readable reason')
    assert(not enabled('Editor/Activate'), 'changes block activation')
    click('Editor/Back')
    assert(dialogOpen() and l._T.confirmKind == 'RETURN', 'leaving asks')
    assert(label('ExitConfirm/Window/SaveAndReturn') == '儲存並返回' and not enabled('ExitConfirm/Window/SaveAndReturn'), 'save disabled for invalid content')
    assert(enabled('ExitConfirm/Window/ReturnWithoutSave') and enabled('ExitConfirm/Window/ContinueEditing'), 'discard and continue remain')
    click('ExitConfirm/Window/ContinueEditing')
    assert(not dialogOpen() and l:IsDirty(), 'continue keeps the content')
    click('Editor/Back')
    click('ExitConfirm/Window/ReturnWithoutSave')
    assert(await(function() return _UserService.LocalPlayer.CurrentMapName == 'formationlobby' end), 'discard then return')
    input = openEditor()
    assert(#l.Draft == 2 and not l:IsDirty() and #l.Snapshot.saved.slots['1'].units == 2, 'reopening shows the saved version, not the discarded edit')
    log('[VRF][Save50] S9 invalid content and discard ok')

    -- S10: save and return from a real change; a clean return needs no question.
    l.SelectedMonsterId = ''
    input:HandleWorldClick(Vector3(-5, 0, 0))
    input:HandleWorldClick(Vector3(-6, -1, 0))
    assert(l:IsDirty() and l.Draft[1].x == -6, 'moved a unit')
    click('Editor/Back')
    assert(dialogOpen())
    click('ExitConfirm/Window/SaveAndReturn')
    assert(await(function() return _UserService.LocalPlayer.CurrentMapName == 'formationlobby' end, 150), 'save then return')
    assert(l.Snapshot.saved.slots['1'].units[1].x == -6 and l.Snapshot.saved.activeSlot == 1, 'saved content updated, active choice kept')
    input = openEditor()
    click('Editor/Back')
    assert(await(function() return _UserService.LocalPlayer.CurrentMapName == 'formationlobby' end) and not dialogOpen(), 'a clean return asks nothing')
    log('[VRF][Save50] S10 save-and-return ok')
end)
log(ok and '[VRF][Save50] PASS' or '[VRF][Save50] FAIL ' .. tostring(detail))
