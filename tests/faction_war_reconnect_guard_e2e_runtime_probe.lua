-- Maker end-to-end for #109 (a guard fight goes on while the only player is disconnected, the reconnect gets the same room back, the result is delivered once).
-- One virtual player, added in Play before running this in server_main:
--   add_virtual_player -profile_code wp2622 -nickname Guard109   (A, Zuoying, 4 units; Gushan is seeded at 10, so a guard win captures it)
-- Writes the REAL town storage (Gushan starts at 10); STEP 9 deletes it. Keep the real player in formationlobby.
-- The disconnect is the production Depart run inside the match room plus a synthetic UserReconnectEvent there: the entity stays in the room, like a
-- retained disconnected entity. A real leave (KickUser) while the room runs is faction_war_reconnect_relogin_e2e_runtime_probe.lua.
-- Steps are numbered; set STEP below, dispatch, wait for the line it announces. STEP 3 to 7 run in server_instance_<matchKey> (the key is in the
-- "QUEUED match=" line and in "[VRF][MatchTransfer] match="); the others in server_main.
--   1 SETUP       server_main, ~30 s, wait "SETUP PASS"
--   2 QUEUE       server_main: AttackFor Gushan; the guard claims the ticket after 10 s and the player is moved into the room
--   3 DISCONNECT  room, after "[VRF][MatchedBattle] admission started=true" and before the result: Depart; the ticket record is dropped, the player is offline,
--                 the fight is still on ("DISCONNECT PASS")
--   4 RESULT      room: the battle reaches its result by itself and the room settles it exactly once with the player away
--                 (a win: one record in towns.settled and Gushan red / 100; "RESULT PASS"); the receipt was sent to the entity that is away
--   5 RECONNECT   room: a synthetic reconnect. The ticket is back as IN_ROOM for this room, the experience receipt is armed again and goes out a second
--                 time (read the log: "[VRF][BattleSession] experience receipt re-armed", then a second "[VRF][ResultExperience] sent profile=wp2622";
--                 "RECONNECT PASS"). Nothing is settled again
--   6 REDELIVER   room, BEFORE RETURN: the same result is delivered again: Settle answers DUPLICATE (NO_CHANGE after a loss), the towns do not move, the
--                 experience is not credited twice. It cannot run after RETURN: the match room is recycled once its player has left
--   7 RETURN      room: ReturnForUser; look for "[VRF][FactionWarAttack] landing ... origin=zuoying destination=zuoying originLost=false"
--   8 LANDING     server_main: in Zuoying even after capture; unlocked, one XP credit, capture record unchanged ("LANDING PASS")
--   9 CLEANUP     deletes the war town storage
--  10 LOSE_ORIGIN optional ADR 0016 variant, written, not run: in a separate fresh Play run 1–6, then STEP 10 in server_main after a capture.
--                 Run 7 then 8 with EXPECT_ORIGIN_LOST = true for STEP 8. Expect Nanzih and a single recorded landing notice there with originLost=true.
-- Expected [VRF] lines (read with logs): see tests/README.md, "Disconnect and reconnect (#109)".
local STEP = 1
local EXPECT_ORIGIN_LOST = false -- set true for STEP 8 only when STEP 10 was used
local PROFILE = "wp2622"
local function await(predicate, tries) for _ = 1, tries or 300 do if predicate() then return true end wait(0.1) end return false end
local function find()
    for _, user in ipairs(_UserService.UserEntities.Values) do
        if isvalid(user) and isvalid(user.PlayerComponent) and user.PlayerComponent.ProfileCode == PROFILE then return user end
    end
    return nil
