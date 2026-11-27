-- #127 Maker end-to-end with the REAL local client: an NPC press that cannot attack opens a message window (never the map), and neither town NPC
-- reacts to the interaction key while the map, the confirmation window or a message window is open.
-- The interaction key is pressed with maker_keyboard_input (['e'], the NPC's InteractionComponent.ActionKey), so the real InteractionEvent, the NPC handlers
-- and the server answer run. Buttons are pressed with ButtonClickEvent (maker_mouse_input cannot click engine UI buttons).
-- This probe uses the fixture of tests/target_select_client_runtime_probe.lua (#124): run ITS steps SETUP, PICK, CONFIRM, CANCEL and CLEANUP unchanged,
-- with the same REAL; the board it leaves is Zuoying (A) next to Gushan (B, 55), the real profile is A and stands in Zuoying. Disposable save only.
-- Edit STEP (and REAL for the server steps) by substitution. Contexts: server_main for BOARD_NO_TARGETS and BOARD_RESTORE; client for the rest.
-- Order (E = one maker_keyboard_input tap of 'e' after the step before it; wait about 2 s after each E for the answer):
--   #124 SETUP (server_main)
--   1 STAND (NPC = "WAR") [E]  2 MAP_BY_KEY [E]  3 KEY_IGNORED_WAR  4 STAND (NPC = "LOBBY") [E]  5 KEY_IGNORED_LOBBY
--   #124 PICK, #124 CONFIRM (the pick and 是: queues Zuoying -> Gushan, the map closes)
--   6 STAND (NPC = "WAR") [E]  7 MESSAGE_ENGAGED (screenshot) [E]  8 MESSAGE_KEY_IGNORED  9 DISMISS  #124 CANCEL (server_main)
--   10 BOARD_NO_TARGETS (server_main: Gushan becomes A's)  11 STAND (NPC = "WAR") [E]  12 MESSAGE_NO_TARGETS (screenshot)  13 DISMISS  14 BOARD_RESTORE (server_main)
--   #124 CLEANUP (server_main)
-- Final lines: [VRF][TargetMessage] <STEP> PASS.
local STEP = "STAND"
local NPC = "WAR"
local REAL = "SET_ME"
local function await(predicate, count)
    for _ = 1, count or 100 do if predicate() then return true end wait(0.1) end
    return false
end
local ui = _FactionWarMapUI
local function text(path) return ui:Ui(path).TextGUIRendererComponent.Text end
local function readBoard()
    local value, done
    _FactionWarTownDocument:Read(function(towns) value, done = towns, true end)
    assert(await(function() return done end, 300), "read town board")
    return assert(value, "readable board")
end
local function saveBoard(board)
    local written
    _FactionWarTownDocument:WriteTowns(board, function(ok) written = ok end)
    assert(await(function() return written end, 300), "write Maker fixture board")
end
local highlight = "<color=" .. _FactionWarUI.TownNameHighlightHex .. ">"
local function name(id) return highlight .. _FactionWarTownDocument.TownNames[id] .. "</color>" end
local function npcEntity()
    local typeName = NPC == "LOBBY" and "script.FactionWarLobbyNpc" or "script.FactionWarNpc"
    local list = _UserService.LocalPlayer.CurrentMap:GetChildComponentsByTypeName(typeName, true)
    assert(#list >= 1, "the town has a " .. typeName)
    return list[1].Entity
end
local function onlyMessageControl()
    local ok = ui:Ui("Message/Window/Ok")
    assert(isvalid(ok) and ok.Enable and ok.TextGUIRendererComponent.Text == "確定", "the message window has its 確定 button")
    assert(ui:Ui("Message/Window/Yes") == nil and ui:Ui("Message/Window/No") == nil, "and no other button")
end

local ok, failure = pcall(function()
    assert(Environment:IsMakerPlay(), "Maker Play required")
    if STEP == "BOARD_NO_TARGETS" then
        assert(REAL ~= "SET_ME" and not _RoomService:IsInstanceRoom(), "dispatch in server_main")
        local board = readBoard()
        board.gushan.owner = "A"
        saveBoard(board)
        log("[VRF][TargetMessage] BOARD_NO_TARGETS PASS Gushan is A's: Zuoying has no adjacent enemy town")
    elseif STEP == "BOARD_RESTORE" then
        local board = readBoard()
        board.gushan.owner = "B"
        saveBoard(board)
        log("[VRF][TargetMessage] BOARD_RESTORE PASS Gushan is B's again")
    elseif STEP == "STAND" then
        -- Beside the NPC, so that the next E tap is a real interaction.
        local player = _UserService.LocalPlayer
        assert(_FactionWar:IsTown(player.CurrentMapName), "the client stands in a town")
        local npc = npcEntity()
        assert(isvalid(npc.InteractionComponent) and npc.InteractionComponent.ActionKey == KeyboardKey.E, "the NPC answers the E key")
        local at = npc.TransformComponent.WorldPosition
        player.MovementComponent:SetWorldPosition(Vector2(at.x, at.y))
        assert(await(function()
            local here = player.TransformComponent.WorldPosition
            return math.abs(here.x - at.x) < 0.6 and math.abs(here.y - at.y) < 0.6
        end, 30), "standing beside the " .. NPC .. " NPC")
        log("[VRF][TargetMessage] STAND PASS beside the " .. NPC .. " NPC at " .. tostring(at) .. "; tap E now (maker_keyboard_input ['e'])")
    elseif STEP == "MAP_BY_KEY" then
        assert(await(function() return ui._T.open and ui._T.mode == "select" and not ui._T.asking end, 100), "the real key press opened the map in selection mode")
        assert(ui:Ui("Overlay").Enable and not ui:Ui("Confirm").Enable and not ui:Ui("Message").Enable, "the map, no confirmation, no message")
        assert(ui:BlocksInteraction(), "the NPCs now ignore the key")
        log("[VRF][TargetMessage] MAP_BY_KEY PASS; tap E again with the map open, then run KEY_IGNORED_WAR")
    elseif STEP == "KEY_IGNORED_WAR" then
        assert(not ui._T.asking and ui._T.open and ui._T.mode == "select", "the second press asked for nothing: no wait, the same map")
        assert(not ui:Ui("Message").Enable and ui._T.message == nil, "and opened no window")
        log("[VRF][TargetMessage] KEY_IGNORED_WAR PASS")
    elseif STEP == "KEY_IGNORED_LOBBY" then
        -- Tapped beside the lobby NPC with the map still open.
        assert(not _FormationLobby:IsTownPanelOpen() and not _FormationLobby.root.Enable, "the lobby panel stayed closed")
        assert(ui._T.open and not ui._T.asking and ui._T.message == nil, "the map is unchanged and nothing was asked")
        log("[VRF][TargetMessage] KEY_IGNORED_LOBBY PASS")
    elseif STEP == "MESSAGE_ENGAGED" then
        assert(await(function() return ui._T.message ~= nil end, 100), "the press was answered with a message")
        assert(not ui._T.open and not ui:Ui("Overlay").Enable and not ui:Ui("Confirm").Enable, "no map")
        assert(ui:Ui("Message").Enable, "the message window is shown")
        assert(text("Message/Window/Text") == "目前正在進攻 " .. name("gushan") .. "，要改變目標請先取消配對（畫面上方的攻城面板可以取消）", "the text: " .. text("Message/Window/Text"))
        onlyMessageControl()
        assert(ui:BlocksInteraction(), "the NPCs ignore the key behind the message")
        log("[VRF][TargetMessage] MESSAGE_ENGAGED PASS " .. text("Message/Window/Text") .. "; take the screenshot, tap E again, run MESSAGE_KEY_IGNORED")
    elseif STEP == "MESSAGE_KEY_IGNORED" then
        assert(ui._T.message ~= nil and not ui._T.asking and not ui._T.open, "the second press asked for nothing and opened no map")
        assert(not _FormationLobby:IsTownPanelOpen(), "nor the lobby panel")
        log("[VRF][TargetMessage] MESSAGE_KEY_IGNORED PASS one window, no second request")
    elseif STEP == "MESSAGE_NO_TARGETS" then
        assert(await(function() return ui._T.message ~= nil end, 100), "the press was answered with a message")
        assert(not ui._T.open and not ui:Ui("Overlay").Enable, "no map")
        assert(text("Message/Window/Text") == "目前沒有可進攻的相鄰敵城", "the text: " .. text("Message/Window/Text"))
        onlyMessageControl()
        log("[VRF][TargetMessage] MESSAGE_NO_TARGETS PASS; take the screenshot")
    elseif STEP == "DISMISS" then
        local button = ui:Ui("Message/Window/Ok")
        assert(isvalid(button) and button.Enable, "the 確定 button is shown")
        button:SendEvent(ButtonClickEvent(button))
        assert(not ui:Ui("Message").Enable and ui._T.message == nil and not ui:BlocksInteraction(), "確定 closed the window and the NPCs answer again")
        log("[VRF][TargetMessage] DISMISS PASS")
    else
        error("unknown STEP: " .. STEP)
    end
end)
if not ok then log_error("[VRF][TargetMessage] " .. STEP .. " FAIL " .. tostring(failure)) end
