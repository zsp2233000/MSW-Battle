-- #130 Maker probe. One local player only, in a fresh Play. Substitute STEP and FACTION before dispatch.
-- For each FACTION (A, B, then optionally empty): SETUP in server_main, MAP in client (screenshot),
-- SIEGE in client (screenshot), RESET in client. Finally CLEANUP in server_main. No actual matchmaking runs.
-- Only isolated Maker faction/board keys are written, and CLEANUP deletes them.
local STEP = "SETUP"
local FACTION = "A"
local ORIGIN = FACTION == "B" and "gushan" or "zuoying"
local TARGET = FACTION == "B" and "zuoying" or "gushan"
local function await(predicate, message)
    for _ = 1, 160 do
        if predicate() then return end
        wait(0.1)
    end
    error(message)
end

local function colorIs(color, expected, path)
    assert(math.abs(color.r - expected[1]) < 0.01 and math.abs(color.g - expected[2]) < 0.01
        and math.abs(color.b - expected[3]) < 0.01, path .. " has wrong tint: " .. tostring(color))
end
local gray = { 0.62, 0.60, 0.56 }
local function expected(owner)
    if FACTION == "" then return gray end
    return FACTION == owner and { 0.27, 0.50, 0.88 } or { 0.84, 0.29, 0.24 }
end
local function fill(entity, width, tint)
    assert(isvalid(entity) and entity.Enable, "missing or hidden strength fill")
    assert(math.abs(entity.UITransformComponent.RectSize.x - width) < 0.5, "wrong strength fill width")
    colorIs(entity.SpriteGUIRendererComponent.Color, tint, entity.Name)
end