end
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
local function history(profile)
    local document, code, done = nil, nil, false
    _MonsterLevelStorage:Read(profile, function(c, d) code, document, done = c, d, true end)
    assert(await(function() return done end, 100) and code == 0, "monster levels read " .. profile)
    return document
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
    local a = find()
    if STEP <= 2 or STEP == 8 then assert(isvalid(a), "virtual player connected") end
    local userId = isvalid(a) and a.PlayerComponent.UserId or nil
    if STEP == 1 then
        local record = _FormationService:GetSession(userId)
        if not record.initialized then _FormationService:Load(record) end
        assert(await(function() return record.initialized and not record.pending end), "formation loaded")
        local units = {}
        for index = 1, 4 do units[index] = { monsterId = index <= 2 and "monster_dark_centaur" or "monster_shooter", x = -3.25 - (index - 1) * 0.75, y = -1.25 } end
        local slotId = record.editSlot
        _FormationService:SaveForUser(userId, units, slotId, record.saved.slots[tostring(slotId)].revision, _UtilLogic:NewGuid())
        assert(await(function() return not record.pending and #record.saved.slots[tostring(slotId)].units == #units end), "save confirmed")
        _FormationService:ActivateForUser(userId, slotId, record.saved.slots[tostring(slotId)].revision)
        assert(await(function() return not record.pending and record.saved.activeSlot == slotId end), "activate confirmed")
        local saved = false
        _FormationStorage:Write(PROFILE, _FactionWar.FactionKey, "", "A", function(code) saved = code == 0 end)
        await(function() return saved end, 100)
        -- Gushan one guard win from falling (a guard win takes 10).
        local towns = _FactionWarTownDocument:InitialTowns()
        towns.gushan.strength = 10
        local written = false
        _FactionWarTownDocument:WriteTowns(towns, function(ok) written = ok end)
        assert(await(function() return written end, 100), "Gushan seeded at 10")
        -- The #107 and #108 e2e probes park the guard at 600 s; this one needs the real 10 s.
        _FactionWarGuard.WaitSeconds = 10
        assert(_FactionWar:Move(a, "zuoying"), "move dispatched")
        assert(await(function() return a.CurrentMapName == "zuoying" end), "in Zuoying")
        log("[VRF][ReconnectGuard] SETUP PASS")
    elseif STEP == 2 then
        _FactionWarAttack:AttackFor(userId, "gushan")
        assert(await(function() return _MatchFlow:StateForUser(userId) == "QUEUED" end, 100), "queued")
        local queuedAt = os.clock()
        assert(await(function() return _MatchFlow:StateForUser(userId) ~= "QUEUED" end, 200), "the guard claimed the ticket")
        local waited = os.clock() - queuedAt
        assert(waited > 8 and waited < 14, "the guard comes after about ten seconds, took " .. tostring(waited))
        local key = ""
        assert(await(function()
            local ticket = _MatchFlow._T.records[userId]
            key = ticket ~= nil and ticket.data ~= nil and ticket.data.matchKey or ""
            return key ~= ""
        end, 300), "the pairing is sealed")
        log("[VRF][ReconnectGuard] QUEUED match=" .. key .. " after " .. tostring(waited) .. " s; wait for [VRF][MatchedBattle] admission started=true, run STEP 3 in the room, then STEP 4")
    elseif STEP == 3 then
        local _, battle = room()
        assert(battle:IsBattleActive(), "the battle is on, phase " .. tostring(battle.Phase))
        local human = find()
        assert(isvalid(human), "the player is in the room")
        local id = human.PlayerComponent.UserId
        _MatchFlow:Depart(id, "Probe")
        assert(_MatchFlow:IsOffline(id), "marked offline")
        assert(_MatchFlow._T.records[id] == nil, "the room's record of the ticket is dropped")
        assert(battle:IsBattleActive(), "the fight goes on without the player")
        log("[VRF][ReconnectGuard] DISCONNECT PASS " .. _RoomService.RoomKey .. "; wait for [VRF][MatchedBattle] result published once, then STEP 4")
    elseif STEP == 4 then
        local _, battle = room()
        assert(await(function() return battle.Phase == "RESULT" end, 3000), "the battle reaches its result while the player is away")
        local result = battle:ResultForProfile(PROFILE)
        assert(result ~= "", "the result names the player's side")
        local key = _RoomService.RoomKey
        local human = find()
        local towns
        if result == "WIN" then
            assert(await(function()
                towns = readTowns()
                return towns ~= nil and recordsOf(towns, key) == 1
            end, 300), "the settlement was stored exactly once")
            assert(towns.gushan.owner == "A" and towns.gushan.strength == 100 and _FactionWarTownDocument:EpochOf(towns, "gushan") == 1, "Gushan was captured and counted once")
        else
            wait(5)
            towns = readTowns()
            assert(recordsOf(towns, key) == 0 and towns.gushan.owner == "B" and towns.gushan.strength == 10, "a loss or a draw to the guard changes nothing")
        end
        assert(isvalid(human) and await(function() return battle._T.experienceSent[human] ~= nil end, 100), "the receipt was sent to the entity that is away")
        log("[VRF][ReconnectGuard] RESULT PASS result=" .. result .. "; run STEP 5")
    elseif STEP == 5 then
        local _, battle = room()
        local human = find()
        assert(isvalid(human), "the player's entity is still in the room")
        local id = human.PlayerComponent.UserId
        assert(_MatchFlow:IsOffline(id), "still offline from step 3")
        reconnect(id)
        -- The handler arms the receipt before it recovers the ticket, so right after the call the mark is normally still empty (the next update sends again).
        log("[VRF][ReconnectGuard] receipt armed right after the reconnect=" .. tostring(battle._T.experienceSent[human] == nil))
        assert(await(function() return not _MatchFlow:IsOffline(id) end, 30), "online again")
        assert(await(function()
            local ticket = _MatchFlow._T.records[id]
            return ticket ~= nil and ticket.data ~= nil and ticket.data.state == "IN_ROOM" and ticket.data.matchKey == _RoomService.RoomKey
        end, 100), "the ticket is back, IN_ROOM for this room")
        assert(await(function() return battle._T.experienceSent[human] ~= nil end, 50), "the receipt went out again")
        log("[VRF][ReconnectGuard] RECONNECT PASS; run STEP 6 (REDELIVER) before STEP 7 (RETURN)")
    elseif STEP == 6 then
        local _, battle, flow = room()
        local key = _RoomService.RoomKey
        local before = readTowns()
        local status, done = nil, false
        _FactionWarAttack:Settle(key, flow._T.homeTown, flow._T.awayTown, battle:ResultForProfile(battle.HomeProfile), flow._T.kind or "GUARD", function(s) status, done = s, true end, flow._T.epochs)
        assert(await(function() return done end, 100), "redelivery answered")
        local after = readTowns()
        assert(status == "DUPLICATE" or status == "NO_CHANGE" or status == "EXEMPT", "a repeated result is never applied again, got " .. tostring(status))
        assert(after.gushan.strength == before.gushan.strength and after.gushan.owner == before.gushan.owner and recordsOf(after, key) == recordsOf(before, key), "the towns did not move")
        local operation = _MonsterLevelStorage:Settle(PROFILE, key, battle._T.deaths.PLAYER)
        assert(await(function() return operation.status ~= "PENDING" end, 100), "experience redelivery answered")
        assert(operation.status == "SAVED" and operation.duplicate == true, "a repeated result credits no second experience, got " .. operation.status .. "/" .. tostring(operation.duplicate))
        log("[VRF][ReconnectGuard] REDELIVER PASS " .. key .. " status=" .. tostring(status))
    elseif STEP == 7 then
        local human = find()
        assert(isvalid(human), "the player is in the room")
        _MatchFlow:ReturnForUser(human.PlayerComponent.UserId)
        log("[VRF][ReconnectGuard] RETURN issued")
    elseif STEP == 8 then
        local towns = readTowns()
        local captured = towns.gushan.owner == "A"
        local expected = EXPECT_ORIGIN_LOST and "nanzih" or "zuoying"
        assert(towns.zuoying.owner == (EXPECT_ORIGIN_LOST and "B" or "A"), "expected origin ownership at return")
        assert(await(function()
            a = find()
            return isvalid(a) and a.CurrentMapName == expected
        end, 600), "landed in " .. expected)
        userId = a.PlayerComponent.UserId
        assert(await(function() return not _FactionWarAttack:IsEngaged(userId) end), "unlocked")
        local ticket = nil
        assert(await(function()
            ticket = _FormationHandoff:Read(PROFILE)
            return ticket ~= nil and ticket.data ~= nil and ticket.data.state == "RETURNED"
        end, 100), "the ticket is closed")
        local key = ticket.data.matchKey
        assert(key ~= nil and key ~= "", "the closed ticket remembers the match")
        local count = 0
        for _, id in ipairs(history(PROFILE).settled or {}) do if id == key then count = count + 1 end end
        assert(count == 1, "the match is in the monster-level history exactly once, found " .. tostring(count))
        if captured then
            assert(towns.gushan.strength == 100 and recordsOf(towns, key) == 1 and _FactionWarTownDocument:EpochOf(towns, "gushan") == 1, "one settlement, one capture")
        else
            assert(towns.gushan.strength == 10 and recordsOf(towns, key) == 0, "no settlement changed Gushan")
        end
        log("[VRF][ReconnectGuard] LANDING PASS in " .. expected)
    elseif STEP == 9 then
        _FactionWarGuard.WaitSeconds = 10
        local code = _DataStorageService:DeleteGlobalDataStorageAndWait(_FactionWarTownDocument.TownStorageName)
        log("[VRF][ReconnectGuard] CLEANUP town storage deleted code=" .. tostring(code))
    elseif STEP == 10 then
        assert(not _RoomService:IsInstanceRoom() and not isvalid(find()), "run in server_main while the player is still looking at the result")
        local towns = readTowns()
        assert(towns.gushan.owner == "A" and towns.zuoying.owner == "A", "the guard capture completed and the origin is still owned")
        -- Simulate another battle winning Zuoying during the result screen, without altering the guard capture record.
        towns.zuoying.owner, towns.zuoying.strength, towns.zuoying.e = "B", 100, _FactionWarTownDocument:EpochOf(towns, "zuoying") + 1
        local written = false
        _FactionWarTownDocument:WriteTowns(towns, function(saved) written = saved end)
        assert(await(function() return written end, 100), "the origin changed hands before RETURN")
        log("[VRF][ReconnectGuard] LOSE_ORIGIN staged; run STEP 7, then STEP 8 with EXPECT_ORIGIN_LOST=true")
    end
end)
if not ok then log_error("[VRF][ReconnectGuard] STEP " .. tostring(STEP) .. " FAIL " .. tostring(reason)) end
