-- Maker end-to-end for #109 (a human fight goes on while one side is disconnected; the other side keeps the room alive). Two virtual players,
-- added in Play before running this in server_main:
--   add_virtual_player -profile_code wp2623 -nickname RedAway109    (RED,  Zuoying, 3 tanks; stays connected)
--   add_virtual_player -profile_code wp2624 -nickname BlueAway109   (BLUE, Gushan,  1 tank;  disconnects mid-fight)
-- Writes the REAL town storage (Gushan starts at 20, so the red win captures it); STEP 9 deletes it. Keep the real player in formationlobby.
-- The disconnect is the production Depart run inside the match room plus a synthetic UserReconnectEvent there (the entity stays). The guard is parked at
-- 600 s by STEP 1 so no guard fight can claim a ticket; STEP 9 puts it back to 10.
-- Steps are numbered; set STEP below, dispatch, wait for the line it announces. STEP 3 to 7 run in server_instance_<matchKey> (the key is in the
-- "QUEUED match=" line); the others in server_main.
--   1 SETUP       server_main, ~60 s, wait "SETUP PASS"
--   2 QUEUE       server_main: red -> Gushan, blue -> Zuoying; the pair forms and both are moved into one room
--   3 DISCONNECT  room, after "[VRF][MatchedBattle] admission started=true": Depart for the BLUE player. Red is still online, the fight goes on
--   4 RESULT      room: the battle reaches its result; one settlement is stored (Gushan red / 100, counted once); the blue player's experience for their lost
--                 tank is settled although they are away (the match is in their monster-level history exactly once)
--   5 RECONNECT   room: a synthetic reconnect for the blue player: the ticket is back as IN_ROOM, the receipt is armed again
--   6 REDELIVER   room, BEFORE RETURN: the same result again: DUPLICATE, the towns do not move, no experience is credited twice
--   7 RETURN      room: ReturnForUser for both. Red (the conqueror) lands in Gushan, blue (the loser) in Yancheng
--   8 LANDING     server_main: red in Gushan, blue in Yancheng, nobody locked, one settlement ("LANDING PASS")
--   9 CLEANUP     deletes the war town storage and puts the guard clock back
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
    _FactionWarTownDocument:Read(function(result) towns, done = result, true end)
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
        local towns = _FactionWarTownDocument:InitialTowns()
        towns.gushan.strength = 20
        local written = false
        _FactionWarTownDocument:WriteTowns(towns, function(saved) written = saved end)
        assert(await(function() return written end, 100), "Gushan seeded at 20")
        _FactionWarGuard.WaitSeconds = 600
        assert(_FactionWar:Move(a, "zuoying") and _FactionWar:Move(b, "gushan"), "moves dispatched")
        assert(await(function() return a.CurrentMapName == "zuoying" and b.CurrentMapName == "gushan" end), "players in their towns")
        log("[VRF][ReconnectHuman] SETUP PASS")
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
        log("[VRF][ReconnectHuman] QUEUED match=" .. key .. "; wait for [VRF][MatchedBattle] admission started=true, run STEP 3 in the room, then STEP 4")
    elseif STEP == 3 then
        local _, battle = room()
        assert(battle:IsBattleActive(), "the battle is on, phase " .. tostring(battle.Phase))
        assert(isvalid(users[RED]) and isvalid(users[BLUE]), "both players are in the room")
        local away = id(users[BLUE])
        _MatchFlow:Depart(away, "Probe")
        assert(_MatchFlow:IsOffline(away) and _MatchFlow._T.records[away] == nil, "blue is offline and its record is dropped")
        assert(not _MatchFlow:IsOffline(id(users[RED])) and _MatchFlow._T.records[id(users[RED])] ~= nil, "red stays online with its ticket")
        assert(battle:IsBattleActive(), "the fight goes on")
        log("[VRF][ReconnectHuman] DISCONNECT PASS " .. _RoomService.RoomKey .. "; wait for [VRF][MatchedBattle] result published once, then STEP 4")
    elseif STEP == 4 then
        local _, battle = room()
        assert(await(function() return battle.Phase == "RESULT" end, 3000), "the battle reaches its result")
        local key = _RoomService.RoomKey
        local towns
        local red = battle:ResultForProfile(RED)
        if red == "WIN" then
            assert(await(function()
                towns = readTowns()
                return towns ~= nil and recordsOf(towns, key) == 1
            end, 300), "one settlement was stored")
            assert(towns.gushan.owner == "RED" and towns.gushan.strength == 100 and _FactionWarTownDocument:EpochOf(towns, "gushan") == 1, "Gushan was captured and counted once")
        else
            log("[VRF][ReconnectHuman] red did not win (" .. red .. "); the capture checks of this probe do not apply, run it again")
        end
        -- The away player's lost tank is credited although they are gone; each match id is in a history once.
        assert(await(function() return creditedOnce(BLUE, key) == 1 end, 100), "the away player's experience was settled exactly once")
        log("[VRF][ReconnectHuman] RESULT PASS red=" .. red .. "; run STEP 5")
    elseif STEP == 5 then
        local _, battle = room()
        local away = users[BLUE]
        assert(isvalid(away), "blue's entity is still in the room")
        local awayId = id(away)
        assert(_MatchFlow:IsOffline(awayId), "still offline from step 3")
        reconnect(awayId)
        log("[VRF][ReconnectHuman] receipt armed right after the reconnect=" .. tostring(battle._T.experienceSent[away] == nil))
        assert(await(function() return not _MatchFlow:IsOffline(awayId) end, 30), "online again")
        assert(await(function()
            local ticket = _MatchFlow._T.records[awayId]
            return ticket ~= nil and ticket.data ~= nil and ticket.data.state == "IN_ROOM" and ticket.data.matchKey == _RoomService.RoomKey
        end, 100), "the ticket is back, IN_ROOM for this room")
        assert(await(function() return battle._T.experienceSent[away] ~= nil end, 50), "the receipt went out again")
        log("[VRF][ReconnectHuman] RECONNECT PASS; run STEP 6 (REDELIVER) before STEP 7 (RETURN)")
    elseif STEP == 6 then
        local _, battle, flow = room()
        local key = _RoomService.RoomKey
        local before = readTowns()
        local status, done = nil, false
        _FactionWarAttack:Settle(key, flow._T.homeTown, flow._T.awayTown, battle:ResultForProfile(battle.HomeProfile), flow._T.kind or "HUMAN", function(s) status, done = s, true end, flow._T.epochs)
        assert(await(function() return done end, 100), "redelivery answered")
        local after = readTowns()
        assert(status == "DUPLICATE" or status == "EXEMPT" or status == "NO_CHANGE", "a repeated result is never applied again, got " .. tostring(status))
        assert(after.gushan.strength == before.gushan.strength and after.gushan.owner == before.gushan.owner and recordsOf(after, key) == recordsOf(before, key), "the towns did not move")
        for _, pair in ipairs({ { battle.HomeProfile, battle._T.deaths.PLAYER }, { battle.AwayProfile, battle._T.deaths.ENEMY } }) do
            local operation = _MonsterLevelStorage:Settle(pair[1], key, pair[2])
            assert(await(function() return operation.status ~= "PENDING" end, 100), "experience redelivery answered")
            assert(operation.status == "SAVED" and operation.duplicate == true, "a repeated result credits no second experience, got " .. operation.status .. "/" .. tostring(operation.duplicate))
        end
        log("[VRF][ReconnectHuman] REDELIVER PASS " .. key .. " status=" .. tostring(status))
    elseif STEP == 7 then
        for _, user in pairs(users) do _MatchFlow:ReturnForUser(id(user)) end
        log("[VRF][ReconnectHuman] RETURN issued")
    elseif STEP == 8 then
        assert(await(function()
            users = find()
            a, b = users[RED], users[BLUE]
            return isvalid(a) and isvalid(b) and a.CurrentMapName == "gushan" and b.CurrentMapName == "yancheng"
        end, 600), "the conqueror entered Gushan and the loser went to Yancheng")
        for _, user in ipairs({ a, b }) do assert(await(function() return not _FactionWarAttack:IsEngaged(id(user)) end), "unlocked") end
        local towns = readTowns()
        assert(towns.gushan.owner == "RED" and towns.gushan.strength == 100 and #towns.settled == 1, "one settlement is stored")
        local key = towns.settled[1].k
        assert(creditedOnce(BLUE, key) == 1, "the away player's match is in their history once")
        log("[VRF][ReconnectHuman] LANDING PASS")
    elseif STEP == 9 then
        _FactionWarGuard.WaitSeconds = 10
        local code = _DataStorageService:DeleteGlobalDataStorageAndWait(_FactionWarTownDocument.TownStorageName)
        log("[VRF][ReconnectHuman] CLEANUP town storage deleted code=" .. tostring(code))
    end
end)
if not ok then log_error("[VRF][ReconnectHuman] STEP " .. tostring(STEP) .. " FAIL " .. tostring(reason)) end