local ok, failure = pcall(function()
    assert(Environment:IsMakerPlay(), "Maker Play required")
    if STEP == "SETUP" then
        local users = _UserService.UserEntities.Values
        assert(#users == 1, "use one local real client and no virtual players")
        local player = users[1]
        local war, doc = _FactionWar, _FactionWarTownDocument
        local profile = player.PlayerComponent.ProfileCode
        local storage = _DataStorageService:GetUserDataStorage(profile)
        if war._T.stanceProbe == nil then
            war._T.stanceProbe = { profile = profile, factionKey = war.FactionKey, boardName = doc.TownStorageName }
            local suffix = _UtilLogic:NewGuid()
            war.FactionKey = "StanceProbeFaction_" .. suffix
            doc.TownStorageName = "StanceProbeBoard_" .. suffix
            local towns = doc:InitialTowns()
            towns.zuoying.strength, towns.gushan.strength = 80, 55
            local written
            doc:WriteTowns(towns, function(value) written = value end)
            await(function() return written ~= nil end, "board write did not answer")
            assert(written, "isolated board write failed")
        end
        assert(war._T.stanceProbe.profile == profile and war.FactionKey:find("^StanceProbeFaction_"), "isolated probe profile and key")
        if FACTION ~= "" then
            assert(storage:SetAndWait(war.FactionKey, FACTION) == 0, "write isolated faction")
        else
            local code = storage:DeleteAndWait(war.FactionKey)
            assert(code == 0 or code == 1000002, "clear isolated faction")
        end
        local arrival = _EntityService:GetEntityByPath("/maps/" .. ORIGIN):GetChildByName("TownArrival")
        _TeleportService:TeleportToMapPosition(player, arrival.TransformComponent.WorldPosition, ORIGIN)
        await(function() return player.CurrentMapName == ORIGIN end, "arrival not confirmed")
    elseif STEP == "CLEANUP" then
        local war, doc = _FactionWar, _FactionWarTownDocument
        local probe = assert(war._T.stanceProbe, "probe not initialized")
        local factionKey, boardName = war.FactionKey, doc.TownStorageName
        assert(factionKey:find("^StanceProbeFaction_") and boardName:find("^StanceProbeBoard_"), "never delete live keys")
        war.FactionKey, doc.TownStorageName = probe.factionKey, probe.boardName
        war._T.stanceProbe = nil
        local code = _DataStorageService:GetUserDataStorage(probe.profile):DeleteAndWait(factionKey)
        assert(code == 0 or code == 1000002, "remove isolated faction")
        assert(_DataStorageService:DeleteGlobalDataStorageAndWait(boardName) == 0, "remove isolated board")
    elseif STEP == "MAP" then
        local ui = _FactionWarMapUI
        await(function() return _UserService.LocalPlayer.CurrentMapName == ORIGIN and ui:Ui("OpenButton").Enable end, "town map button not ready")
        ui:Open()
        local side, map = "Overlay/Window/Side/", "Overlay/Window/Map/Content/"
        local label = ui:Ui(side .. "Faction").TextGUIRendererComponent
        local name = FACTION == "" and "尚未加入陣營" or FACTION .. " 方"
        assert(label.Text == "讀取中…", "the map starts without a faction")
        colorIs(ui:Ui(map .. "Towns/zuoying/Crest").SpriteGUIRendererComponent.Color, gray, "before the faction reply")
        await(function() return label.Text == name and ui:Ui(side .. "Rows/zuoying/Value").TextGUIRendererComponent.Text == "80/100" end, "map replies did not arrive")
        colorIs(label.FontColor, { 0.93, 0.78, 0.56 }, "faction label")
        assert(ui:Ui(side .. "Legend/Ally/Label").TextGUIRendererComponent.Text == "我方", "ally legend")
        assert(ui:Ui(side .. "Legend/Enemy/Label").TextGUIRendererComponent.Text == "敵方", "enemy legend")
        colorIs(ui:Ui(side .. "Legend/Ally").SpriteGUIRendererComponent.Color, { 0.27, 0.50, 0.88 }, "ally legend")
        colorIs(ui:Ui(side .. "Legend/Enemy").SpriteGUIRendererComponent.Color, { 0.84, 0.29, 0.24 }, "enemy legend")
        for id, owner in pairs({ nanzih = "A", zuoying = "A", gushan = "B", yancheng = "B" }) do
            local tint = expected(owner)
            colorIs(ui:Ui(map .. "Towns/" .. id .. "/Crest").SpriteGUIRendererComponent.Color, tint, id .. " crest")
            colorIs(ui:Ui(map .. "Districts/" .. id).SpriteGUIRendererComponent.Color, tint, id .. " district")
            local strength = id == "zuoying" and 0.8 or (id == "gushan" and 0.55 or 1)
            fill(ui:Ui(side .. "Rows/" .. id .. "/Bar/Fill"), ui.BarWidth * strength, tint)
        end
    elseif STEP == "SIEGE" then
        local ui = _FactionWarUI
        _FactionWarMapUI:Close()
        assert(_MatchFlowInput.Snapshot.state == "IDLE", "probe needs a real idle session")
        ui._T.stanceProbeSnapshot = _MatchFlowInput.Snapshot
        -- Only the client presentation is synthetic; its board and faction come from the real subscription RPC.
        local now = DateTime.UtcNow.Elapsed
        _MatchFlowInput.Snapshot = { state = "QUEUED", reasonCode = "", started = now, players = 0, busy = false, summary = "",
            attempt = "stance-probe", origin = ORIGIN, target = TARGET, guardAt = now + 300000, sequenceKey = "stance-probe", sequence = 1 }
        await(function() return ui._T.siegeFaction == FACTION and ui._T.siegeTowns ~= nil end, "siege replies did not arrive")
        ui:RenderSiege(ORIGIN)
        assert(ui:Ui("SiegePanel").Enable, "siege panel is open")
        for side, id in pairs({ Origin = ORIGIN, Target = TARGET }) do
            local owner, ratio = "A", 0.8
            if id == "gushan" then owner, ratio = "B", 0.55 end
            local bar = "SiegePanel/" .. side .. "Bar"
            fill(ui:Ui(bar .. "/Fill"), ui:Ui(bar).UITransformComponent.RectSize.x * ratio, expected(owner))
        end
    elseif STEP == "RESET" then
        local ui = _FactionWarUI
        _FactionWarMapUI:Close()
        if ui._T.stanceProbeSnapshot ~= nil then
            _MatchFlowInput.Snapshot = ui._T.stanceProbeSnapshot
            ui._T.stanceProbeSnapshot = nil
        end
        await(function() return not ui:Ui("SiegePanel").Enable end, "siege panel did not close")
    else
        error("unknown step")
    end
end)
local message = "[VRF][WarStance] " .. STEP .. " faction=" .. (FACTION == "" and "none" or FACTION)
if ok then log(message .. " PASS") else log_error(message .. " FAIL " .. tostring(failure)) end
