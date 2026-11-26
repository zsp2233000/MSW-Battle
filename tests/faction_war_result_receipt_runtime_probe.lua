-- #115 / #119 Maker only. Runbook: tests/README.md, War result receipts (#115) and the return button (#119).
-- This probe changes the Maker local board and the two disposable accounts. Never use production or valuable saves.
local STEP = "SETUP" -- SETUP, QUEUE, ARM, CLIENT, RECONNECT, RECHECK, BOARD, BOARD_CLIENT, LOBBY_CLIENT, RETURN, CLEANUP
local KIND = "HUMAN" -- HUMAN or GUARD; one fresh Play per case
local RED_PROFILE = "SET_ME" -- the real Maker client must play RED, so its screen can be inspected
local BLUE_PROFILE = "wp2624" -- virtual BLUE only in HUMAN
local MATCH_KEY = "SET_ME" -- only BOARD (from the room/transfer logs)
local function await(predicate, count)
    for _ = 1, count or 300 do if predicate() then return true end wait(0.1) end
    return false
end
local function users()
    local found = {}
    for _, user in ipairs(_UserService.UserEntities.Values) do
        if isvalid(user) and isvalid(user.PlayerComponent) then found[user.PlayerComponent.ProfileCode] = user end
    end
    return found
end
local function userId(user) return user.PlayerComponent.UserId end
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
local function prepare(user, faction, units)
    assert(isvalid(user), "fixture account connected")
    local id = userId(user)
    local record = _FormationService:GetSession(id)
    assert(record ~= nil, "formation session loaded")
    _FormationService:Load(record)
    assert(await(function() return record.initialized and not record.pending and record.loadState == "NEW" end), "isolated formation loaded")
    local slot = record.editSlot
    local key = tostring(slot)
    local revision = record.saved.slots[key].revision
    _FormationService:SaveForUser(id, units, slot, revision, _UtilLogic:NewGuid())
    assert(await(function() return not record.pending and record.saved.slots[key].revision ~= revision
        and #record.saved.slots[key].units == #units end), "save confirmed")
    _FormationService:ActivateForUser(id, slot, record.saved.slots[key].revision)
    assert(await(function() return not record.pending and record.saved.activeSlot == slot end), "active slot confirmed")
    local profile = user.PlayerComponent.ProfileCode
    local previous, read
    _FactionWar:ReadFaction(profile, function(value) previous, read = value, true end)
    assert(await(function() return read end) and (previous == "" or previous == faction), "fixture account must be unaligned or in the chosen faction")
    if previous == "" then
        local written
        _FormationStorage:Write(profile, _FactionWar.FactionKey, "", faction, function(code) written = code == 0 end)
        assert(await(function() return written end), "faction stored")
    end
end
local function matchPhase()
    local map = _EntityService:GetEntityByPath("/maps/matchprobe")
    assert(isvalid(map) and _RoomService:IsInstanceRoom(), "dispatch in server_instance_<matchKey>")
    return map:GetComponent("script.BattleSession")
end
local function clientMatch()
    local player = _UserService.LocalPlayer
    assert(isvalid(player) and player.CurrentMapName == "matchprobe", "dispatch in the admitted real client")
    local battle = player.CurrentMap:GetComponent("script.BattleSession")
    local coordinator = player.CurrentMap:GetFirstChildComponentByTypeName("script.MatchedBattle", true)
    assert(isvalid(battle) and isvalid(coordinator), "battle and receipt controller present")
    return player, battle, coordinator, _BattleUIController
end
local function checkReturnButton(destination, lost)
    -- #119 (ADR 0016): the button says where it goes, the line above it says so first when the departure town fell, and the screen shows exactly that.
    local highlight = "<color=" .. _FactionWarUI.TownNameHighlightHex .. ">"
    local view = _MatchFlowInput:View()
    local name = _FactionWarTownDocument.TownNames[destination]
    assert(view.label == "返回 " .. highlight .. name .. "</color>" and view.action == "RETURN" and view.enabled, "return label names " .. name .. ": " .. tostring(view.label))
    assert(await(function()
        local action, status = _MatchFlowInput.action, _MatchFlowInput.status
        return isvalid(action) and isvalid(status) and action.TextGUIRendererComponent.Text == view.label and status.TextGUIRendererComponent.Text == view.text
    end, 100), "the visible return button and the line above it show the same words")
    if lost then
        assert(view.text == highlight .. "左營</color>已失守", "the fall notice above the button: " .. tostring(view.text))
    else
        assert(not string.find(view.text, "已失守", 1, true), "no fall notice while the departure town stands: " .. tostring(view.text))
    end
    log("[VRF][Return119] button label=" .. view.label .. " notice=" .. view.text)
end
local function inspectSaved(player, battle, coordinator, ui, destination)
    assert(await(function()
        local receipt = coordinator.WarResultReceipt
        return receipt.status == "SAVED" and receipt.destination == destination and ui.warResult.EnabledInHierarchy
    end), "committed result and destination preview visible")
    local receipt = coordinator.WarResultReceipt
    local before, after = KIND == "HUMAN" and 20 or 25, KIND == "HUMAN" and 100 or 15
    assert(ui.OwnResult == "WIN", "the fixture must produce a red win")
    assert(receipt.matchId == battle.MatchKey and receipt.profile == player.PlayerComponent.ProfileCode, "only this profile's match receipt")
    assert(receipt.origin == "zuoying" and receipt.target == "gushan", "viewer orientation")
    assert(receipt.originBefore == 100 and receipt.originAfter == 100 and receipt.targetBefore == before and receipt.targetAfter == after, "historical strength snapshot")
    assert(receipt.originLost == (destination == "nanzih"), "origin ownership preview")
    local highlight = "<color=" .. _FactionWarUI.TownNameHighlightHex .. ">"
    local function label(node) return node.TextGUIRendererComponent.Text end
    assert(ui.warOrigin.EnabledInHierarchy and ui.warTarget.EnabledInHierarchy, "strength rows visible")
    -- One merged panel: the HUD steps aside and the window grew upward by the section, bottom edge kept.
    local frame = ui.resultWindow.UITransformComponent
    assert(not ui.hud.Enable, "the HUD steps aside for the merged result panel")
    assert(frame.RectSize.y == 360 + ui.WarExtraHeight and frame.anchoredPosition.y == 90 + ui.WarExtraHeight / 2, "window grown by the war section")
    assert(label(ui.warOrigin) == highlight .. "左營</color>　兵力 100 → 100", "origin row")
    assert(label(ui.warTarget) == highlight .. "鼓山</color>　兵力 " .. before .. " → " .. after, "target row")
    local conclusion = KIND == "HUMAN" and ("奪城：" .. highlight .. "鼓山</color> 改為 紅方") or "未易主"
    assert(label(ui.warConclusion) == conclusion, "ownership conclusion")
    checkReturnButton(destination, destination == "nanzih")
    assert(await(function() return battle.ExperienceResult.status == "SAVED" end), "experience still settles")
    assert(await(function() return label(ui.result:GetChildByName("Window"):GetChildByName("Caption")) == "本局怪物經驗" end), "experience UI unchanged")
    log("[VRF][Result115] " .. STEP .. " PASS kind=" .. KIND .. " match=" .. receipt.matchId .. " revision=" .. tostring(receipt.revision) .. " destination=" .. destination)
end

local ok, failure = pcall(function()
    assert(Environment:IsMakerPlay(), "Maker Play required")
    if STEP == "LOBBY_CLIENT" then
        local _, battle, coordinator, ui = clientMatch()
        assert(await(function() return ui.OwnResult ~= "" and ui.result.EnabledInHierarchy end, 3000), "lobby battle result visible")
        assert(coordinator.WarResultReceipt.matchId == nil and not ui.warResult.EnabledInHierarchy, "lobby has no war receipt or war block")
        assert(not ui.hud.Enable and ui.resultWindow.UITransformComponent.RectSize.y == 360 and ui.resultWindow.UITransformComponent.anchoredPosition.y == 90, "the lobby result keeps the plain window and the HUD steps aside")
        assert(battle.RequireMatchedFormations, "this is a lobby match, not the POC")
        log("[VRF][Result115] LOBBY_CLIENT PASS")
    elseif STEP == "CLIENT" or STEP == "RECHECK" then
        local player, battle, coordinator, ui = clientMatch()
        if STEP == "CLIENT" then
            assert(await(function()
                return coordinator.WarResultReceipt.status == "PENDING" and ui.warResult.EnabledInHierarchy
                    and ui.warConclusion.TextGUIRendererComponent.Text == "戰果結算中…"
            end, 3000), "visible pending; ARM before the fight finishes and dispatch CLIENT promptly")
            assert(not ui.warOrigin.EnabledInHierarchy and not ui.warTarget.EnabledInHierarchy and ui.OwnResult ~= "", "pending doesn't block WIN/LOSE or show proposed values")
            -- No strength rows yet: the conclusion takes the first row's place and the window is shorter than the full war window.
            local pending = ui.resultWindow.UITransformComponent.RectSize.y
            assert(pending > 360 and pending < 360 + ui.WarExtraHeight and not ui.hud.Enable
                and ui.warConclusion.UITransformComponent.anchoredPosition.y == ui.warOrigin.UITransformComponent.anchoredPosition.y, "pending uses the short war window")
            -- Until the receipt knows, the departure town is what the button promises.
            local view = _MatchFlowInput:View()
            assert(view.label == "返回 <color=" .. _FactionWarUI.TownNameHighlightHex .. ">左營</color>", "pending return button names the departure town: " .. tostring(view.label))
            log("[VRF][Result115] PENDING PASS kind=" .. KIND)
        end
        inspectSaved(player, battle, coordinator, ui, "zuoying")
    elseif STEP == "BOARD_CLIENT" then
        local player, battle, coordinator, ui = clientMatch()
        inspectSaved(player, battle, coordinator, ui, "nanzih")
    elseif STEP == "SETUP" then
        assert(not _RoomService:IsInstanceRoom() and RED_PROFILE ~= "SET_ME", "set RED_PROFILE and dispatch in server_main")
        local found = users()
        _FormationService.StorageKey = "Result115_" .. _UtilLogic:NewGuid()
        local roster = {}
        for index = 1, (KIND == "HUMAN" and 3 or 4) do
            local monster = KIND == "HUMAN" and "monster_tank" or (index <= 2 and "monster_dark_centaur" or "monster_shooter")
            roster[index] = { monsterId = monster, x = -3.25 - (index - 1) * 0.75, y = -1.25 }
        end
        prepare(found[RED_PROFILE], "RED", roster)
        if KIND == "HUMAN" then prepare(found[BLUE_PROFILE], "BLUE", {{ monsterId = "monster_tank", x = -3.25, y = -1.25 }}) end
        local board = _FactionWarTownDocument:InitialTowns()
        board.gushan.strength = KIND == "HUMAN" and 20 or 25
        saveBoard(board)
        _FactionWarGuard.WaitSeconds = KIND == "HUMAN" and 600 or 10
        assert(_FactionWar:Move(found[RED_PROFILE], "zuoying"), "red moves to origin")
        if KIND == "HUMAN" then assert(_FactionWar:Move(found[BLUE_PROFILE], "gushan"), "blue moves to origin") end
        assert(await(function() return found[RED_PROFILE].CurrentMapName == "zuoying"
            and (KIND ~= "HUMAN" or found[BLUE_PROFILE].CurrentMapName == "gushan") end), "both origins ready")
        log("[VRF][Result115] SETUP PASS kind=" .. KIND)
    elseif STEP == "QUEUE" then
        local found = users()
        local red = userId(found[RED_PROFILE])
        _FactionWarAttack:AttackFor(red, "gushan")
        assert(await(function() return _FactionWarAttack:IsEngaged(red) end), "red engaged")
        if KIND == "HUMAN" then
            local blue = userId(found[BLUE_PROFILE])
            _FactionWarAttack:AttackFor(blue, "zuoying")
            assert(await(function() return _FactionWarAttack:IsEngaged(blue) or _UserService:GetUserEntityByUserId(blue) == nil end), "blue engaged or transferred")
        end
        log("[VRF][Result115] QUEUE PASS; route by the match key in MatchTransfer logs")
    elseif STEP == "ARM" then
        local battle = matchPhase()
        assert(battle.Phase == "BATTLE", "arm after admission and before result")
        _FormationStorage:ConfigureMakerFaults(0, 0, 10)
        log("[VRF][Result115] ARM PASS match=" .. _RoomService.RoomKey .. "; run CLIENT now")
    elseif STEP == "RECONNECT" then
        assert(matchPhase().Phase == "RESULT", "reconnect on the result page")
        local id = userId(users()[RED_PROFILE])
        _FormationStorage:ConfigureMakerFaults(0, 0, 0)
        assert(_FactionWarTownDocument:OutcomeFrom(readBoard(), _RoomService.RoomKey).status == "DUPLICATE", "battle already committed")
        _MatchFlow:Depart(id, "Probe115")
        local event = UserReconnectEvent()
        event.UserId = id
        _UserService:SendEvent(event)
        assert(await(function() return not _MatchFlow:IsOffline(id) end), "production reconnect handler ran")
        log("[VRF][Result115] RECONNECT event PASS; RECHECK the client and compare revisions")
    elseif STEP == "BOARD" then
        assert(not _RoomService:IsInstanceRoom() and MATCH_KEY ~= "SET_ME", "set MATCH_KEY and dispatch in server_main")
        local board = readBoard()
        assert(_FactionWarTownDocument:OutcomeFrom(board, MATCH_KEY) ~= nil, "board contains this match")
        board.zuoying.owner = "BLUE"
        board.zuoying.e = _FactionWarTownDocument:EpochOf(board, "zuoying") + 1
        saveBoard(board)
        local event = TownBoardChangedEvent()
        event.Source = _WorldInstanceService.WorldInstanceId
        local sent
        _RoomService:RequestSendEventToRoomAsync(event, MATCH_KEY, function(code) sent = code == SendEventRequestResultCode.OK end)
        assert(await(function() return sent end), "board change sent to this match room")
        log("[VRF][Result115] BOARD PASS; run BOARD_CLIENT to check preview only")
    elseif STEP == "RETURN" then
        assert(matchPhase().Phase == "RESULT", "finish inspection before return")
        _FormationStorage:ConfigureMakerFaults(0, 0, 0)
        for _, user in pairs(users()) do _MatchFlow:ReturnForUser(userId(user)) end
        log("[VRF][Result115] RETURN dispatched; no landing expectation in this probe")
    elseif STEP == "CLEANUP" then
        assert(not _RoomService:IsInstanceRoom(), "clean up in server_main after the test match ends")
        _FactionWarGuard.WaitSeconds = 10
        local code = _DataStorageService:DeleteGlobalDataStorageAndWait(_FactionWarTownDocument.TownStorageName)
        log("[VRF][Result115] CLEANUP town storage delete code=" .. tostring(code))
    else
        error("unknown STEP: " .. STEP)
    end
end)
if not ok then log_error("[VRF][Result115] " .. STEP .. " FAIL " .. tostring(failure)) end
