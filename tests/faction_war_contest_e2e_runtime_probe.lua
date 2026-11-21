-- Maker end-to-end for #108 (two matches contest one town). Needs five virtual players, added in Play before running this in server_main:
--   add_virtual_player -profile_code wp2611 -nickname RedOne    (RED,  Zuoying, 3 tanks, home of match 1)
--   add_virtual_player -profile_code wp2612 -nickname BlueOne    (BLUE, Gushan,  1 tank,  away of match 1)
--   add_virtual_player -profile_code wp2613 -nickname RedTwo     (RED,  Zuoying, 3 tanks, home of match 2)
--   add_virtual_player -profile_code wp2614 -nickname BlueTwo    (BLUE, Gushan,  1 tank,  away of match 2)
--   add_virtual_player -profile_code wp2615 -nickname BlueIdle   (BLUE, Gushan,  stands still, must be sent home exactly once)
-- Writes the REAL town storage (Gushan starts at 20); STEP 9 deletes it. Keep the real player in formationlobby.
-- Steps are numbered; set STEP below, dispatch, wait for the line it announces.
--   1 SETUP      server_main, ~90 s, wait "SETUP PASS"
--   2 QUEUE1     server_main: RedOne -> Gushan, BlueOne -> Zuoying (pair 1), RedTwo -> Gushan, BlueTwo -> Zuoying (pair 2).
--                Both pairings are made while Gushan is still blue at 20, so every ticket is stamped Gushan = 0.
--   3 CAPTURE    server_main, after BOTH match rooms logged "[VRF][MatchedBattle] result published once", one of them with
--                "status=SAVED", the other with "status=EXEMPT": Gushan is red, 100, counted once; one record; the idle blue player was sent home
--   4 RETURN     server_instance_<matchKey>, run in EACH of the two rooms: ReturnForUser for every user in the room
--   5 REDELIVER  server_instance_<matchKey>, run in EACH room (before or after RETURN): the same result is delivered again; the towns and the
--                experience do not move (DUPLICATE for the room that flipped, EXEMPT for the other)
--   6 LANDING1   server_main: exactly one red player stands in Gushan (the conqueror), the other in Zuoying; both blue players and the idle
--                one stand in Yancheng; nobody is locked; both matches are in the blue players' monster-level history
--   7 QUEUE2     server_main: Gushan is put back to blue/60; the red player who stayed in Zuoying and the blue player who went to Yancheng
--                are paired (stamp Gushan = 0), then the document is rewritten as "taken and taken back" (blue, 60, counted twice)
--   8 LANDING2   server_main, after STEP 4 in the new room: no deduction (Gushan still 60, counted twice), the red player stays in Zuoying,
--                the blue player stays in Gushan (its own town again)
--   9 CLEANUP
-- Expected [VRF] lines (read with logs): see the probe plan in the #108 report.
local STEP = 1
local PROFILES = { "wp2611", "wp2612", "wp2613", "wp2614", "wp2615" }
local function await(predicate, tries) for _ = 1, tries or 300 do if predicate() then return true end wait(0.1) end return false end
local function find()
    local found = {}
    for _, user in ipairs(_UserService.UserEntities.Values) do found[user.PlayerComponent.ProfileCode] = user end
    return found
end
local function id(user) return user.PlayerComponent.UserId end
local function readTowns()
    local towns, done = nil, false
    _FactionWar:ReadTowns(function(result) towns, done = result, true end)
    assert(await(function() return done end, 100), "towns read")
    return towns
end
local function ticketData(user)
    local ticket = _MatchFlow._T.records[id(user)]
    return ticket ~= nil and ticket.data or nil
end
local function history(profile)
    local document, code, done = nil, nil, false
    _MonsterLevelStorage:Read(profile, function(c, d) code, document, done = c, d, true end)
    assert(await(function() return done end, 100) and code == 0, "monster levels read " .. profile)
    return document
