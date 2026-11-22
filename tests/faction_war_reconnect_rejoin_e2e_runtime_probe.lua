-- Maker end-to-end for #109 (P6b): a player REALLY leaves in the middle of a human fight and logs in again with a NEW user id; the other player keeps the
-- room alive, so the static room finds the room (InstanceRooms) and moves the new entity back into it. (A guard fight cannot show this in Maker: its only
-- human is the last user, and the engine reclaims a room about a second after its last user leaves, so nothing is left to rejoin; that case is P6 STALE.)
-- Two virtual players, added in Play before running this in server_main; the blue one is added AGAIN after STEP 3 (3 of the 10 virtual players a Play allows):
--   add_virtual_player -profile_code wp2623 -nickname RedStay109    (RED,  Zuoying, 3 tanks; stays connected, keeps the room alive)
--   add_virtual_player -profile_code wp2624 -nickname BlueLeave109  (BLUE, Gushan,  1 tank;  is kicked mid-fight, then logs in again)
-- Writes the REAL town storage (Gushan starts at 20, so the red win captures it); STEP 8 deletes it. Keep the real player in formationlobby.
-- The guard is parked at 600 s by STEP 1 so no guard fight can claim a ticket; STEP 8 puts it back to 10.
-- Steps are numbered; set STEP below, dispatch, wait for the line it announces. STEP 3, 4, 5 and 6 run in server_instance_<matchKey> (the key is in the
-- "QUEUED match=" line); the others in server_main.
--   1 SETUP    server_main, ~60 s, wait "SETUP PASS"
--   2 QUEUE    server_main: red -> Gushan, blue -> Zuoying; the pair forms and both are moved into one room
--   3 KICK     room, after "[VRF][MatchedBattle] admission started=true": KickUser for the BLUE player. Then run the second console command at once
--   4 REJOIN   room, after the second add_virtual_player: the new blue entity is back in this room ("[VRF][MatchFlow] rejoin match=... moved=true"), the ticket is
--              IN_ROOM for this room ("REJOIN PASS")
--   5 RESULT   room: the battle reaches its result; one settlement is stored (Gushan red / 100, counted once); blue's lost tank is credited exactly once
--   6 RETURN   room: ReturnForUser for both (blue is a NEW entity). Red lands in Gushan, blue in Yancheng
--   7 LANDING  server_main: red in Gushan, blue in Yancheng, nobody locked, one settlement ("LANDING PASS")
--   8 CLEANUP  deletes the war town storage and puts the guard clock back
-- Expected [VRF] lines (read with logs): see tests/README.md, "Disconnect and reconnect (#109)".
local STEP = 1
local RED, BLUE = "wp2623", "wp2624"
local function await(predicate, tries) for _ = 1, tries or 300 do if predicate() then return true end wait(0.1) end return false end
local function find()
    local found = {}
    for _, user in ipairs(_UserService.UserEntities.Values) do
        if isvalid(user) and isvalid(user.PlayerComponent) then found[user.PlayerComponent.ProfileCode] = user end
    end
    return found
end
local function id(user) return user.PlayerComponent.UserId end
local function readTowns()
    local towns, done = nil, false
    _FactionWar:ReadTowns(function(result) towns, done = result, true end)
    assert(await(function() return done end, 100), "towns read")
    return towns
end
local function recordsOf(towns, key)
    local n = 0
    for _, entry in ipairs(towns.settled or {}) do
        if (type(entry) == "table" and entry.k == key) or entry == key then n = n + 1 end
    end
    return n
end
local function creditedOnce(profile, key)
    local document, code, done = nil, nil, false
    _MonsterLevelStorage:Read(profile, function(c, d) code, document, done = c, d, true end)
    assert(await(function() return done end, 100) and code == 0, "monster levels read " .. profile)
    local count = 0
    for _, matchId in ipairs(document.settled or {}) do if matchId == key then count = count + 1 end end
    return count
end
local function reconnect(userId)
    local event = UserReconnectEvent()
    event.UserId = userId
    _UserService:SendEvent(event)
end
local function room()
    local map = _EntityService:GetEntityByPath("/maps/matchprobe")
    return map, map:GetComponent("script.BattleSession"), map:GetFirstChildComponentByTypeName("script.MatchedBattle", true)
