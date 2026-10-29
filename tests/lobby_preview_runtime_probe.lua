-- Client, from the lobby. Uses connected selectors and service observations; never writes storage.
local function await(predicate)
    for index = 1, 100 do if predicate() then return true end wait(0.1) end
    return false
end
local lobby = _FormationLobby
local function click(path) lobby:Ui(path):SendEvent(ButtonClickEvent()) end
local ok, detail = pcall(function()
    assert(await(function() return lobby.Snapshot.loadState == 'READY' or lobby.Snapshot.loadState == 'NEW' end), 'formation load')
    assert(_UserService.LocalPlayer.CurrentMapName == 'formationlobby', 'start in lobby')
    local field = lobby:Ui('Lobby/Command/Field')
    assert(isvalid(field) and field.EnabledInHierarchy, 'saved active formation preview is visible')
    local originalSlot = lobby.Snapshot.editSlot
    local active = lobby.Snapshot.saved.activeSlot
    local expected = active > 0 and lobby.Snapshot.saved.slots[tostring(active)].units or {}
    local count = 0
    for index = 1, 6 do
        local marker = lobby:Ui('Lobby/Command/Field/Unit' .. tostring(index))
        assert(isvalid(marker), 'authored preview marker')
        assert(marker.Enable == (expected[index] ~= nil), 'saved active count, not selected draft')
        if marker.Enable then count = count + 1 end
    end
    for first = 1, #expected do
        local a = lobby:Ui('Lobby/Command/Field/Unit' .. tostring(first))
        local pa = a.UITransformComponent.anchoredPosition
        local labelA = a:GetChildByName('Name', false).UITransformComponent.anchoredPosition
        for second = first + 1, #expected do
            local b = lobby:Ui('Lobby/Command/Field/Unit' .. tostring(second))
            local pb = b.UITransformComponent.anchoredPosition
            local dx, dy = expected[second].x - expected[first].x, expected[second].y - expected[first].y
            local sx, sy = pb.x - pa.x, pb.y - pa.y
            assert(math.abs(sx * dy - sy * dx) < 0.01 and sx * dx + sy * dy > 0, 'relative direction and proportions')
            local labelB = b:GetChildByName('Name', false).UITransformComponent.anchoredPosition
            assert(math.abs((pb.y + labelB.y) - (pa.y + labelA.y)) >= 44, 'roster labels remain separate even for dense positions')
        end
    end
    for slot = 1, 5 do
        click('Lobby/Slots/Slot' .. tostring(slot))
        assert(await(function() return lobby.Snapshot.editSlot == slot end), 'connected selector')
        assert(lobby.Snapshot.saved.activeSlot == active, 'selection never activates')
        local label = lobby:Ui('Lobby/Slots/Slot' .. tostring(slot)).TextGUIRendererComponent.Text
        assert(string.find(label, '編輯'), 'editing label')
        for index = 1, 6 do
            assert(lobby:Ui('Lobby/Command/Field/Unit' .. tostring(index)).Enable == (index <= count), 'selection preserves preview')
        end
    end
    click('Lobby/Slots/Slot' .. tostring(originalSlot))
    assert(await(function() return lobby.Snapshot.editSlot == originalSlot end), 'restore selection')
    click('Lobby/Edit')
    assert(await(function() return _UserService.LocalPlayer.CurrentMapName == 'formationsim' end), 'connected preparation entry')
    assert(not field.EnabledInHierarchy, 'lobby preview hidden in simulation')
    click('Editor/Back')
    wait(0.3)
    if lobby:Ui('ExitConfirm').EnabledInHierarchy then click('ExitConfirm/Window/ReturnWithoutSave') end
    assert(await(function() return _UserService.LocalPlayer.CurrentMapName == 'formationlobby' end), 'return from simulation')
    assert(field.EnabledInHierarchy, 'preview restored')
    click('Lobby/Legacy')
    assert(await(function() return _UserService.LocalPlayer.CurrentMapName == 'template' end), 'connected POC entry retained')
    assert(await(function() return not field.EnabledInHierarchy and lobby:Ui('ReturnLobby').EnabledInHierarchy end), 'POC controls visible without lobby overlay')
    click('ReturnLobby')
    assert(await(function() return _UserService.LocalPlayer.CurrentMapName == 'formationlobby' end), 'POC return')
    assert(await(function() return field.EnabledInHierarchy end), 'lobby rendering restored after POC')
    log('[VRF][LobbyPreview] PASS saved active positions; separate labels; five selectors; preparation and POC round trips')
end)
if not ok then log('[VRF][LobbyPreview] FAIL ' .. tostring(detail)) end
