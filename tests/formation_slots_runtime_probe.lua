-- Client: connected player controls and public snapshots, no session internals.
local function await(predicate)
    for index = 1, 100 do if predicate() then return true end wait(0.1) end
    return false
end
local function click(path)
    _EntityService:GetEntityByPath('/ui/FormationGroup/' .. path):SendEvent(ButtonClickEvent())
end
local l = _FormationLobby
local function selectSlot(slot)
    click('Editor/Slots/Slot' .. tostring(slot))
    assert(await(function() return l.Snapshot.editSlot == slot end), 'select slot ' .. tostring(slot))
end
local ok, detail = pcall(function()
    assert(await(function() return l.Snapshot.loadState == 'READY' or l.Snapshot.loadState == 'NEW' end), 'load completes')
    click('Lobby/Slots/Slot2')
    assert(await(function() return l.Snapshot.editSlot == 2 end), 'second slot selected')
    click('Lobby/Edit')
    assert(await(function() return _UserService.LocalPlayer.CurrentMapName == 'formationsim' end), 'enter editor')
    local input = _UserService.LocalPlayer.CurrentMap:GetComponent('FormationMapInput')
    -- On the first run #28 leaves this slot empty; later runs still test empty drafts.
    selectSlot(5)
    local version = l.Snapshot.draftVersion
    _FormationService:RequestDraft({}, version, 5)
    assert(await(function() return #l.Snapshot.draft == 0 end), 'empty draft')
    if #l.Snapshot.saved.slots['5'].units == 0 then
        local active = l.Snapshot.saved.activeSlot
        assert(not _EntityService:GetEntityByPath('/ui/FormationGroup/Editor/Activate').ButtonComponent.Enable, 'empty slot cannot activate')
        _FormationService:RequestActivate(5, l.Snapshot.saved.slots['5'].revision)
        wait(0.3)
        assert(l.Snapshot.saved.activeSlot == active and not l.Snapshot.pending, 'empty slot rejected by server')
        assert(string.find(_EntityService:GetEntityByPath('/ui/FormationGroup/Editor/Slots/Slot5').TextGUIRendererComponent.Text, '空欄位'), 'empty label')
    end
    for slot = 1, 5 do
        selectSlot(slot)
        version = l.Snapshot.draftVersion
        _FormationService:RequestDraft({}, version, slot)
        assert(await(function() return #l.Snapshot.draft == 0 end), 'clear slot draft')
        click('Editor/Catalog/Monster' .. tostring((slot - 1) % 3 + 1))
        for unit = 1, slot do
            version = l.Snapshot.draftVersion
            input:HandleWorldClick(Vector3(-5.25 + (unit - 1) * 0.9, 0.65, 0))
            assert(await(function() return l.Snapshot.draftVersion > version end), 'place unit')
        end
        local active = l.Snapshot.saved.activeSlot
        local revisions = {}
        for other = 1, 5 do revisions[other] = l.Snapshot.saved.slots[tostring(other)].revision end
        click('Editor/Save')
        assert(await(function() return l.Snapshot.saveState == 'SAVED' and not l.Snapshot.pending end), 'save slot ' .. tostring(slot))
        assert(l.Snapshot.saved.activeSlot == active, 'saving preserves active selection')
        for other = 1, 5 do
            if other ~= slot then assert(l.Snapshot.saved.slots[tostring(other)].revision == revisions[other], 'other slots untouched') end
        end
        if slot == 1 then
            click('Editor/Activate')
            assert(await(function() return l.Snapshot.saved.activeSlot == 1 and not l.Snapshot.pending end), 'one saved slot suffices')
        end
    end
    for slot = 1, 5 do
        selectSlot(slot)
        assert(#l.Snapshot.draft == slot and #l.Snapshot.saved.slots[tostring(slot)].units == slot, 'independent count')
        assert(l.Snapshot.draft[1].monsterId == l.Snapshot.options[(slot - 1) % 3 + 1][1], 'independent monster')
        assert(math.abs(l.Snapshot.draft[1].x + 5.25) < 0.001, 'fractional coordinates')
    end
    selectSlot(2)
    version = l.Snapshot.draftVersion
    input:HandleWorldClick(Vector3(-5.25, 0.65, 0))
    input:HandleWorldClick(Vector3(-5.25, -0.35, 0))
    assert(await(function() return l.Snapshot.draftVersion > version end), 'unsaved move')
    local draftVersion = l.Snapshot.draftVersion
    selectSlot(3)
    assert(await(function() return input.PreviewCount == 3 end), 'third slot previews')
    selectSlot(2)
    assert(await(function() return input.PreviewCount == 2 end), 'second slot previews')
    assert(l.Snapshot.draftVersion == draftVersion and l.Snapshot.saveState == 'UNSAVED', 'draft version retained')
    assert(math.abs(l.Snapshot.draft[1].y + 0.35) < 0.001 and math.abs(l.Snapshot.saved.slots['2'].units[1].y - 0.65) < 0.001, 'draft distinct from saved')
    assert(l.Snapshot.saved.activeSlot == 1, 'editing other groups preserves first active')
    local before = l.Snapshot.draftVersion
    _FormationService:RequestDraft({}, before, 3)
    _FormationService:RequestSave(before, 3)
    _FormationService:RequestActivate(3, l.Snapshot.saved.slots['3'].revision)
    wait(0.4)
    assert(l.Snapshot.editSlot == 2 and l.Snapshot.draftVersion == before and l.Snapshot.saved.activeSlot == 1, 'late commands for another slot rejected')
    click('Editor/Back')
    assert(await(function() return _UserService.LocalPlayer.CurrentMapName == 'formationlobby' end), 'return lobby')
    assert(l.Snapshot.editSlot == 2 and l.Snapshot.slots['2'].dirty, 'draft remains visible in lobby')
    click('Lobby/Slots/Slot4')
    assert(await(function() return l.Snapshot.editSlot == 4 end), 'lobby selects independently')
    click('Lobby/Slots/Slot2')
    assert(await(function() return l.Snapshot.editSlot == 2 end), 'return draft from lobby')
end)
log(ok and '[VRF][FormationSlots] PASS' or '[VRF][FormationSlots] FAIL ' .. tostring(detail))