end
local ok, reason = pcall(function()
    local users = find()
    local a, b = users[RED], users[BLUE]
    if STEP == 1 then
        assert(isvalid(a) and isvalid(b), "both virtual players connected")
        local function setup(user, units)
            local record = _FormationService:GetSession(id(user))
            if not record.initialized then _FormationService:Load(record) end
            assert(await(function() return record.initialized and not record.pending end), "formation loaded")
            local slotId = record.editSlot
            _FormationService:SaveForUser(id(user), units, slotId, record.saved.slots[tostring(slotId)].revision, _UtilLogic:NewGuid())
            assert(await(function() return not record.pending and #record.saved.slots[tostring(slotId)].units == #units end), "save confirmed")
            _FormationService:ActivateForUser(id(user), slotId, record.saved.slots[tostring(slotId)].revision)
            assert(await(function() return not record.pending and record.saved.activeSlot == slotId end), "activate confirmed")
        end
        local three = {}
        for index = 1, 3 do three[index] = { monsterId = "monster_tank", x = -3.25 - (index - 1) * 0.75, y = -1.25 } end
        setup(a, three)
        setup(b, {{ monsterId = "monster_tank", x = -3.25, y = -1.25 }})
        for user, value in pairs({ [a] = "RED", [b] = "BLUE" }) do
            local saved = false
            _FormationStorage:Write(user.PlayerComponent.ProfileCode, _FactionWar.FactionKey, "", value, function(code) saved = code == 0 end)
            await(function() return saved end, 100)
        end
        local towns = _FactionWar:InitialTowns()
        towns.gushan.strength = 20
        local written = false
        _FactionWar:WriteTowns(towns, function(saved) written = saved end)
        assert(await(function() return written end, 100), "Gushan seeded at 20")
        _FactionWarGuard.WaitSeconds = 600
        assert(_FactionWar:Move(a, "zuoying") and _FactionWar:Move(b, "gushan"), "moves dispatched")
        assert(await(function() return a.CurrentMapName == "zuoying" and b.CurrentMapName == "gushan" end), "players in their towns")
        log("[VRF][ReconnectRejoin] SETUP PASS")
    elseif STEP == 2 then
        assert(isvalid(a) and isvalid(b), "both players are in server_main")
        _FactionWarAttack:AttackFor(id(a), "gushan")
        assert(await(function() return _FactionWarAttack:IsEngaged(id(a)) end, 100), "red engaged")
        _FactionWarAttack:AttackFor(id(b), "zuoying")
        assert(await(function() return _FactionWarAttack:IsEngaged(id(b)) end, 100), "blue engaged")
        local key = ""
        assert(await(function()
            local ticket = _MatchFlow._T.records[id(a)]
            key = ticket ~= nil and ticket.data ~= nil and ticket.data.matchKey or ""
            return key ~= ""
        end, 300), "the pair is sealed")
        log("[VRF][ReconnectRejoin] QUEUED match=" .. key .. "; wait for [VRF][MatchedBattle] admission started=true, run STEP 3 in the room, then STEP 4")
    elseif STEP == 3 then
        local _, battle = room()
        assert(battle:IsBattleActive(), "the battle is on, phase " .. tostring(battle.Phase))
        assert(isvalid(users[RED]) and isvalid(users[BLUE]), "both players are in the room")
        _UserService:KickUser(id(users[BLUE]), KickReason.ETC)
        assert(await(function() return find()[BLUE] == nil end, 100), "the blue entity left the room")
        assert(isvalid(find()[RED]) and battle:IsBattleActive(), "red stays, the fight goes on")
        log("[VRF][ReconnectRejoin] KICKED match=" .. _RoomService.RoomKey .. "; now add_virtual_player -profile_code " .. BLUE .. " -nickname BlueLeave109, then STEP 4")
    elseif STEP == 4 then
        local key = _RoomService.RoomKey
        assert(await(function()
            b = find()[BLUE]
            return isvalid(b)
        end, 600), "the new blue entity is in this room")
        assert(await(function()
            local ticket = _MatchFlow._T.records[id(b)]
            return ticket ~= nil and ticket.data ~= nil and ticket.data.state == "IN_ROOM" and ticket.data.matchKey == key
        end, 100), "its ticket is IN_ROOM for this room")
        log("[VRF][ReconnectRejoin] REJOIN PASS match=" .. key .. "; wait for [VRF][MatchedBattle] result published once, then STEP 5")
    elseif STEP == 5 then
        local _, battle = room()
        assert(await(function() return battle.Phase == "RESULT" end, 3000), "the battle reaches its result")
        local key = _RoomService.RoomKey
        local red = battle:ResultForProfile(RED)
        if red == "WIN" then
            local towns
            assert(await(function()
                towns = readTowns()
                return towns ~= nil and recordsOf(towns, key) == 1
            end, 300), "one settlement was stored")
            assert(towns.gushan.owner == "RED" and towns.gushan.strength == 100 and _FactionWar:EpochOf(towns, "gushan") == 1, "Gushan was captured and counted once")
        else
            log("[VRF][ReconnectRejoin] red did not win (" .. red .. "); the capture checks of this probe do not apply, run it again")
        end
        assert(await(function() return creditedOnce(BLUE, key) == 1 end, 100), "the rejoined player's experience was settled exactly once")
        log("[VRF][ReconnectRejoin] RESULT PASS red=" .. red .. "; run STEP 6")
    elseif STEP == 6 then
        for _, user in pairs(users) do _MatchFlow:ReturnForUser(id(user)) end
        log("[VRF][ReconnectRejoin] RETURN issued")
    elseif STEP == 7 then
        assert(await(function()
            users = find()
            a, b = users[RED], users[BLUE]
            return isvalid(a) and isvalid(b) and a.CurrentMapName == "gushan" and b.CurrentMapName == "yancheng"
        end, 600), "the conqueror entered Gushan and the loser went to Yancheng")
        for _, user in ipairs({ a, b }) do assert(await(function() return not _FactionWarAttack:IsEngaged(id(user)) end), "unlocked") end
        local towns = readTowns()
        assert(towns.gushan.owner == "RED" and towns.gushan.strength == 100 and #towns.settled == 1, "one settlement is stored")
        assert(creditedOnce(BLUE, towns.settled[1].k) == 1, "blue's match is in their history once")
        log("[VRF][ReconnectRejoin] LANDING PASS")
    elseif STEP == 8 then
        _FactionWarGuard.WaitSeconds = 10
        local code = _DataStorageService:DeleteGlobalDataStorageAndWait(_FactionWar.TownStorageName)
        log("[VRF][ReconnectRejoin] CLEANUP town storage deleted code=" .. tostring(code))
    end
end)
if not ok then log_error("[VRF][ReconnectRejoin] STEP " .. tostring(STEP) .. " FAIL " .. tostring(reason)) end
