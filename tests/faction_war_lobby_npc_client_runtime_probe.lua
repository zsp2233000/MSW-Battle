-- Maker `client` context, fresh Play, local player standing in any faction war town (the authored start map).
-- Run PART 1 first (final line: [VRF][TownLobby] CLIENT PASS), then PART 3 (GM PASS, needs a GM account), then PART 2 (EDIT PASS).
-- PART 2 leaves the player in the formation editor; stop Play afterwards.
local PART = 1
local function await(predicate, tries) for _ = 1, tries or 100 do if predicate() then return true end wait(0.1) end return false end
local ok, reason = pcall(function()
    local lobby = _FormationLobby
    local player = _UserService.LocalPlayer
    assert(_FactionWar:IsTown(player.CurrentMapName), "client stands in a town")
    if PART == 1 then
        local controller = player.PlayerControllerComponent
        local before = controller.Enable
        assert(not lobby:IsTownPanelOpen() and not lobby.root.Enable, "panel hidden in the town")
        lobby:OpenTownPanel()
        assert(await(function() return lobby.root.Enable end), "root shown")
        assert(lobby:IsTownPanelOpen() and lobby:OnLobbyScreen(), "town panel is the lobby screen")
        assert(await(function() return lobby:Ui("Lobby").Enable end), "Lobby screen enabled over the town")
        assert(not lobby:Ui("ReturnLobby").Enable, "no return-to-lobby button on the town panel")
        assert(not controller.Enable, "walking controls off while the panel is open")
        assert(await(function() return _FactionWarUI:Ui("LobbyClose").Enable end), "close button shown")
        assert(not _FactionWarUI:Ui("TownHUD").Enable, "town HUD hidden under the panel")
        assert(await(function() return _FormationEditSession.Snapshot.loadState ~= nil end, 150), "session load requested")
        lobby:CloseTownPanel()
        assert(await(function() return not lobby.root.Enable end), "root hidden again")
        assert(controller.Enable == before, "controls restored")
        assert(await(function() return _FactionWarUI:Ui("TownHUD").Enable and not _FactionWarUI:Ui("LobbyClose").Enable end), "town HUD back, close hidden")
        log("[VRF][TownLobby] CLIENT PASS in " .. player.CurrentMapName)
    elseif PART == 3 then
        -- The GM entry (and the Maker-only dex entry) must follow the lobby screen onto the town panel.
        local gm = _GMPanel
        local button = gm.lobbyButton.Entity
        assert(not button.Enable, "GM entry hidden while the town panel is closed")
        lobby:OpenTownPanel()
        assert(await(function() return gm._T.authorized end, 100), "GM identity answered for this player")
        assert(await(function() return button.Enable end, 50), "GM entry shown on the town panel")
        lobby:CloseTownPanel()
        assert(await(function() return not button.Enable end, 50), "GM entry hidden again after closing")
        log("[VRF][TownLobby] GM PASS")
    else
        lobby:OpenTownPanel()
        assert(await(function() return _FormationSchema:IsLoadConfirmed(_FormationEditSession.Snapshot.loadState) end, 200), "saved teams loaded")
        assert(await(function() return lobby:Ui("Lobby/Edit").ButtonComponent.Enable end), "edit button usable on the town panel")
        lobby:SelectLobbySlot(1, true)
        assert(await(function() return player.CurrentMapName == "formationsim" end, 200), "edit opens the editor from the town")
        assert(not lobby:IsTownPanelOpen(), "town panel closed when leaving the town")
        log("[VRF][TownLobby] EDIT PASS reached formationsim")
    end
end)
if not ok then log_error("[VRF][TownLobby] PART " .. tostring(PART) .. " FAIL " .. tostring(reason)) end
