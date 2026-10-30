-- Client: follow READY with maker_mouse_input move=(640,540), left click (1920x1080 reference).
local l = _FormationLobby
local function await(predicate)
    for _=1,150 do if predicate() then return true end wait(.1) end
    return false
end
local function click(path) l:Ui(path):SendEvent(ButtonClickEvent()) end
local originalSlot = l.Snapshot.editSlot
local backup = nil
local ok, detail = pcall(function()
    click('Lobby/Slots/Slot5')
    assert(await(function() return l.Snapshot.editSlot == 5 end), 'fixture slot selected')
    backup = _FormationSchema:CopyUnits(l.Snapshot.draft)
    local version=l.Snapshot.draftVersion
    if #backup > 0 then
        _FormationService:RequestDraft({},version,5)
        assert(await(function() return #l.Snapshot.draft == 0 end), 'fixture cleared')
    end
    click('Lobby/Edit')
    assert(await(function() return _UserService.LocalPlayer.CurrentMapName == 'formationsim' end), 'real editor')
    wait(.3)
    click('Editor/Catalog/Monster1')
    local saved=_FormationSchema:EncodeDocument(l.Snapshot.saved)
    local expected=_UILogic:ScreenToWorldPosition(Vector2(640,540))
    log('[VRF][EditorNativeInput] READY native left click=(640,540) expected='..tostring(expected.x)..','..tostring(expected.y))
    assert(await(function() return #l.Snapshot.draft == 1 end), 'real screen input reaches battlefield')
    local unit=l.Snapshot.draft[1]
    assert(math.abs(unit.x-expected.x)<.001 and math.abs(unit.y-expected.y)<.001, 'native camera conversion preserves position')
    assert(_FormationSchema:EncodeDocument(l.Snapshot.saved)==saved, 'native placement changes only draft')
end)
if backup ~= nil and l.Snapshot.editSlot == 5 then
    _FormationService:RequestDraft(backup,l.Snapshot.draftVersion,5)
    await(function() return _FormationSchema:SameUnits(l.Snapshot.draft,backup) end)
end
_FormationService:RequestSelectSlot(originalSlot)
log(ok and '[VRF][EditorNativeInput] PASS' or '[VRF][EditorNativeInput] FAIL '..tostring(detail))