end
local ok, reason = pcall(function()
    local users = find()
    local r1, b1, r2, b2, idle = users.wp2611, users.wp2612, users.wp2613, users.wp2614, users.wp2615
    if STEP == 1 then
        for _, profile in ipairs(PROFILES) do assert(isvalid(users[profile]), profile .. " connected") end
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
        setup(r1, three)
        setup(r2, three)
        setup(b1, {{ monsterId = "monster_tank", x = -3.25, y = -1.25 }})
        setup(b2, {{ monsterId = "monster_tank", x = -3.25, y = -1.25 }})
        for user, value in pairs({ [r1] = "RED", [r2] = "RED", [b1] = "BLUE", [b2] = "BLUE", [idle] = "BLUE" }) do
            local saved = false
            _FormationStorage:Write(user.PlayerComponent.ProfileCode, _FactionWar.FactionKey, "", value, function(code) saved = code == 0 end)
            await(function() return saved end, 100)
        end
        -- Gushan one win from falling; the guard must not claim a queued player before the two human matches are made.
        local towns = _FactionWar:InitialTowns()
        towns.gushan.strength = 20
        local written = false
        _FactionWar:WriteTowns(towns, function(saved) written = saved end)
        assert(await(function() return written end, 100), "Gushan seeded at 20")
        _FactionWarGuard.WaitSeconds = 600
        assert(_FactionWar:Move(r1, "zuoying") and _FactionWar:Move(r2, "zuoying") and _FactionWar:Move(b1, "gushan") and _FactionWar:Move(b2, "gushan") and _FactionWar:Move(idle, "gushan"), "moves dispatched")
        assert(await(function()
            return r1.CurrentMapName == "zuoying" and r2.CurrentMapName == "zuoying" and b1.CurrentMapName == "gushan" and b2.CurrentMapName == "gushan" and idle.CurrentMapName == "gushan"
        end), "players in their towns")
        log("[VRF][ContestE2E] SETUP PASS")
    elseif STEP == 2 then
        local function pair(red, blue)
            _FactionWarAttack:AttackFor(id(red), "gushan")
            assert(await(function() return _FactionWarAttack:IsEngaged(id(red)) end, 100), "red engaged")
            _FactionWarAttack:AttackFor(id(blue), "zuoying")
            assert(await(function() return _FactionWarAttack:IsEngaged(id(blue)) end, 100), "blue engaged")
            -- The pair must exist before the next ticket, or FIFO could pair a red with the wrong blue.
            assert(await(function() return _MatchFlow:StateForUser(id(red)) ~= "QUEUED" and _MatchFlow:StateForUser(id(blue)) ~= "QUEUED" end, 300), "pair formed")
        end
        pair(r1, b1)
        pair(r2, b2)
        -- Every ticket carries the stamp of the board it was paired on, and the two matches are two different rooms.
        assert(await(function() return ticketData(r1) ~= nil and ticketData(r1).match ~= nil and ticketData(b1) ~= nil and ticketData(b1).match ~= nil and ticketData(r2) ~= nil and ticketData(r2).match ~= nil and ticketData(b2) ~= nil and ticketData(b2).match ~= nil end, 300), "all four tickets hold their pairing")
        for _, user in ipairs({ r1, b1, r2, b2 }) do
            local match = ticketData(user).match
            assert(match.homeEpoch == 0 and match.awayEpoch == 0, "the pairing is stamped with Gushan and Zuoying at count zero, got " .. tostring(match.homeEpoch) .. "/" .. tostring(match.awayEpoch))
        end
        assert(ticketData(r1).matchKey == ticketData(b1).matchKey and ticketData(r2).matchKey == ticketData(b2).matchKey and ticketData(r1).matchKey ~= ticketData(r2).matchKey, "two matches, two rooms")
        log("[VRF][ContestE2E] QUEUED match1=" .. ticketData(r1).matchKey .. " match2=" .. ticketData(r2).matchKey .. "; wait for both results, then STEP 3")
    elseif STEP == 3 then
        local towns
        assert(await(function()
            towns = readTowns()
            return towns ~= nil and towns.gushan.owner == "RED" and towns.settled ~= nil
        end, 2000), "Gushan changed flag within 200 s")
        wait(5)
        towns = readTowns()
        assert(towns.gushan.strength == 100 and _FactionWar:EpochOf(towns, "gushan") == 1, "refilled to 100 and counted once, got " .. tostring(towns.gushan.strength) .. "/" .. tostring(_FactionWar:EpochOf(towns, "gushan")))
        assert(#towns.settled == 1, "only one match left a record, got " .. tostring(#towns.settled))
        assert(towns.zuoying.strength == 100 and towns.zuoying.owner == "RED" and towns.nanzih.strength == 100 and towns.yancheng.strength == 100 and towns.yancheng.owner == "BLUE", "no other town moved")
        assert(await(function() return idle.CurrentMapName == "yancheng" end, 300), "the idle blue player was sent to Yancheng")
        log("[VRF][ContestE2E] CAPTURE PASS flipping match=" .. tostring(towns.settled[1].k))
    elseif STEP == 4 then
        for _, user in ipairs(_UserService.UserEntities.Values) do _MatchFlow:ReturnForUser(id(user)) end
        log("[VRF][ContestE2E] RETURN issued")
    elseif STEP == 5 then
        -- Dispatched in each match room: the same result arrives a second time, with the arguments the room itself used.
        local map = _EntityService:GetEntityByPath("/maps/matchprobe")
        local battle = map:GetComponent("script.BattleSession")
        local flow = map:GetFirstChildComponentByTypeName("script.MatchedBattle", true)
        local key = _RoomService.RoomKey
        local before = readTowns()
        local status, outcome, done = nil, nil, false
        _FactionWarAttack:Settle(key, flow._T.homeTown, flow._T.awayTown, battle:ResultForProfile(battle.HomeProfile), flow._T.kind or "HUMAN", function(s, d, o) status, outcome, done = s, o, true end, flow._T.epochs)
        assert(await(function() return done end, 100), "redelivery answered")
        local after = readTowns()
        assert(status == "DUPLICATE" or status == "EXEMPT", "a repeated result is never applied again, got " .. tostring(status))
        assert(after.gushan.strength == before.gushan.strength and after.gushan.owner == before.gushan.owner and #(after.settled or {}) == #(before.settled or {}), "the towns did not move")
        for _, pair in ipairs({ { battle.HomeProfile, battle._T.deaths.PLAYER }, { battle.AwayProfile, battle._T.deaths.ENEMY } }) do
            if not _FactionWarGuard:IsGuardProfile(pair[1]) then
                local operation = _MonsterLevelStorage:Settle(pair[1], key, pair[2])
                assert(await(function() return operation.status ~= "PENDING" end, 100), "experience redelivery answered")
                assert(operation.status == "SAVED" and operation.duplicate == true, "a repeated result credits no second experience, got " .. operation.status .. "/" .. tostring(operation.duplicate))
            end
        end
        log("[VRF][ContestE2E] REDELIVER PASS " .. key .. " status=" .. tostring(status) .. " flipped=" .. tostring(outcome.flipped))
    elseif STEP == 6 then
        -- Expect: exactly one red player in Gushan (the conqueror), the other in Zuoying; both blue players and the idle one in Yancheng.
        assert(await(function()
            users = find()
            r1, b1, r2, b2, idle = users.wp2611, users.wp2612, users.wp2613, users.wp2614, users.wp2615
            return isvalid(r1) and isvalid(r2) and isvalid(b1) and isvalid(b2) and isvalid(idle)
                and ((r1.CurrentMapName == "gushan" and r2.CurrentMapName == "zuoying") or (r1.CurrentMapName == "zuoying" and r2.CurrentMapName == "gushan"))
                and b1.CurrentMapName == "yancheng" and b2.CurrentMapName == "yancheng" and idle.CurrentMapName == "yancheng"
        end, 600), "one conqueror advanced to Gushan, the other red player stayed, every blue player is in Yancheng")
        for _, user in ipairs({ r1, b1, r2, b2, idle }) do assert(await(function() return not _FactionWarAttack:IsEngaged(id(user)) end), "unlocked") end
        local towns = readTowns()
        assert(towns.gushan.owner == "RED" and towns.gushan.strength == 100, "the board is as the one flipping match left it")
        -- Experience is independent of the town result: both blue players lost their tank and both matches are in their history.
        local keys = {}
        for _, user in ipairs({ b1, b2 }) do
            local document = history(user.PlayerComponent.ProfileCode)
            local last = document.settled[#document.settled]
            assert(last ~= nil and document.monsters.monster_tank ~= nil, "the match is in the monster-level history of " .. user.PlayerComponent.ProfileCode)
            keys[last] = true
        end
        local flipping = towns.settled[1].k
        local credited = 0
        for _ in pairs(keys) do credited = credited + 1 end
        assert(keys[flipping] == true and credited == 2, "both matches, the exempt one too, were credited")
        log("[VRF][ContestE2E] LANDING1 PASS")
    elseif STEP == 7 then
        -- Round two: Gushan is blue and at 60 again. The red player who stayed in Zuoying meets the blue player who went to Yancheng.
        users = find()
        r1, b1, r2, b2 = users.wp2611, users.wp2612, users.wp2613, users.wp2614
        local red = r1.CurrentMapName == "zuoying" and r1 or r2
        local blue = b1
        local seeded = _FactionWar:InitialTowns()
        seeded.gushan.strength = 60
        local written = false
        _FactionWar:WriteTowns(seeded, function(saved) written = saved end)
        assert(await(function() return written end, 100), "Gushan reset to blue/60")
        assert(_FactionWar:Move(blue, "gushan") and await(function() return blue.CurrentMapName == "gushan" end), "the blue player went to Gushan")
        _FactionWarAttack:AttackFor(id(red), "gushan")
        assert(await(function() return _FactionWarAttack:IsEngaged(id(red)) end, 100), "red engaged")
        _FactionWarAttack:AttackFor(id(blue), "zuoying")
        assert(await(function() return _FactionWarAttack:IsEngaged(id(blue)) end, 100), "blue engaged")
        assert(await(function() return _MatchFlow:StateForUser(id(red)) ~= "QUEUED" and _MatchFlow:StateForUser(id(blue)) ~= "QUEUED" end, 300), "pair formed")
        assert(await(function() return ticketData(red) ~= nil and ticketData(red).match ~= nil end, 300), "the red ticket holds its pairing")
        assert(ticketData(red).match.awayEpoch == 0, "the pairing was stamped with Gushan at count zero")
        -- While the match is on, Gushan is taken and taken back: blue again, strength 60, counted twice.
        local retaken = _FactionWar:InitialTowns()
        retaken.gushan.strength = 60
        retaken.gushan.e = 2
        written = false
        _FactionWar:WriteTowns(retaken, function(saved) written = saved end)
        assert(await(function() return written end, 100), "Gushan rewritten as taken and taken back")
        log("[VRF][ContestE2E] ROUND 2 QUEUED red=" .. red.PlayerComponent.ProfileCode .. " blue=" .. blue.PlayerComponent.ProfileCode .. "; wait for the result, run STEP 4 inside the new match room, then STEP 8")
    elseif STEP == 8 then
        assert(await(function()
            users = find()
            r1, b1, r2, b2 = users.wp2611, users.wp2612, users.wp2613, users.wp2614
            local red = (r1.CurrentMapName == "zuoying" and r1) or (r2.CurrentMapName == "zuoying" and r2)
            return isvalid(b1) and b1.CurrentMapName == "gushan" and red ~= nil and isvalid(red)
        end, 1500), "the red player stayed in Zuoying and the blue player stayed in Gushan (its own town again)")
        local towns = readTowns()
        assert(towns.gushan.owner == "BLUE" and towns.gushan.strength == 60 and _FactionWar:EpochOf(towns, "gushan") == 2, "no strength was deducted: Gushan is still blue, 60, counted twice")
        assert(towns.zuoying.strength == 100 and towns.nanzih.strength == 100 and towns.yancheng.strength == 100, "no town lost strength")
        log("[VRF][ContestE2E] LANDING2 PASS")
    elseif STEP == 9 then
        _FactionWarGuard.WaitSeconds = 10
        local code = _DataStorageService:DeleteGlobalDataStorageAndWait(_FactionWar.TownStorageName)
        log("[VRF][ContestE2E] CLEANUP town storage deleted code=" .. tostring(code))
    end
end)
if not ok then log_error("[VRF][ContestE2E] STEP " .. tostring(STEP) .. " FAIL " .. tostring(reason)) end
