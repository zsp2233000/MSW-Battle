-- #128 Maker end-to-end with the REAL local client: the town table changes while the world map is open in target selection or the confirmation window is open.
-- Strength only (the window follows, stays open); a town changed hands but the picked one is a target no more (window closes, one line in the side panel, list
-- redrawn); the server refuses 是 (no stuck "正在加入配對…", line, list asked again); the departure town fell (window closes, nothing can be picked, line).
-- This probe changes the Maker local board and the real test profile's faction and last town. Use a disposable save only. Nothing is queued: the only attack request
-- it sends (step REFUSED) is refused by the server on purpose. It needs NO virtual player: a settlement result takes only town names (the same
-- _FactionWarAttack:Settle the match room calls), and the real player is the one who watches.
-- Edit STEP and REAL (the real client's ProfileCode) by substitution. Contexts: server_main for SETUP, STRENGTH, CAPTURE, STALE, RESTORE, ORIGIN_LOST, CLEANUP; client for the rest.
-- Buttons are pressed with ButtonClickEvent sent to the real UI entities (maker_mouse_input cannot click engine UI buttons), so the real bindings run.
-- Board it builds (the real profile is A, standing in Gushan, which A owns): Nanzih A 100, Zuoying B 55, Gushan A 60, Yancheng B 100. Gushan borders both B towns.
-- Run in a fresh Play (stop, refresh, play) with /ui/WorldMapGroup/Overlay/Window/Side/Notice present (node assets/worldmap/build_notice_ui.cjs, then refresh).
-- Order (wait about 3 s after each server_main step before the client step that follows it; run exactly these 19 steps, in this order):
--   1 SETUP
--   2 SELECT_OPEN
--   3 PICK
--   4 STRENGTH
--   5 STRENGTH_SEEN
--   6 STALE
--   7 REFUSED
--   8 RESTORE
--   9 LIST_BACK
--   10 PICK
--   11 CAPTURE
--   12 TARGET_GONE
--   13 RESTORE
--   14 LIST_BACK
--   15 PICK
--   16 ORIGIN_LOST
--   17 ORIGIN_SEEN
--   18 CLOSE
--   19 CLEANUP
-- Screenshots for the issue (docs/evidence/issue128/): after PICK (1: the window, Zuoying 55), after STRENGTH_SEEN (2: the same window, Zuoying 35, nothing else changed),
-- after REFUSED (3: window closed, the line "左營 已不能進攻", no waiting window, Yancheng still pickable), after TARGET_GONE (4: window closed, the line "左營 已不能進攻",
-- Zuoying dimmed with its new owner, Yancheng still pickable), after ORIGIN_SEEN (5: window closed, the line "這座城已不屬於你的陣營", every row dimmed, the map still open).
-- Final lines: [VRF][TargetInvalidate] <STEP> PASS.
local STEP = "SETUP"
local REAL = "SET_ME"
local ORIGIN, TARGET, OTHER = "gushan", "zuoying", "yancheng"
local TARGET_START, ORIGIN_START = 55, 60
local function await(predicate, count)
    for _ = 1, count or 300 do if predicate() then return true end wait(0.1) end
    return false
end
local function readBoard()
    local value, done
    _FactionWarTownDocument:Read(function(towns) value, done = towns, true end)
    assert(await(function() return done end), "read town board")
    return assert(value, "readable board")
end
local function saveBoard(board)
    local written
    _FactionWarTownDocument:WriteTowns(board, function(ok) written = ok end)
    assert(await(function() return written end), "write Maker fixture board")
end
local function layout()
    -- The fixture board; every server step that needs it starts from here.
    local board = _FactionWarTownDocument:InitialTowns()
    board[TARGET].owner = "B" -- the initial world has Zuoying as A's
    board[TARGET].strength = TARGET_START
    board[ORIGIN].owner = "A"
    board[ORIGIN].strength = ORIGIN_START
    return board
end
local function settle(home, away)
    -- A real human result, the call the match room makes; it announces the change to every open map.
    local status, outcome, done
    _FactionWarAttack:Settle("c128-" .. _UtilLogic:NewGuid(), home, away, "WIN", "HUMAN", function(s, _, o) status, outcome, done = s, o, true end)
    assert(await(function() return done end, 300), "settlement completed")
    return status, outcome
end
local function real()
    for _, user in ipairs(_UserService.UserEntities.Values) do
        if isvalid(user) and isvalid(user.PlayerComponent) and user.PlayerComponent.ProfileCode == REAL then return user end
    end
    error("the real client is connected as " .. REAL)
end
local ui = _FactionWarMapUI
local function text(path) return ui:Ui(path).TextGUIRendererComponent.Text end
local function click(path)
    local entity = ui:Ui(path)
    assert(isvalid(entity) and entity.Enable, path .. " is shown")
    entity:SendEvent(ButtonClickEvent(entity))
end
local function row(id) return "Overlay/Window/Side/Rows/" .. id end
local highlight = "<color=" .. _FactionWarUI.TownNameHighlightHex .. ">"
local function name(id) return highlight .. _FactionWarTownDocument.TownNames[id] .. "</color>" end
local function strengthText(value) return "兵力 " .. tostring(value) .. " / 100" end
local function noticeShown()
    local node = ui:Ui("Overlay/Window/Side/Notice")
    assert(isvalid(node), "the side panel has its Notice line (node assets/worldmap/build_notice_ui.cjs, then refresh)")
    return node.Enable and node.TextGUIRendererComponent.Text or nil
end
local function onlyPickable(ids)
    local wanted = {}
    for _, id in ipairs(ids) do wanted[id] = true end
    for _, id in ipairs(_FactionWarTownDocument.TownOrder) do
        assert(ui:Ui(row(id) .. "/Pick").Enable == (wanted[id] == true), id .. ": pick button " .. tostring(wanted[id] == true))
        assert(ui:Ui(row(id) .. "/Dim").Enable == (wanted[id] ~= true), id .. ": veil " .. tostring(wanted[id] ~= true))
    end
end

local ok, failure = pcall(function()
    assert(Environment:IsMakerPlay(), "Maker Play required")
    if STEP == "SETUP" then
        assert(REAL ~= "SET_ME" and not _RoomService:IsInstanceRoom(), "set REAL and dispatch in server_main")
        local user = real()
        local id = user.PlayerComponent.UserId
        assert(not _FactionWarAttack:IsEngaged(id), "the real player is not queued")
        local previous, read
        _FactionWar:ReadFaction(REAL, function(value) previous, read = value, true end)
        assert(await(function() return read end) and (previous == "" or previous == "A"), "the real profile must be unaligned or A")
        if previous == "" then
            local written
            _FormationStorage:Write(REAL, _FactionWar.FactionKey, "", "A", function(code) written = code == 0 end)
            assert(await(function() return written end), "faction stored")
        end
        saveBoard(layout())
        -- No guard claim while the probe looks at the map.
        _FactionWarGuard.WaitSeconds = 600
        assert(_FactionWar:Move(user, ORIGIN), "move dispatched")
        assert(await(function() return real().CurrentMapName == ORIGIN end), "in " .. ORIGIN)
        log("[VRF][TargetInvalidate] SETUP PASS origin=" .. ORIGIN .. " targets=" .. TARGET .. "," .. OTHER)
    elseif STEP == "STRENGTH" then
        -- Gushan beats Zuoying: 55 -> 35, no change of owner, so no new list is needed.
        local status, outcome = settle(ORIGIN, TARGET)
        assert(status == "SAVED" and outcome.strength == TARGET_START - 20 and not outcome.flipped, "a win takes 20: " .. tostring(status) .. "/" .. tostring(outcome.strength))
        log("[VRF][TargetInvalidate] STRENGTH PASS " .. TARGET .. " 55 -> " .. tostring(outcome.strength) .. "; run STRENGTH_SEEN on the client")
    elseif STEP == "CAPTURE" then
        -- Zuoying is B's again (RESTORE) with 55; bring it to 20 silently (nothing is announced), then a real win takes it: it flips to A and refills.
        local board = readBoard()
        board[TARGET].strength = 20
        saveBoard(board)
        local status, outcome = settle(ORIGIN, TARGET)
        assert(status == "SAVED" and outcome.flipped and outcome.owner == "A" and outcome.strength == 100, "Zuoying flipped to A: " .. tostring(status))
        log("[VRF][TargetInvalidate] CAPTURE PASS " .. TARGET .. " is A's, announced; run TARGET_GONE on the client")
    elseif STEP == "STALE" then
        -- Zuoying turns A's WITHOUT an announcement: the open map still shows it as the picked target, the server no longer lists it.
        -- (Not Yancheng: a board whose B capital is A's is unreadable by design, so the server would answer UNAVAILABLE, not INVALID.)
        local board = readBoard()
        board[TARGET].owner = "A"
        board[TARGET].strength = 100
        saveBoard(board)
        log("[VRF][TargetInvalidate] STALE PASS " .. TARGET .. " is A's in the table, nothing announced; run REFUSED on the client")
    elseif STEP == "RESTORE" then
        -- Back to the fixture board; the announcement makes the open map ask for its list again.
        saveBoard(layout())
        _FactionWarMap:AnnounceChange()
        log("[VRF][TargetInvalidate] RESTORE PASS fixture board written and announced; run LIST_BACK on the client")
    elseif STEP == "ORIGIN_LOST" then
        -- Gushan is B's in the table. Written (not settled) so the order is the same every run: the real capture also sweeps the player to the capital
        -- at once, and whether that or the board push reaches the client first is not deterministic. The server answers the relist NOT_OWNED, then
        -- the landing check sends the player to the capital.
        local board = readBoard()
        board[ORIGIN].owner = "B"
        saveBoard(board)
        _FactionWarMap:AnnounceChange()
        log("[VRF][TargetInvalidate] ORIGIN_LOST PASS " .. ORIGIN .. " is B's, announced; run ORIGIN_SEEN on the client")
    elseif STEP == "CLEANUP" then
        assert(await(function() return next(_FactionWarMap._T.viewers) == nil end, 100), "no map viewer is left")
        _FactionWarGuard.WaitSeconds = 10
        local code = _DataStorageService:DeleteGlobalDataStorageAndWait(_FactionWarTownDocument.TownStorageName)
        log("[VRF][TargetInvalidate] CLEANUP PASS town storage delete code=" .. tostring(code))
    elseif STEP == "SELECT_OPEN" then
        local player = _UserService.LocalPlayer
        assert(player.CurrentMapName == ORIGIN, "the client stands in " .. ORIGIN)
        assert(not ui:Ui("Overlay").Enable, "the map starts closed")
        -- What the NPC's InteractionEvent handler sends: the real RPC and the real answer.
        _FactionWarAttack:RequestSelect()
        assert(await(function() return ui._T.open and ui._T.mode == "select" and text(row(TARGET) .. "/Value") ~= "—" end, 100), "the server's answer opened the map in selection mode")
        onlyPickable({ TARGET, OTHER })
        assert(noticeShown() == nil, "no line yet")
        assert(text(row(TARGET) .. "/Value") == tostring(TARGET_START) .. "/100", "Zuoying's strength: " .. text(row(TARGET) .. "/Value"))
        log("[VRF][TargetInvalidate] SELECT_OPEN PASS pickable=" .. TARGET .. "," .. OTHER)
    elseif STEP == "PICK" then
        local id = TARGET
        click(row(id) .. "/Pick")
        assert(ui._T.selected == id and ui:Ui("Confirm").Enable, "the pick opened the confirmation")
        assert(noticeShown() == nil, "a new pick shows no line")
        assert(text("Confirm/Window/Title") == "進攻 " .. name(id) .. "？", "the title: " .. text("Confirm/Window/Title"))
        log("[VRF][TargetInvalidate] " .. STEP .. " PASS target=" .. text("Confirm/Window/Target") .. " origin=" .. text("Confirm/Window/Origin"))
    elseif STEP == "STRENGTH_SEEN" then
        assert(await(function() return text("Confirm/Window/Target") == "目標城 " .. name(TARGET) .. "　" .. strengthText(TARGET_START - 20) end, 100), "the open window follows the other match: " .. text("Confirm/Window/Target"))
        assert(ui:Ui("Confirm").Enable and ui._T.selected == TARGET, "the window stayed open on the same pick")
        assert(text("Confirm/Window/Origin") == "出發城 " .. name(ORIGIN) .. "　" .. strengthText(ORIGIN_START), "the departure line is unchanged: " .. text("Confirm/Window/Origin"))
        assert(text(row(TARGET) .. "/Value") == tostring(TARGET_START - 20) .. "/100", "the list follows")
        assert(not ui._T.relisting and noticeShown() == nil, "no new list was asked for and no line is shown")
        onlyPickable({ TARGET, OTHER })
        log("[VRF][TargetInvalidate] STRENGTH_SEEN PASS " .. text("Confirm/Window/Target"))
    elseif STEP == "TARGET_GONE" then
        local line = name(TARGET) .. " 已不能進攻"
        assert(await(function() return noticeShown() == line end, 100), "the side panel says Zuoying can no longer be attacked: " .. tostring(noticeShown()))
        assert(not ui:Ui("Confirm").Enable and ui._T.selected == nil, "the confirmation window closed")
        assert(ui._T.open and ui:Ui("Overlay").Enable and ui._T.mode == "select" and not ui:Ui("Message").Enable, "the map stays open in selection mode, with no message window")
        assert(await(function() return not ui._T.relisting end, 50), "the relist is answered")
        onlyPickable({ OTHER })
        assert(text(row(TARGET) .. "/Owner") == "A 方" and text(row(TARGET) .. "/Value") == "100/100", "Zuoying's row shows the new owner and the refilled strength")
        log("[VRF][TargetInvalidate] TARGET_GONE PASS line=" .. noticeShown())
    elseif STEP == "REFUSED" then
        -- The list on screen is stale (Zuoying is A's in the table, nothing announced): the server must refuse the attack.
        assert(ui._T.selected == TARGET and ui:Ui("Confirm").Enable, "Zuoying is still picked")
        click("Confirm/Window/Yes")
        assert(ui._T.pending and text("Confirm/Window/Status") == "正在加入配對…", "the window waits: " .. text("Confirm/Window/Status"))
        local line = name(TARGET) .. " 已不能進攻"
        assert(await(function() return noticeShown() == line end, 100), "the refusal closed the window and named the town: " .. tostring(noticeShown()))
        assert(not ui._T.pending and not ui:Ui("Confirm").Enable and ui._T.selected == nil, "nothing waits any more")
        assert(await(function() return not ui._T.relisting end, 100), "the list was asked for again and answered")
        assert(ui._T.open and not ui:Ui("Message").Enable, "the map stays open, no message window")
        assert(noticeShown() == line, "the line stays while Zuoying is not a target")
        onlyPickable({ OTHER })
        assert(ui._T.mapName == ORIGIN and not _FactionWarAttack:IsEngaged(real().PlayerComponent.UserId), "nothing was queued and the player did not move")
        log("[VRF][TargetInvalidate] REFUSED PASS line=" .. line .. "; the server logs queue refused ... reason=INVALID")
    elseif STEP == "LIST_BACK" then
        assert(await(function() return noticeShown() == nil and ui:Ui(row(TARGET) .. "/Pick").Enable end, 100), "the restored board lists Zuoying again and the line is gone: " .. tostring(noticeShown()))
        onlyPickable({ TARGET, OTHER })
        assert(text(row(TARGET) .. "/Value") == tostring(TARGET_START) .. "/100", "Zuoying is B's again with 55")
        log("[VRF][TargetInvalidate] LIST_BACK PASS pickable=" .. TARGET .. "," .. OTHER)
    elseif STEP == "ORIGIN_SEEN" then
        local line = "這座城已不屬於你的陣營"
        assert(await(function() return noticeShown() == line end, 100), "the side panel says the departure town is no longer the player's faction's: " .. tostring(noticeShown()))
        assert(not ui:Ui("Confirm").Enable and ui._T.selected == nil and not ui._T.pending, "the confirmation window closed")
        assert(ui._T.open and ui:Ui("Overlay").Enable and ui._T.mode == "select" and not ui:Ui("Message").Enable, "the map stays open, no message window")
        onlyPickable({})
        log("[VRF][TargetInvalidate] ORIGIN_SEEN PASS line=" .. line .. "; the server then sends the player to the capital (landing CHECK)")
    elseif STEP == "CLOSE" then
        click("Overlay/Window/Close")
        assert(not ui._T.open and not ui:Ui("Overlay").Enable and not ui:Ui("Confirm").Enable, "the map is closed")
        assert(noticeShown() == nil and not ui:BlocksInteraction(), "the line is gone and the NPCs answer again")
        log("[VRF][TargetInvalidate] CLOSE PASS")
    else
        error("unknown STEP: " .. STEP)
    end
end)
if not ok then log_error("[VRF][TargetInvalidate] " .. STEP .. " FAIL " .. tostring(failure)) end
