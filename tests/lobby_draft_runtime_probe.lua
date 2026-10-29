-- Client, with a valid saved active formation. Changes login drafts only; Stop/Play clears their versions.
local function await(predicate)
    for index = 1, 100 do if predicate() then return true end wait(0.1) end
    return false
end
local l = _FormationLobby
local function click(path) l:Ui(path):SendEvent(ButtonClickEvent()) end
local function select(slot)
    wait(0.4) -- Keep these deliberate single selections outside the double-click window.
    click('Lobby/Slots/Slot' .. tostring(slot))
    assert(await(function() return l.Snapshot.editSlot == slot end), 'select editor target')
end
local originalSlot = l.Snapshot.editSlot
local active = l.Snapshot.saved.activeSlot
local other = active == 1 and 2 or 1
local backups = {}
local positions = {}
local saved = _FormationSchema:EncodeDocument(l.Snapshot.saved)
local function previewUnchanged()
    assert(_FormationSchema:EncodeDocument(l.Snapshot.saved) == saved, 'draft editing never saves or activates')
    for index, position in ipairs(positions) do
        local marker = l:Ui('Lobby/Command/Field/Unit' .. tostring(index))
        local actual = marker.UITransformComponent.anchoredPosition
        assert(marker.Enable and math.abs(actual.x - position.x) < 0.001 and math.abs(actual.y - position.y) < 0.001, 'preview remains saved active positions')
    end
end
local ok, detail = pcall(function()
    assert(l:HasValidActive() and _MatchProbeInput.State == 'IDLE', 'valid active lobby fixture')
    for index = 1, #l.Snapshot.saved.slots[tostring(active)].units do
        local pos = l:Ui('Lobby/Command/Field/Unit' .. tostring(index)).UITransformComponent.anchoredPosition
        positions[index] = {x=pos.x, y=pos.y}
    end
    for _, slot in ipairs({other, active}) do
        select(slot)
        backups[slot] = _FormationSchema:CopyUnits(l.Snapshot.draft)
        local version = l.Snapshot.draftVersion
        local units = slot == active and {} or {{monsterId=l.Snapshot.options[1][1], x=-5.25, y=0.65}}
        _FormationService:RequestDraft(units, version, slot)
        assert(await(function() return l.Snapshot.draftVersion > version end), 'draft changed')
        assert(string.find(l:Ui('Lobby/Slots/Slot' .. tostring(slot)).TextGUIRendererComponent.Text, '草稿'), 'unsaved summary')
        previewUnchanged()
        assert(_MatchProbeInput.action.TextGUIRendererComponent.Text == '開始配對', 'active saved roster still usable with unsaved draft')
    end
end)
-- Restore the original content even when an assertion failed; versions reset on Stop/Play.
for slot, units in pairs(backups) do
    select(slot)
    local version = l.Snapshot.draftVersion
    _FormationService:RequestDraft(units, version, slot)
    assert(await(function() return _FormationSchema:SameUnits(l.Snapshot.draft, units) end), 'draft content restored')
end
select(originalSlot)
log(ok and '[VRF][LobbyDraft] PASS active/other unsaved drafts; saved preview stable; draft contents restored' or '[VRF][LobbyDraft] FAIL ' .. tostring(detail))
