-- Client, fresh Stop/Play after slots -> delayed -> failure probes.
local l = _FormationLobby
local function await(predicate)
    for index = 1, 100 do if predicate() then return true end wait(0.1) end
    return false
end
local ok, detail = pcall(function()
    assert(await(function() return l.Snapshot.loadState == 'READY' end), 'load saved document')
    assert(l.Snapshot.saved.activeSlot == 4, 'independent activation persists across login')
    for slot = 1, 5 do
        _EntityService:GetEntityByPath('/ui/FormationGroup/Lobby/Slots/Slot' .. tostring(slot)):SendEvent(ButtonClickEvent())
        assert(await(function() return l.Snapshot.editSlot == slot end), 'select restored slot')
        assert(#l.Snapshot.draft == slot and l.Snapshot.saveState == 'SAVED', 'independent count and saved state restored')
        assert(l.Snapshot.draft[1].monsterId == l.Snapshot.options[(slot - 1) % 3 + 1][1], 'monster ID restored')
        local y = slot == 2 and -0.35 or (slot == 3 and -1.35 or 0.65)
        assert(math.abs(l.Snapshot.draft[1].x + 5.25) < 0.001 and math.abs(l.Snapshot.draft[1].y - y) < 0.001, 'only confirmed positions restored')
        assert(l.Snapshot.saved.activeSlot == 4, 'editing restores without changing active selection')
    end
    assert(math.abs(l.Snapshot.draft[1].y - 0.65) < 0.001, 'unsaved fifth-slot draft not persisted')
end)
log(ok and '[VRF][FormationSlotsRelogin] PASS' or '[VRF][FormationSlotsRelogin] FAIL ' .. tostring(detail))
