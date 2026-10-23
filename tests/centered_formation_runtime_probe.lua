-- Client: public editing/save/activation RPCs and their private observations. First run uses a fresh V2 account.
local ok, detail = pcall(function()
    local lobby = _FormationLobby
    local function untilState(predicate)
        for i = 1, 150 do if predicate() then return true end wait(0.1) end
        return false
    end
    local function click(path)
        _EntityService:GetEntityByPath('/ui/FormationGroup/' .. path):SendEvent(ButtonClickEvent())
    end
    _FormationService:RequestOpen()
    assert(untilState(function() return lobby.Snapshot.loadState == 'NEW' or lobby.Snapshot.loadState == 'READY' end), 'load completes')
    assert(lobby.Snapshot.saved.schema == 2, 'new coordinate schema')
    if lobby.Snapshot.loadState == 'NEW' then
        assert(lobby.Snapshot.saved.activeSlot == 0, 'new document has no active formation')
        for i = 1, 5 do assert(#lobby.Snapshot.saved.slots[tostring(i)].units == 0, 'all five slots empty') end
        log('[VRF][CenteredFormation] EMPTY_V2_PASS')
    else
        local saved = lobby.Snapshot.saved.slots['1'].units
        assert(lobby.Snapshot.saved.activeSlot == 1 and #saved == 1, 'relogin retains active saved formation')
        assert(math.abs(saved[1].x + 4.35) < 0.0001 and math.abs(saved[1].y - 0.65) < 0.0001, 'relogin restores fractional coordinates')
        log('[VRF][CenteredFormation] RELOGIN_PASS')
    end
    click('Lobby/Edit')
    assert(untilState(function() return _UserService.LocalPlayer.CurrentMapName == 'formationsim' end), 'enter editor')
    local input = _UserService.LocalPlayer.CurrentMap:GetComponent('script.FormationMapInput')
    local function edit(units, accepted, label)
        local before = lobby.Snapshot.draftVersion
        local seq = lobby.ObservedSequence
        _FormationService:RequestDraft(units, before, 1)
        assert(untilState(function() return lobby.ObservedSequence > seq end), label .. ' observed')
        assert((lobby.Snapshot.draftVersion > before) == accepted, label)
    end
    local function unit(x, y) return {monsterId = 'monster_tank', x = x, y = y} end
    for _, point in ipairs({{0,0}, {1,0}, {-15,0}, {-15.01,0}, {-16,0}, {-1,8}, {-1,-8.01}, {-1,9.5}, {-1,math.huge}, {-math.huge,0}, {0/0,0}}) do
        edit({unit(point[1], point[2])}, false, 'reject centre/right/wall/boundary/nonfinite')
    end
    edit({unit(-14.99,-8)}, true, 'valid horizontal and bottom boundary')
    edit({unit(-0.01,7.99)}, true, 'valid near centre and top')
    edit({unit(-3.25,0.65),unit(-3.25,0.65)}, false, 'reject overlap')
    edit({unit(-3.25,0.65),unit(-3.10,0.65)}, false, 'reject minimum separation')
    local seven = {}
    for i = 1, 7 do seven[i] = unit(-i, 0) end
    edit(seven, false, 'reject seventh unit')
    local before = lobby.Snapshot.draftVersion
    _FormationService:RequestDraft({}, before, 1)
    assert(untilState(function() return lobby.Snapshot.draftVersion > before end), 'clear temporary accepted points')
    click('Editor/Catalog/Monster1')
    before = lobby.Snapshot.draftVersion
    input:HandleWorldClick(Vector3(-4.35, 0.65, 0))
    assert(untilState(function() return lobby.Snapshot.draftVersion > before end), 'world click retains fractions')
    assert(untilState(function() return input.PreviewCount == 1 end), 'private preview generated')
    local preview = _EntityService:GetEntityByPath('/maps/formationsim/FormationPreview_1')
    assert(math.abs(preview.TransformComponent.WorldPosition.x + 4.35) < 0.0001, 'preview matches exact x')
    assert(math.abs(preview.TransformComponent.WorldPosition.y - 0.65) < 0.0001, 'preview matches exact y')
    local submittedX, submittedY = lobby.Snapshot.draft[1].x, lobby.Snapshot.draft[1].y
    local initialActive = lobby.Snapshot.saved.activeSlot
    click('Editor/Save')
    assert(untilState(function() return lobby.Snapshot.saveState == 'SAVED' and not lobby.Snapshot.pending end), 'durable save')
    assert(lobby.Snapshot.saved.activeSlot == initialActive, 'saving does not activate')
    assert(lobby.Snapshot.saved.slots['1'].units[1].x == submittedX and lobby.Snapshot.saved.slots['1'].units[1].y == submittedY, 'save exact submitted continuous coordinates')
    click('Editor/Activate')
    assert(untilState(function() return lobby.Snapshot.saved.activeSlot == 1 and not lobby.Snapshot.pending end), 'durable activation')
    click('Editor/Back')
    assert(untilState(function() return _UserService.LocalPlayer.CurrentMapName == 'formationlobby' end), 'return lobby')
    assert(not isvalid(preview), 'preview cleaned on departure')
    click('Lobby/Edit')
    assert(untilState(function() return _UserService.LocalPlayer.CurrentMapName == 'formationsim' end), 'reenter editor')
    assert(lobby.Snapshot.saved.activeSlot == 1 and #lobby.Snapshot.draft == 1, 'normal reentry retains V2')
    log('[VRF][CenteredFormation] PASS boundary rejection; exact preview/save/activation; reentry preserves V2')
end)
if not ok then log('[VRF][CenteredFormation] FAIL ' .. tostring(detail)) end
