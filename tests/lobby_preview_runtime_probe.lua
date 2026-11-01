-- Client, from the lobby. Uses connected selectors and service observations; never writes storage.
local function await(predicate)
    for index = 1, 100 do if predicate() then return true end wait(0.1) end
    return false
end
local lobby = _FormationLobby
local function click(path) lobby:Ui(path):SendEvent(ButtonClickEvent()) end
local ok, detail = pcall(function()
    assert(await(function() return _FormationEditSession.Snapshot.loadState == 'READY' or _FormationEditSession.Snapshot.loadState == 'NEW' end), 'formation load')
    assert(_UserService.LocalPlayer.CurrentMapName == 'formationlobby', 'start in lobby')
    local field = lobby:Ui('Lobby/Command/Field')
    assert(isvalid(field) and field.EnabledInHierarchy, 'saved active formation preview is visible')
    local originalSlot = _FormationEditSession.Snapshot.editSlot
    local active = _FormationEditSession.Snapshot.saved.activeSlot
    local expected = _FormationEditSession.Snapshot.saved.slots[tostring(originalSlot)].units
    for index = 1, 6 do
        local marker = lobby:Ui('Lobby/Command/Field/Unit' .. tostring(index))
        assert(isvalid(marker), 'authored preview marker')
        assert(marker.Enable == (expected[index] ~= nil), 'selected saved count, not active group or draft')
        if marker.Enable then
            local portrait = marker:GetChildByName('Portrait', false)
            local pos = portrait.UITransformComponent.anchoredPosition
            assert(portrait.EnabledInHierarchy and pos.x == 0 and math.abs(pos.y) <= 24, 'monster image directly occupies its saved position')
            assert(not isvalid(marker:GetChildByName('Link', false)), 'no roster connector')
        end
    end
    for first = 1, #expected do
        local a = lobby:Ui('Lobby/Command/Field/Unit' .. tostring(first))
        local pa = a.UITransformComponent.anchoredPosition
        for second = first + 1, #expected do
            local b = lobby:Ui('Lobby/Command/Field/Unit' .. tostring(second))
            local pb = b.UITransformComponent.anchoredPosition
            local dx, dy = expected[second].x - expected[first].x, expected[second].y - expected[first].y
            local sx, sy = pb.x - pa.x, pb.y - pa.y
            assert(math.abs(sx * dy - sy * dx) < 0.01 and sx * dx + sy * dy > 0, 'relative direction and proportions')
        end
    end
    for slot = 1, 5 do
        click('Lobby/Slots/Slot' .. tostring(slot))
        assert(await(function() return _FormationEditSession.Snapshot.editSlot == slot end), 'connected selector')
        assert(_FormationEditSession.Snapshot.saved.activeSlot == active, 'selection never activates')
        local selectedUnits = _FormationEditSession.Snapshot.saved.slots[tostring(slot)].units
        assert(string.find(lobby:Ui('Lobby/Summary').TextGUIRendererComponent.Text, '第 ' .. tostring(slot) .. ' 組'), 'preview identifies selected group')
        local label = lobby:Ui('Lobby/Slots/Slot' .. tostring(slot)).TextGUIRendererComponent.Text
        assert(string.find(label, '編輯'), 'editing label')
        for index = 1, 6 do
            local marker = lobby:Ui('Lobby/Command/Field/Unit' .. tostring(index))
            assert(marker.Enable == (selectedUnits[index] ~= nil), 'selection changes preview to that group')
            if selectedUnits[index] ~= nil then
                for _, option in ipairs(_FormationEditSession.Snapshot.options) do
                    if option[1] == selectedUnits[index].monsterId then
                        assert(marker:GetChildByName('Portrait', false).SpriteGUIRendererComponent.ImageRUID.DataId == 'thumbnail://' .. option[3], 'selected group monster identity')
                    end
                end
            end
        end
        assert(lobby:Ui('Lobby/Command/Field/Empty').Enable == (#selectedUnits == 0), 'empty group clears previous portraits')
        if active > 0 then
            local title = _MatchProbeInput.root:GetChildByName('Title', true)
            assert(await(function() return string.find(title.TextGUIRendererComponent.Text, '出戰第 ' .. tostring(active) .. ' 組') end), 'match title retains actual active group')
        end
    end
    wait(0.4) -- This is a single selection, not the new double-click shortcut.
    click('Lobby/Slots/Slot' .. tostring(originalSlot))
    assert(await(function() return _FormationEditSession.Snapshot.editSlot == originalSlot end), 'restore selection')
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
    log('[VRF][LobbyPreview] PASS selected saved previews; empty groups clear; active unchanged; preparation and POC round trips')
end)
if not ok then log('[VRF][LobbyPreview] FAIL ' .. tostring(detail)) end
