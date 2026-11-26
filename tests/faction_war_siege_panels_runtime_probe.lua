-- #117 / #118 / #123 Maker end-to-end with the REAL local client: the attack panel's numbers and live updates, the team preview and the siege panel.
-- This probe changes the Maker local board and the real test profile's faction, isolated formation key and last town. Use a disposable save only.
-- Edit STEP, and REAL (the real client's ProfileCode) by substitution. Contexts: server_main for SETUP, PUSH, QUEUE, CANCEL, CLEANUP; client for the rest.
-- Order: SETUP, ATTACK_OPEN, PUSH, ATTACK_PUSHED, ATTACK_CLOSE, TEAM_IDLE, QUEUE, SIEGE_SHOWN, PUSH_SIEGE, SIEGE_PUSHED, TEAM_QUEUED, ATTACK_ENGAGED, ATTACK_CLOSE, CANCEL, SIEGE_HIDDEN, SIEGE_ENDED, TEAM_AFTER, CLEANUP.
-- Server steps (server_main): SETUP, PUSH, QUEUE, PUSH_SIEGE, CANCEL, SIEGE_ENDED, CLEANUP; the others run in client. Final lines: [VRF][Siege] <STEP> PASS.
local STEP = "SETUP"
local REAL = "SET_ME"
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
local function text(path) return _FactionWarUI:Ui(path).TextGUIRendererComponent.Text end
local function teamText(path) return _FactionWarTeam:Ui(path).TextGUIRendererComponent.Text end
local highlight = "<color=" .. _FactionWarUI.TownNameHighlightHex .. ">"

local ok, failure = pcall(function()
    assert(Environment:IsMakerPlay(), "Maker Play required")
    if STEP == "SETUP" then
        assert(REAL ~= "SET_ME" and not _RoomService:IsInstanceRoom(), "set REAL and dispatch in server_main")
        local user = real()
        local id = user.PlayerComponent.UserId
        -- The real profile's saved teams are never touched: this Play reads and writes an isolated formation key.
        _FormationService.StorageKey = "Siege117_" .. _UtilLogic:NewGuid()
        local record = _FormationService:GetSession(id)
        _FormationService:Load(record)
        assert(await(function() return record.initialized and not record.pending and record.loadState == "NEW" end), "isolated formation loaded")
        local units = {}
        for index = 1, 3 do units[index] = { monsterId = "monster_tank", x = -3.25 - (index - 1) * 0.75, y = -1.25 + (index % 2) * 0.75 } end
        local slot = record.editSlot
        local key = tostring(slot)
        local revision = record.saved.slots[key].revision
        _FormationService:SaveForUser(id, units, slot, revision, _UtilLogic:NewGuid())
        assert(await(function() return not record.pending and #record.saved.slots[key].units == 3 end), "save confirmed")
        _FormationService:ActivateForUser(id, slot, record.saved.slots[key].revision)
        assert(await(function() return not record.pending and record.saved.activeSlot == slot end), "active slot confirmed")
        local previous, read
        _FactionWar:ReadFaction(REAL, function(value) previous, read = value, true end)
        assert(await(function() return read end) and (previous == "" or previous == "RED"), "the real profile must be unaligned or RED")
        if previous == "" then
            local written
            _FormationStorage:Write(REAL, _FactionWar.FactionKey, "", "RED", function(code) written = code == 0 end)
            assert(await(function() return written end), "faction stored")
        end
        local board = _FactionWarTownDocument:InitialTowns()
        board.gushan.strength = 55
        saveBoard(board)
        -- No guard claim while the probe looks at a queued ticket.
        _FactionWarGuard.WaitSeconds = 600
        assert(_FactionWar:Move(user, "zuoying"), "move dispatched")
        assert(await(function() return real().CurrentMapName == "zuoying" end), "in Zuoying")
        log("[VRF][Siege] SETUP PASS")
    elseif STEP == "PUSH" then
        local board = readBoard()
        board.gushan.strength = 35
        saveBoard(board)
        _FactionWarMap:AnnounceChange()
        log("[VRF][Siege] PUSH PASS board written, change announced; run ATTACK_PUSHED on the client")
    elseif STEP == "QUEUE" then
        local user = real()
        _FactionWarAttack:AttackFor(user.PlayerComponent.UserId, "gushan")
        assert(await(function() return _FactionWarAttack:IsEngaged(user.PlayerComponent.UserId) end, 100), "the real client is queued")
        log("[VRF][Siege] QUEUE PASS")
    elseif STEP == "CANCEL" then
        -- The attack panel of ATTACK_ENGAGED is still open on the client; closing it is the client's own step (ATTACK_CLOSE).
        local id = real().PlayerComponent.UserId
        _MatchFlow:CancelForUser(id)
        assert(await(function() return not _FactionWarAttack:IsEngaged(id) end, 200), "the ticket is cancelled and unlocked")
        log("[VRF][Siege] CANCEL PASS")
    elseif STEP == "PUSH_SIEGE" then
        -- Another match changes both towns of the queued player's card; the siege panel must follow without a request.
        local board = readBoard()
        board.zuoying.strength = 70
        board.gushan.strength = 20
        saveBoard(board)
        _FactionWarMap:AnnounceChange()
        log("[VRF][Siege] PUSH_SIEGE PASS board written (Zuoying 70, Gushan 20), change announced; run SIEGE_PUSHED on the client")
    elseif STEP == "SIEGE_ENDED" then
        -- The card hid on the client, so the server must have dropped the subscription (and the other kinds are not involved).
        assert(await(function() return next(_FactionWarMap._T.siegeViewers) == nil end, 100), "no siege viewer is left")
        log("[VRF][Siege] SIEGE_ENDED PASS siege viewers=0")
    elseif STEP == "CLEANUP" then
        _FactionWarGuard.WaitSeconds = 10
        local code = _DataStorageService:DeleteGlobalDataStorageAndWait(_FactionWarTownDocument.TownStorageName)
        log("[VRF][Siege] CLEANUP PASS town storage delete code=" .. tostring(code))
    elseif STEP == "ATTACK_OPEN" then
        local player = _UserService.LocalPlayer
        assert(player.CurrentMapName == "zuoying", "the client stands in Zuoying")
        _FactionWarAttack:RequestOptions()
        assert(await(function() return _FactionWarUI:Ui("AttackPanel").Enable and text("AttackPanel/Window/Row1/Value") ~= "兵力 —" end, 100), "the panel opened with the server's answer")
        assert(text("AttackPanel/Window/Origin/Name") == highlight .. "左營</color>" and text("AttackPanel/Window/Origin/Value") == "兵力 100 / 100", "departure town and strength")
        assert(text("AttackPanel/Window/Row1/Name") == highlight .. "鼓山</color>" and text("AttackPanel/Window/Row1/Value") == "兵力 55 / 100", "the target's strength from the live board")
        assert(not _FactionWarUI:Ui("AttackPanel/Window/Row1/Capital").Enable, "Gushan is not a capital")
        assert(not _FactionWarUI:Ui("AttackPanel/Window/Row2").Enable, "one target, one card")
        log("[VRF][Siege] ATTACK_OPEN PASS")
    elseif STEP == "ATTACK_PUSHED" then
        assert(await(function() return text("AttackPanel/Window/Row1/Value") == "兵力 35 / 100" end, 100), "the open panel followed the other match without a request")
        local fill = _FactionWarUI:Ui("AttackPanel/Window/Row1/Bar/Fill").UITransformComponent.RectSize.x
        assert(math.abs(fill - _FactionWarUI.AttackBarWidth * 0.35) < 0.01, "and so did the bar")
        log("[VRF][Siege] ATTACK_PUSHED PASS")
    elseif STEP == "ATTACK_CLOSE" then
        _FactionWarUI:CloseAttack()
        assert(not _FactionWarUI:Ui("AttackPanel").Enable, "closed")
        log("[VRF][Siege] ATTACK_CLOSE PASS; the server logs panel close")
    elseif STEP == "TEAM_IDLE" then
        assert(_FactionWarUI:Ui("TeamButton").Enable, "the team button is shown in a town")
        _FactionWarTeam:Close()
        _FactionWarTeam:Open()
        assert(await(function() return teamText("Window/Title") == "出戰隊伍" and _FactionWarTeam:Ui("Window/Field/Unit3").Enable end, 100), "the saved active team is shown")
        assert(teamText("Window/Hint") == "要更換出戰隊伍，請找大廳 NPC", "the hint to the lobby NPC")
        assert(teamText("Window/Field/Unit1/Lv") ~= "" and string.sub(teamText("Window/Field/Unit1/Lv"), 1, 3) == "Lv ", "every unit shows its Lv")
        log("[VRF][Siege] TEAM_IDLE PASS lv=" .. teamText("Window/Field/Unit1/Lv"))
    elseif STEP == "TEAM_QUEUED" then
        -- The client's own levels move on after queueing; the preview must still show the ticket's.
        for _, option in ipairs(_FormationEditSession.Snapshot.options or {}) do option.level = 9 end
        _FactionWarTeam:Close()
        _FactionWarTeam:Open()
        assert(await(function() return teamText("Window/Title") == "本局隊伍" and _FactionWarTeam:Ui("Window/Field/Unit3").Enable end, 100), "the ticket's team is shown")
        assert(teamText("Window/Hint") == "", "no lobby hint on the ticket's team")
        assert(teamText("Window/Field/Unit1/Lv") ~= "Lv 9", "the level is the one frozen at queueing, not the client's current 9: " .. teamText("Window/Field/Unit1/Lv"))
        log("[VRF][Siege] TEAM_QUEUED PASS lv=" .. teamText("Window/Field/Unit1/Lv"))
    elseif STEP == "ATTACK_ENGAGED" then
        _FactionWarTeam:Close()
        _FactionWarAttack:RequestOptions()
        assert(await(function() return _FactionWarUI:Ui("AttackPanel").Enable and text("AttackPanel/Window/Status") ~= "" and string.find(text("AttackPanel/Window/Status"), "目前正在進攻", 1, true) end, 100), "queued: the panel says which town is being attacked")
        assert(text("AttackPanel/Window/Row1/Option") == "進攻中" and not _FactionWarUI:Ui("AttackPanel/Window/Row1/Option").ButtonComponent.Enable, "and offers nothing")
        log("[VRF][Siege] ATTACK_ENGAGED PASS")
    elseif STEP == "SIEGE_SHOWN" then
        -- The real client queued against Gushan from Zuoying: the card replaces the old queue bar, with both towns and the live strengths.
        local card = _FactionWarUI:Ui("SiegePanel")
        assert(await(function() return card.Enable and text("SiegePanel/Origin") == highlight .. "左營</color> 兵力 100" end, 150), "the card shows the departure town and its strength")
        assert(text("SiegePanel/Target") == highlight .. "鼓山</color> 兵力 35", "and the target with the board's strength: " .. text("SiegePanel/Target"))
        assert(text("SiegePanel/Versus") ~= "", "the versus mark")
        assert(string.find(text("SiegePanel/Status"), "配對中", 1, true), "the status: " .. text("SiegePanel/Status"))
        local button = _FactionWarUI:Ui("SiegePanel/Cancel")
        assert(button.Enable and button.ButtonComponent.Enable and button.TextGUIRendererComponent.Text == "取消配對", "the cancel button")
        assert(_FactionWarUI:Ui("QueueBar") == nil, "the old queue bar is gone")
        assert(not string.find(text("SiegePanel/Status") .. text("SiegePanel/Origin") .. text("SiegePanel/Target"), "守衛", 1, true), "no 守衛")
        log("[VRF][Siege] SIEGE_SHOWN PASS origin=" .. text("SiegePanel/Origin") .. " target=" .. text("SiegePanel/Target") .. " status=" .. text("SiegePanel/Status"))
    elseif STEP == "SIEGE_PUSHED" then
        assert(await(function() return text("SiegePanel/Origin") == highlight .. "左營</color> 兵力 70" and text("SiegePanel/Target") == highlight .. "鼓山</color> 兵力 20" end, 100), "the card followed the other match without a request: " .. text("SiegePanel/Origin") .. " / " .. text("SiegePanel/Target"))
        log("[VRF][Siege] SIEGE_PUSHED PASS")
    elseif STEP == "SIEGE_HIDDEN" then
        local card = _FactionWarUI:Ui("SiegePanel")
        assert(await(function() return not card.Enable and not _FactionWarUI._T.siegeShown and _FactionWarUI._T.siegeStrengths == nil end, 100), "after the cancel the card hides and forgets the numbers")
        log("[VRF][Siege] SIEGE_HIDDEN PASS; run SIEGE_ENDED on the server")
    elseif STEP == "TEAM_AFTER" then
        _FactionWarTeam:Close()
        _FactionWarTeam:Open()
        assert(await(function() return teamText("Window/Title") == "出戰隊伍" end, 100), "after the cancel the saved team is shown again")
        log("[VRF][Siege] TEAM_AFTER PASS")
    else
        error("unknown STEP: " .. STEP)
    end
end)
if not ok then log_error("[VRF][Siege] " .. STEP .. " FAIL " .. tostring(failure)) end
