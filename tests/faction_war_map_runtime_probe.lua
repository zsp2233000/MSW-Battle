-- Maker `server_main`, fresh Play, the real player in formationlobby. Dispatch this, then at once dispatch
-- faction_war_map_client_runtime_probe.lua in `client`; the two follow each other through the viewer list.
-- Works on the isolated board CountryWarProbeMapV1 (deleted at the end); never writes the player's faction or last town.
-- Final line: [VRF][MapProbe] SERVER PASS (the client prints CLIENT PASS).
local STORAGE = "CountryWarProbeMapV1"
local original = _FactionWarTownDocument.TownStorageName
local function await(predicate, seconds)
    for _ = 1, math.floor((seconds or 10) * 10) do
        if predicate() then return true end
        wait(0.1)
    end
    return false
end
local function call(start)
    local box = { done = false }
    start(function(value) box.value = value box.done = true end)
    assert(await(function() return box.done end, 10), "storage answered")
    return box.value
end
local function board(gushan)
    return { nanzih = { owner = "RED", strength = 100 }, zuoying = { owner = "RED", strength = 80 },
        gushan = { owner = "BLUE", strength = gushan }, yancheng = { owner = "BLUE", strength = 100 } }
end
local function viewers()
    local n = 0
    for _ in pairs(_FactionWarMap._T.viewers) do n = n + 1 end
    return n
end
local ok, reason = pcall(function()
    local player = nil
    for _, user in ipairs(_UserService.UserEntities.Values) do player = user end
    assert(isvalid(player), "the real player is in the room")
    _FactionWarTownDocument.TownStorageName = STORAGE
    assert(call(function(done) _FactionWarTownDocument:WriteTowns(board(70), done) end) == true, "isolated board written")

    -- Gate links come from the authored gates: the chain north to south and nothing else.
    local links = _FactionWarMap:Links()
    local pairs_ = {}
    for _, link in ipairs(links) do table.insert(pairs_, link.a .. "-" .. link.b) end
    assert(table.concat(pairs_, ",") == "nanzih-zuoying,zuoying-gushan,gushan-yancheng", "gate links: " .. table.concat(pairs_, ","))

    -- Stand in a town the player's faction owns on this board, so no eviction interferes.
    local faction = call(function(done) _FactionWar:ReadFaction(player.PlayerComponent.ProfileCode, done) end)
    local town = faction == "BLUE" and "gushan" or "zuoying"
    local arrival = _EntityService:GetEntityByPath("/maps/" .. town):GetChildByName("TownArrival")
    _TeleportService:TeleportToMapPosition(player, arrival.TransformComponent.WorldPosition, town)
    log("[VRF][MapProbe] SETUP faction=" .. tostring(faction) .. " town=" .. town)

    -- 1. The client opens the map: it becomes a viewer and gets the board.
    assert(await(function() return viewers() == 1 end, 25), "client opened the map")
    log("[VRF][MapProbe] viewer registered")
    wait(2)

    -- 2. A settlement-like change is pushed without the client asking.
    assert(call(function(done) _FactionWarTownDocument:WriteTowns(board(50), done) end) == true, "board changed")
    _FactionWarMap:AnnounceChange()
    log("[VRF][MapProbe] PUSH announced gushan=50")
    -- Observation, not an assertion: whether the all-instances event also reaches the sender's own instance in Maker.
    -- AnnounceChange's own event carries this instance's id and is ignored; this one pretends to come from elsewhere,
    -- so "[VRF][FactionWarMap] change received via=instance" appears only if the own instance receives it.
    local foreign = TownBoardChangedEvent()
    foreign.Source = "probe-other-instance"
    _WorldInstanceService:RequestSendEventToAllWorldInstancesAsync(foreign, function(code)
        log("[VRF][MapProbe] foreign event sent=" .. tostring(code == SendEventRequestResultCode.OK))
    end)

    -- 3. Once the client closed the map, a change reads nothing and sends nothing.
    assert(await(function() return viewers() == 0 end, 25), "client closed the map")
    assert(call(function(done) _FactionWarTownDocument:WriteTowns(board(40), done) end) == true, "board changed while closed")
    _FactionWarMap:AnnounceChange()
    wait(1)
    assert(not _FactionWarMap._T.reading, "no board read for a room with no viewer")
    log("[VRF][MapProbe] CLOSED no push")

    -- 4. Reopening reads the board fresh; leaving the town ends the subscription.
    assert(await(function() return viewers() == 1 end, 25), "client reopened the map")
    wait(3)
    _TeleportService:TeleportToMapPosition(player, Vector3(0, 0, 0), "formationlobby")
    assert(await(function() return viewers() == 0 end, 25), "leaving the town ends the subscription")
    log("[VRF][MapProbe] SERVER PASS")
end)
_FactionWarTownDocument.TownStorageName = original
_DataStorageService:DeleteGlobalDataStorageAndWait(STORAGE)
if not ok then log_error("[VRF][MapProbe] SERVER FAIL " .. tostring(reason)) end
