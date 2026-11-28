-- #124 Maker end-to-end with the REAL local client: the NPC press opens the world map in target selection (the server's answer, the dimmed towns, the pick
-- buttons, the confirmation window, Yes / No, QUEUING closing the map for the siege panel) and the read-only view is unchanged.
-- This probe changes the Maker local board and the real test profile's faction, isolated formation key and last town. Use a disposable save only.
-- Edit STEP, REAL (the real client's ProfileCode) and CAPITAL by substitution. Contexts: server_main for SETUP, PUSH, CANCEL, SELECT_ENDED, CLEANUP; client for the rest.
-- Buttons are pressed with ButtonClickEvent sent to the real UI entities (maker_mouse_input cannot click engine UI buttons), so the real bindings run.
-- Order (CAPITAL = false: Zuoying attacks Gushan, 55 left; CAPITAL = true: Gushan, owned by A, attacks the B capital Yancheng):
--   1 SETUP (server_main)  2 SELECT_OPEN  3 PUSH (server_main)  4 SELECT_PUSHED  5 PICK  6 DECLINE  7 CONFIRM  8 SIEGE_SHOWN  9 CANCEL (server_main)
--   10 SIEGE_HIDDEN  11 VIEW  12 SELECT_ENDED (server_main)  13 CLEANUP (server_main)
-- Screenshots for the issue: after SELECT_OPEN (dimmed towns, one pick button), after PICK (the window; with CAPITAL = true the capital note), after SIEGE_SHOWN.
-- Client-only extra, no SETUP needed, from any town: PENDING (opens a synthetic selection and puts the window into the waiting state without sending
-- a request: it says 正在加入配對… with both buttons disabled, take the screenshot) then PENDING_CLOSE (closes the map).
-- Final lines: [VRF][TargetSelect] <STEP> PASS.
local STEP = "SETUP"
local REAL = "SET_ME"
local CAPITAL = false
local ORIGIN, TARGET = "zuoying", "gushan"
if CAPITAL then ORIGIN, TARGET = "gushan", "yancheng" end
-- Strengths the board carries (SETUP) and the one PUSH writes: the target's, or the departure town's when the target is a capital (a capital is always full).
local ORIGIN_START, TARGET_START = CAPITAL and 60 or 100, CAPITAL and 100 or 55
local PUSHED = 35
local PUSHED_TOWN = CAPITAL and ORIGIN or TARGET
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
-- (#132) A town's name in the windows is in the viewer's stance colour once the faction and the town's owner are known, the common highlight until then.
local function name(id)
    local owner
    for _, town in ipairs(ui._T.board or {}) do if town.id == id then owner = town.owner end end
    if _FactionWarTownDocument:IsFaction(ui._T.faction) and _FactionWarTownDocument:IsFaction(owner) then
        return _FactionWarTownDocument:StanceName(id, owner == ui._T.faction and "ally" or "enemy")
    end
    return "<color=" .. _FactionWarUI.TownNameHighlightHex .. ">" .. _FactionWarTownDocument.TownNames[id] .. "</color>"
end
local function strengthText(value) return "兵力 " .. tostring(value) .. " / 100" end

local ok, failure = pcall(function()
    assert(Environment:IsMakerPlay(), "Maker Play required")
    if STEP == "SETUP" then
        assert(REAL ~= "SET_ME" and not _RoomService:IsInstanceRoom(), "set REAL and dispatch in server_main")
        local user = real()
        local id = user.PlayerComponent.UserId
        -- The real profile's saved teams are never touched: this Play reads and writes an isolated formation key.
        _FormationService.StorageKey = "Select124_" .. _UtilLogic:NewGuid()
        local record = _FormationService:GetSession(id)
        _FormationService:Load(record)
        assert(await(function() return record.initialized and not record.pending and record.loadState == "NEW" end), "isolated formation loaded")
        local units = {}
        for index = 1, 3 do units[index] = { monsterId = "monster_tank", x = -3.25 - (index - 1) * 0.75, y = -1.25 + (index % 2) * 0.75 } end
        local slot = record.editSlot
        local key = tostring(slot)
        _FormationService:SaveForUser(id, units, slot, record.saved.slots[key].revision, _UtilLogic:NewGuid())
        assert(await(function() return not record.pending and #record.saved.slots[key].units == 3 end), "save confirmed")
        _FormationService:ActivateForUser(id, slot, record.saved.slots[key].revision)
        assert(await(function() return not record.pending and record.saved.activeSlot == slot end), "active slot confirmed")
        local previous, read
        _FactionWar:ReadFaction(REAL, function(value) previous, read = value, true end)
        assert(await(function() return read end) and (previous == "" or previous == "A"), "the real profile must be unaligned or A")
        if previous == "" then
            local written
            _FormationStorage:Write(REAL, _FactionWar.FactionKey, "", "A", function(code) written = code == 0 end)
            assert(await(function() return written end), "faction stored")
        end
        local board = _FactionWarTownDocument:InitialTowns()
        board.gushan.strength = CAPITAL and ORIGIN_START or TARGET_START
        if CAPITAL then board.gushan.owner = "A" end
        saveBoard(board)
        -- No guard claim while the probe looks at the selection and a queued ticket.
        _FactionWarGuard.WaitSeconds = 600
        assert(_FactionWar:Move(user, ORIGIN), "move dispatched")
        assert(await(function() return real().CurrentMapName == ORIGIN end), "in " .. ORIGIN)
        log("[VRF][TargetSelect] SETUP PASS origin=" .. ORIGIN .. " target=" .. TARGET)
    elseif STEP == "PUSH" then
        local board = readBoard()
        board[PUSHED_TOWN].strength = PUSHED
        saveBoard(board)
        _FactionWarMap:AnnounceChange()
        log("[VRF][TargetSelect] PUSH PASS " .. PUSHED_TOWN .. "=" .. tostring(PUSHED) .. " written, change announced; run SELECT_PUSHED on the client")
    elseif STEP == "CANCEL" then
        -- The map closed on QUEUING; the siege panel shows the queued ticket. Cancelling frees the player.
        local id = real().PlayerComponent.UserId
        _MatchFlow:CancelForUser(id)
        assert(await(function() return not _FactionWarAttack:IsEngaged(id) end, 200), "the ticket is cancelled and unlocked")
        log("[VRF][TargetSelect] CANCEL PASS")
    elseif STEP == "SELECT_ENDED" then
        -- The map closed on the client (QUEUING, then the view's close button) and the siege card hid: no viewer of either kind is left.
        assert(await(function() return next(_FactionWarMap._T.viewers) == nil and next(_FactionWarMap._T.siegeViewers) == nil end, 100), "no map or siege viewer is left")
        log("[VRF][TargetSelect] SELECT_ENDED PASS viewers=0 siege viewers=0")
    elseif STEP == "CLEANUP" then
        _FactionWarGuard.WaitSeconds = 10
        local code = _DataStorageService:DeleteGlobalDataStorageAndWait(_FactionWarTownDocument.TownStorageName)
        log("[VRF][TargetSelect] CLEANUP PASS town storage delete code=" .. tostring(code))
    elseif STEP == "SELECT_OPEN" then
        local player = _UserService.LocalPlayer
        assert(player.CurrentMapName == ORIGIN, "the client stands in " .. ORIGIN)
        assert(not ui:Ui("Overlay").Enable, "the map starts closed")
        -- What the NPC's InteractionEvent handler sends: the real RPC and the real answer.
        _FactionWarAttack:RequestSelect()
        assert(await(function() return ui._T.open and ui._T.mode == "select" and text(row(TARGET) .. "/Value") ~= "—" end, 100), "the server's answer opened the map in selection mode")
        assert(ui:Ui("Overlay").Enable and not ui:Ui("Confirm").Enable, "the map is open and no confirmation yet")
        assert(text("Overlay/Window/Side/Header") == "選擇要進攻的相鄰敵城", "the selection hint")
        assert(text("Overlay/Window/Side/Faction") == "A 方", "the player's faction: " .. text("Overlay/Window/Side/Faction"))
        for _, id in ipairs(_FactionWarTownDocument.TownOrder) do
            assert(ui:Ui(row(id) .. "/Pick").Enable == (id == TARGET), id .. ": only the adjacent enemy town has a pick button")
            assert(ui:Ui(row(id) .. "/Dim").Enable == (id ~= TARGET), id .. ": the others are dimmed")
        end
        assert(text(row(TARGET) .. "/Value") == tostring(TARGET_START) .. "/100", "the target's strength: " .. text(row(TARGET) .. "/Value"))
        assert(text(row(ORIGIN) .. "/Value") == tostring(ORIGIN_START) .. "/100", "the departure town's strength: " .. text(row(ORIGIN) .. "/Value"))
        assert(ui:BlocksInteraction(), "the NPCs ignore the interaction key while the map is open")
        local lit = ui:Ui("Overlay/Window/Map/Content/Districts/" .. TARGET).SpriteGUIRendererComponent.Color.a
        local dim = ui:Ui("Overlay/Window/Map/Content/Districts/" .. ORIGIN).SpriteGUIRendererComponent.Color.a
        assert(math.abs(lit - ui.DistrictAlpha) < 0.01 and math.abs(dim - ui.DimDistrictAlpha) < 0.01, "the dimmed town is drawn dimmer on the map")
        log("[VRF][TargetSelect] SELECT_OPEN PASS target=" .. TARGET .. " value=" .. text(row(TARGET) .. "/Value"))
    elseif STEP == "SELECT_PUSHED" then
        assert(await(function() return text(row(PUSHED_TOWN) .. "/Value") == tostring(PUSHED) .. "/100" end, 100), "the open map followed the other match without a request")
        assert(ui._T.mode == "select" and ui:Ui(row(TARGET) .. "/Pick").Enable, "still in selection mode, the target still pickable")
        log("[VRF][TargetSelect] SELECT_PUSHED PASS " .. PUSHED_TOWN .. "=" .. text(row(PUSHED_TOWN) .. "/Value"))
    elseif STEP == "PICK" then
        click(row(TARGET) .. "/Pick")
        assert(ui._T.selected == TARGET and ui:Ui("Confirm").Enable, "the pick opened the confirmation")
        assert(text("Confirm/Window/Title") == "進攻 " .. name(TARGET) .. "？", "the title: " .. text("Confirm/Window/Title"))
        assert(text("Confirm/Window/Origin") == "出發城 " .. name(ORIGIN) .. "　" .. strengthText(CAPITAL and PUSHED or ORIGIN_START), "the departure line: " .. text("Confirm/Window/Origin"))
        assert(text("Confirm/Window/Target") == "目標城 " .. name(TARGET) .. "　" .. strengthText(CAPITAL and 100 or PUSHED), "the target line, live: " .. text("Confirm/Window/Target"))
        assert(text("Confirm/Window/Note") == (CAPITAL and "打贏不扣主城兵力" or ""), "the capital note only for a capital: " .. text("Confirm/Window/Note"))
        assert(text("Confirm/Window/Yes") == "是" and text("Confirm/Window/No") == "否", "是 and 否")
        assert(ui:Ui("Confirm/Window/Yes").ButtonComponent.Enable and ui:Ui("Confirm/Window/No").ButtonComponent.Enable, "both buttons answer")
        log("[VRF][TargetSelect] PICK PASS title=" .. text("Confirm/Window/Title") .. " target=" .. text("Confirm/Window/Target") .. " note=" .. text("Confirm/Window/Note"))
    elseif STEP == "DECLINE" then
        click("Confirm/Window/No")
        assert(not ui:Ui("Confirm").Enable and ui._T.selected == nil, "No closed the window and cleared the pick")
        assert(ui._T.open and ui:Ui("Overlay").Enable and ui._T.mode == "select", "the map stays open in selection mode")
        assert(ui:Ui(row(TARGET) .. "/Pick").Enable, "the town can be picked again")
        log("[VRF][TargetSelect] DECLINE PASS")
    elseif STEP == "CONFIRM" then
        click(row(TARGET) .. "/Pick")
        assert(ui._T.selected == TARGET, "picked again")
        click("Confirm/Window/Yes")
        -- The click handler marks the window waiting before the server can answer.
        assert(ui._T.pending and text("Confirm/Window/Status") == "正在加入配對…", "the window waits: " .. text("Confirm/Window/Status"))
        assert(await(function() return not ui._T.open end, 100), "QUEUING closed the map")
        assert(not ui:Ui("Overlay").Enable and not ui:Ui("Confirm").Enable and ui._T.selected == nil and ui._T.mode == "view", "the map and the window are closed and the selection is gone")
        log("[VRF][TargetSelect] CONFIRM PASS queued " .. ORIGIN .. " -> " .. TARGET .. "; the server logs the queue and the map close")
    elseif STEP == "SIEGE_SHOWN" then
        local card = _FactionWarUI:Ui("SiegePanel")
        local shown = _FactionWarUI:Ui("SiegePanel/Origin").TextGUIRendererComponent
        assert(await(function() return card.Enable and string.find(shown.Text, "兵力", 1, true) ~= nil end, 150), "the siege panel took over")
        assert(string.find(shown.Text, name(ORIGIN), 1, true) and string.find(_FactionWarUI:Ui("SiegePanel/Target").TextGUIRendererComponent.Text, name(TARGET), 1, true), "both towns")
        assert(string.find(_FactionWarUI:Ui("SiegePanel/Status").TextGUIRendererComponent.Text, "配對中", 1, true), "waiting for an opponent")
        assert(_FactionWarUI:Ui("SiegePanel/Cancel").Enable, "the cancel button is reachable (the map is closed)")
        assert(_FactionWarUI:Ui("AttackPanel") == nil, "the attack panel is gone")
        log("[VRF][TargetSelect] SIEGE_SHOWN PASS origin=" .. shown.Text .. " status=" .. _FactionWarUI:Ui("SiegePanel/Status").TextGUIRendererComponent.Text)
    elseif STEP == "SIEGE_HIDDEN" then
        local card = _FactionWarUI:Ui("SiegePanel")
        assert(await(function() return not card.Enable and not _FactionWarUI._T.siegeShown end, 100), "after the cancel the siege panel hides")
        log("[VRF][TargetSelect] SIEGE_HIDDEN PASS")
    elseif STEP == "VIEW" then
        -- The view (M, or the entry button) is unchanged: read only, no pick buttons, nothing dimmed, one server request.
        ui:HandleKey(KeyDownEvent(KeyboardKey.M))
        assert(ui._T.open and ui._T.mode == "view" and ui:Ui("Overlay").Enable, "M opened the view")
        assert(await(function() return text("Overlay/Window/Side/Faction") ~= "讀取中…" and text(row(TARGET) .. "/Value") ~= "—" end, 100), "the server answered the view")
        assert(text("Overlay/Window/Side/Header") == "城鎮兵力（由北到南）", "the view's header")
        for _, id in ipairs(_FactionWarTownDocument.TownOrder) do
            assert(not ui:Ui(row(id) .. "/Pick").Enable and not ui:Ui(row(id) .. "/Dim").Enable, id .. ": no pick button and no veil in the view")
        end
        ui:Ui(row(TARGET) .. "/Pick"):SendEvent(ButtonClickEvent(ui:Ui(row(TARGET) .. "/Pick")))
        assert(ui._T.selected == nil and not ui:Ui("Confirm").Enable, "a view cannot pick")
        click("Overlay/Window/Close")
        assert(not ui._T.open and not ui:Ui("Overlay").Enable, "the close button closed the view")
        log("[VRF][TargetSelect] VIEW PASS")
    elseif STEP == "PENDING" then
        -- Synthetic, from any town: the waiting window without a server. Yes is never pressed, so no request is sent.
        local player = _UserService.LocalPlayer
        local here = player.CurrentMapName
        assert(_FactionWar:IsTown(here), "the client stands in a town")
        local towns = {}
        for _, id in ipairs(_FactionWarTownDocument.TownOrder) do
            table.insert(towns, { id = id, name = _FactionWarTownDocument.TownNames[id], owner = (id == "nanzih" or id == here) and "A" or "B", strength = 100, capital = _FactionWarTownDocument:IsCapital(id) })
        end
        local target = here == "gushan" and "yancheng" or "gushan"
        ui:ShowSelect(here, "READY", { town = here, strength = 100, owner = "A", faction = "A" }, { { town = target, name = _FactionWarTownDocument.TownNames[target], capital = _FactionWarTownDocument:IsCapital(target), strength = 100, owner = "B" } },
            { towns = towns, links = { { a = "nanzih", b = "zuoying" }, { a = "zuoying", b = "gushan" }, { a = "gushan", b = "yancheng" } } })
        ui:Pick(target)
        ui._T.pending = true
        ui:RenderConfirm()
        assert(text("Confirm/Window/Status") == "正在加入配對…" and not ui:Ui("Confirm/Window/Yes").ButtonComponent.Enable and not ui:Ui("Confirm/Window/No").ButtonComponent.Enable, "the window waits with both buttons disabled")
        log("[VRF][TargetSelect] PENDING PASS window waits; take the screenshot, then run PENDING_CLOSE")
    elseif STEP == "PENDING_CLOSE" then
        ui._T.pending = false
        ui:Close()
        assert(not ui._T.open and not ui:Ui("Confirm").Enable, "the synthetic selection is closed")
        log("[VRF][TargetSelect] PENDING_CLOSE PASS")
    else
        error("unknown STEP: " .. STEP)
    end
end)
if not ok then log_error("[VRF][TargetSelect] " .. STEP .. " FAIL " .. tostring(failure)) end
