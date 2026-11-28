-- #126 (ADR 0018): the faction choice screen has two colourless Cardgame buttons, "A 方" and "B 方", and each one joins its own faction.
-- Four dispatches, in this order (details and expected lines: tests/README.md, "Faction choice screen (#126)"):
--   1. Fresh Play, `client` context, PART = "CLIENT", CHOICE = "A"   -> [VRF][FactionChoice] CLIENT PASS choice=A town=zuoying profile=<code>
--   2. `server_main` context, PART = "SERVER", CHOICE = "A", PROFILE = <the code line 1 printed>  -> [VRF][FactionChoice] SERVER PASS choice=A (and wipes the stored faction)
--   3. Stop, fresh Play, `client`, PART = "CLIENT", CHOICE = "B"     -> [VRF][FactionChoice] CLIENT PASS choice=B town=gushan profile=<code>
--   4. `server_main`, PART = "SERVER", CHOICE = "B", PROFILE = <code>        -> [VRF][FactionChoice] SERVER PASS choice=B
-- The client part presses the REAL buttons (ButtonClickEvent on the authored entities), so it covers the binding, the server's RequestEntry, the save and the move.
-- It needs a profile that has no faction yet (the server part of the previous run wipes it). Do not run it on a profile whose faction you want to keep:
-- the server part deletes the stored faction and last-town keys of PROFILE.
local PART = "CLIENT"
local CHOICE = "A"
local PROFILE = ""

local PREFIX = "[VRF][FactionChoice] "
local FRONT = { A = "zuoying", B = "gushan" } -- the front town each faction enters first on the initial board
-- Cardgame button art (assets/siege/build_faction_choice_ui.cjs).
local CARD_BUTTON = { normal = "9505617fb63c447c8ff9c15c18d88064" }
local function near(value, expected) return math.abs(value - expected) < 0.005 end
local function await(predicate, tries) for _ = 1, tries or 100 do if predicate() then return true end wait(0.1) end return false end

local ok, reason = pcall(function()
    assert(CHOICE == "A" or CHOICE == "B", "CHOICE is A or B")
    if PART == "CLIENT" then
        local ui = _FactionWarUI
        local player = _UserService.LocalPlayer
        local profile = player.PlayerComponent.ProfileCode
        log(PREFIX .. "client profile=" .. profile .. " map=" .. player.CurrentMapName)
        -- The faction screen opens from the lobby's entry button; a player who logged into a town goes to the lobby first, the way the town NPC does.
        if player.CurrentMapName ~= "formationlobby" then
            _FormationLobby:Travel("formationlobby")
            assert(await(function() return player.CurrentMapName == "formationlobby" end, 150), "reached the lobby (a profile that was queued or engaged cannot travel)")
        end
        local entry = ui:Ui("LobbyEntry")
        assert(await(function() return entry.Enable end, 100), "the lobby entry button is shown")
        entry:SendEvent(ButtonClickEvent())
        local choice = ui:Ui("FactionChoice")
        assert(await(function() return choice.Enable end, 50), "the choice screen opened")
        -- Wait for the server's answer: CHOOSE shows both buttons. A profile that already has a faction goes straight to its front instead.
        local a, b = ui:Ui("FactionChoice/Window/A"), ui:Ui("FactionChoice/Window/B")
        assert(await(function() return a.Enable and b.Enable or player.CurrentMapName ~= "formationlobby" end, 100), "the server answered the entry request")
        assert(player.CurrentMapName == "formationlobby", "this profile already has a faction and went straight to " .. player.CurrentMapName .. "; run the SERVER part with its PROFILE to wipe it, then start a fresh Play")
        assert(a.Enable and b.Enable, "both choice buttons are offered")
        assert(ui:Ui("FactionChoice/Window/Status").TextGUIRendererComponent.Text == "請選擇國戰陣營。", "the prompt")
        -- What a player sees: the same Cardgame button twice, untinted, told apart by the text alone.
        assert(a.TextGUIRendererComponent.Text == "A 方" and b.TextGUIRendererComponent.Text == "B 方", "button texts are A 方 and B 方")
        for _, button in ipairs({ a, b }) do
            local sprite = button.SpriteGUIRendererComponent
            assert(sprite.ImageRUID.DataId == CARD_BUTTON.normal, "Cardgame button art: " .. tostring(sprite.ImageRUID.DataId))
            assert(near(sprite.Color.r, 1) and near(sprite.Color.g, 1) and near(sprite.Color.b, 1) and near(sprite.Color.a, 1), "untinted")
            assert(button.ButtonComponent.Enable, "clickable")
        end
        local sizeA, sizeB = a.UITransformComponent.RectSize, b.UITransformComponent.RectSize
        assert(sizeA.x == sizeB.x and sizeA.y == sizeB.y, "same size")
        log(PREFIX .. "buttons A=[" .. a.TextGUIRendererComponent.Text .. "] B=[" .. b.TextGUIRendererComponent.Text .. "] art=" .. a.SpriteGUIRendererComponent.ImageRUID.DataId .. " same on both")
        -- Press the real button of this run's choice.
        local pressed = CHOICE == "A" and a or b
        pressed:SendEvent(ButtonClickEvent())
        local front = FRONT[CHOICE]
        assert(await(function() return player.CurrentMapName == front end, 150), "joined " .. CHOICE .. " and entered " .. front .. ", stands in " .. player.CurrentMapName)
        assert(not choice.Enable, "the choice screen closed")
        assert(await(function() return ui:Ui("TownHUD").Enable end, 50), "the town HUD is shown in the front town")
        log(PREFIX .. "CLIENT PASS choice=" .. CHOICE .. " town=" .. player.CurrentMapName .. " profile=" .. profile)
    elseif PART == "SERVER" then
        assert(PROFILE ~= "", "PROFILE is the code the client run printed")
        local function readRaw(key)
            local raw, done = "", false
            _FormationStorage:Read(PROFILE, key, function(code, _, value) raw, done = code == 0 and value or "", true end)
            assert(await(function() return done end, 100), "raw read " .. key)
            return raw
        end
        local faction, done = nil, false
        _FactionWar:ReadFaction(PROFILE, function(result) faction, done = result, true end)
        assert(await(function() return done end, 100), "faction read")
        assert(faction == CHOICE, "the saved faction is " .. CHOICE .. ", got " .. tostring(faction))
        assert(readRaw(_FactionWar.FactionKey) == CHOICE, "what is stored is the new id " .. CHOICE .. ", not a colour")
        local name = _FactionWarTownDocument:FactionName(faction)
        assert(name == CHOICE .. " 方", "the faction is shown as " .. name)
        local storage = _DataStorageService:GetUserDataStorage(PROFILE)
        storage:DeleteAndWait(_FactionWar.FactionKey)
        storage:DeleteAndWait(_FactionWar.TownKey)
        assert(readRaw(_FactionWar.FactionKey) == "", "the stored faction is wiped for the next run")
        log(PREFIX .. "SERVER PASS choice=" .. CHOICE .. " stored=" .. CHOICE .. " shown=" .. name .. " profile=" .. PROFILE .. " wiped")
    else
        error("PART is CLIENT or SERVER")
    end
end)
if not ok then log_error(PREFIX .. PART .. " FAIL " .. tostring(reason)) end
