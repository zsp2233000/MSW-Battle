-- Maker end-to-end for #110 (integration): the live guard fights that the README of #106 and #107 listed as not verified. BLUE owns only its capital:
--   Nanzih RED/100, Zuoying RED/100, Gushan RED/10 (taken once), Yancheng BLUE/100. Three guard fights, in this order, on that one board:
--   CAPITAL  a RED player in Gushan attacks the ENEMY CAPITAL (Yancheng) and wins the guard fight: nothing changes (NO_CHANGE: no record, Yancheng stays BLUE/100,
--            Gushan stays RED/10) and the player is back in Gushan, where he set out
--   LOSS     the only BLUE player, in Yancheng, attacks Gushan (RED, 10: one guard win would take it) and LOSES the guard fight: both towns are unchanged, no record,
--            the player is back in Yancheng; the match is credited to him once (what his three force-killed tanks earned is logged, not asserted)
--   COUNTER  the same BLUE player attacks Gushan again and wins: "only the capital is left" counterattack. Gushan flips to BLUE and refills to 100 (counted twice),
--            the player lands in Gushan, the idle RED player in Gushan is sent to Nanzih, nothing else moves
-- THE FIGHTS ARE NOT PLAYED. Each ROOM step ends its fight by killing one side's units (ApplyResolvedDamage 99999 on every living unit of that side, in the room):
-- the result (WIN or LOSE) is forced, the settlement, the fall announcement, the sweep, the experience and the landing that follow are the normal production path.
-- A guard fight that the player wins or loses by playing, and a draw, are not covered here.
-- Joins: 2 of the 10 virtual players a Play allows (kicked players count too); nobody is kicked.
--   add_virtual_player -profile_code wp2636 -nickname CapitalRed110    (P, RED,  3 tanks, stands in Gushan)
--   add_virtual_player -profile_code wp2637 -nickname CapitalBlue110   (Q, BLUE, 3 tanks, stands in Yancheng)
-- Writes the REAL town storage (the match room reads the real one); STEP 12 deletes it. Keep the real player in formationlobby.
-- STEP 1 runs BEFORE any virtual player exists: it wipes what an earlier run left for the two profiles (a profile with a last town is placed there at login),
-- writes their factions and seeds the board. The guard clock is the real 10 s here (every other e2e parks it at 600 s); STEP 12 puts it back to 10.
-- Steps are numbered; set STEP below, dispatch, wait for the line it announces. ROOM steps run in server_instance_<matchKey> (the key is in the "QUEUED ... match=" line),
-- after "[VRF][MatchedBattle] admission started=true"; the others in server_main.
--   1 SEED      server_main, no virtual player yet: wipes the two profiles, writes their factions, seeds the board, sets the guard clock. Then add the two players and wait 14 s
--   2 SETUP     server_main, ~30 s: formations, P in Gushan, Q in Yancheng, the NPC options of the seeded board ("SETUP PASS")
--   3 QUEUE1    server_main: P -> Yancheng; the guard claims the ticket after about 10 s (a guard- match)
--   4 ROOM1     room: forces a WIN (kills the guard's units), waits for the settlement answer, returns P ("[VRF][Capital] ROOM CAPITAL ...")
--   5 CHECK1    server_main: P in Gushan, nothing settled, the capital and Gushan unchanged ("CAPITAL PASS")
--   6 QUEUE2    server_main: Q -> Gushan; the guard claims the ticket
--   7 ROOM2     room: forces a LOSS (kills Q's units), returns Q
--   8 CHECK2    server_main: Q in Yancheng, nothing settled, Gushan still RED/10, the match credited to Q once, the experience of his three killed tanks logged ("LOSS PASS")
--   9 QUEUE3    server_main: Q -> Gushan again
--   10 ROOM3    room: forces a WIN, waits until the capture is stored, returns Q
--   11 CHECK3   server_main: Gushan BLUE/100 counted twice, one record, Q in Gushan, P in Nanzih ("COUNTER PASS", then "E2E PASS")
--   12 CLEANUP  puts the guard clock back, deletes the war town storage and the two profiles' keys
-- Expected [VRF] lines (read with logs): see tests/README.md, "War integration (#110)".
local STEP = 1
local PREFIX = "[VRF][Capital] "
local P_PROFILE, Q_PROFILE = "wp2636", "wp2637"
local ROOM_PLAN = { [4] = "WIN", [7] = "LOSE", [10] = "WIN" }
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
    assert(towns ~= nil, "the town document is readable")
    return towns
end
local function readFaction(profile)
    local faction, done = nil, false
    _FactionWar:ReadFaction(profile, function(result) faction, done = result, true end)
    assert(await(function() return done end, 100), "faction read")
    return faction
end
local function history(profile)
    local document, code, done = nil, nil, false
    _MonsterLevelStorage:Read(profile, function(c, d) code, document, done = c, d, true end)
    assert(await(function() return done end, 100) and code == 0, "monster levels read " .. profile)
    return document
end
local function credited(document, key)
    local count = 0
    for _, matchId in ipairs(document.settled or {}) do if matchId == key then count = count + 1 end end
    return count
end
local function recordsOf(towns, key)
    local n = 0
    for _, entry in ipairs(towns.settled or {}) do
        if (type(entry) == "table" and entry.k == key) or entry == key then n = n + 1 end
    end
    return n
end
local function wipe(profile)
    local storage = _DataStorageService:GetUserDataStorage(profile)
    storage:DeleteAndWait(_FactionWar.FactionKey)
    storage:DeleteAndWait(_FactionWar.TownKey)
    storage:DeleteAndWait(_MonsterLevelStorage.StorageKey)
    storage:DeleteAndWait(_FormationHandoff.StorageKey)
end
local function board(towns)
    local parts = {}
    for _, town in ipairs(_FactionWar.TownOrder) do
        table.insert(parts, town .. "=" .. towns[town].owner .. "/" .. tostring(towns[town].strength) .. "/e" .. tostring(_FactionWar:EpochOf(towns, town)))
    end
    return table.concat(parts, " ")
end
local function names(list)
    local parts = {}
    for _, option in ipairs(list) do table.insert(parts, option.town .. (option.capital and "(capital)" or "")) end
    if #parts == 0 then return "nothing" end
    return table.concat(parts, ",")
end
-- The ticket of a player after the claim: the match key it carries (a closed ticket on storage keeps it too).
local function matchKeyOf(profile, userId)
    local ticket = _MatchFlow._T.records[userId]
    if ticket ~= nil and ticket.data ~= nil and ticket.data.matchKey ~= nil and ticket.data.matchKey ~= "" then return ticket.data.matchKey end
    local stored = _FormationHandoff:Read(profile)
    return stored ~= nil and stored.data ~= nil and stored.data.matchKey or ""
end
local function queue(label, user, target)
    local userId, profile = id(user), user.PlayerComponent.ProfileCode
    local before = readTowns()
    _FactionWarAttack:AttackFor(userId, target)
    assert(await(function() return _MatchFlow:StateForUser(userId) == "QUEUED" end, 100), "queued")
    local queuedAt = os.clock()
    assert(_MatchFlow._T.guardTimers[userId] ~= nil, "the guard clock is running")
    assert(await(function() return _MatchFlow:StateForUser(userId) ~= "QUEUED" end, 200), "the guard claimed the ticket")
    local waited = os.clock() - queuedAt
    assert(waited > 8 and waited < 14, "the guard comes after about ten seconds, took " .. tostring(waited))
    local key = ""
    assert(await(function()
        key = matchKeyOf(profile, userId)
        return key ~= ""
    end, 300), "the pairing is sealed")
    assert(string.sub(key, 1, 6) == "guard-", "this is a guard match, found " .. key)
    log(PREFIX .. "QUEUED " .. label .. " match=" .. key .. " after " .. tostring(waited) .. " s on " .. board(before) .. "; wait for [VRF][MatchedBattle] admission started=true, then run the ROOM step in the room")
end
local ok, reason = pcall(function()
    local users = find()
    local p, q = users[P_PROFILE], users[Q_PROFILE]
    if STEP == 1 then
        assert(p == nil and q == nil, "no virtual player may be connected yet: stop, play, and run STEP 1 before the adds")
        for _, profile in ipairs({ P_PROFILE, Q_PROFILE }) do wipe(profile) end
        for profile, faction in pairs({ [P_PROFILE] = "RED", [Q_PROFILE] = "BLUE" }) do
            local saved = false
            _FormationStorage:Write(profile, _FactionWar.FactionKey, "", faction, function(code) saved = code == 0 end)
            assert(await(function() return saved end, 100), "faction written for " .. profile)
        end
        -- BLUE owns only its capital; Gushan is RED at 10 (taken once), so one guard win takes it back.
        local towns = _FactionWar:InitialTowns()
        towns.gushan.owner = "RED"
        towns.gushan.strength = 10
        towns.gushan.e = 1
        local written = false
        _FactionWar:WriteTowns(towns, function(saved) written = saved end)
        assert(await(function() return written end, 100), "the board is seeded")
        _FactionWarGuard.WaitSeconds = 10
        log("[VRF][Capital] SEED " .. board(towns) .. "; now add the two virtual players (see the header), wait 14 s, then STEP 2")
    elseif STEP == 2 then
        assert(isvalid(p) and isvalid(q), "both virtual players are connected")
        local function setup(user)
            local record = _FormationService:GetSession(id(user))
            if not record.initialized then _FormationService:Load(record) end
            assert(await(function() return record.initialized and not record.pending end), "formation loaded")
            local units = {}
            for index = 1, 3 do units[index] = { monsterId = "monster_tank", x = -3.25 - (index - 1) * 0.75, y = -1.25 } end
            local slotId = record.editSlot
            _FormationService:SaveForUser(id(user), units, slotId, record.saved.slots[tostring(slotId)].revision, _UtilLogic:NewGuid())
            assert(await(function() return not record.pending and #record.saved.slots[tostring(slotId)].units == #units end), "save confirmed")
            _FormationService:ActivateForUser(id(user), slotId, record.saved.slots[tostring(slotId)].revision)
            assert(await(function() return not record.pending and record.saved.activeSlot == slotId end), "activate confirmed")
        end
        setup(p)
        setup(q)
        assert(readFaction(P_PROFILE) == "RED" and readFaction(Q_PROFILE) == "BLUE", "the factions are stored")
        assert(_FactionWar:Move(p, "gushan") and _FactionWar:Move(q, "yancheng"), "moves dispatched")
        assert(await(function() return p.CurrentMapName == "gushan" and q.CurrentMapName == "yancheng" end), "players in their towns")
        local towns = readTowns()
        assert(towns.gushan.owner == "RED" and towns.gushan.strength == 10 and _FactionWar:EpochOf(towns, "gushan") == 1, "Gushan is RED at 10, found " .. board(towns))
        assert(towns.yancheng.owner == "BLUE" and towns.nanzih.owner == "RED" and towns.zuoying.owner == "RED", "BLUE owns only its capital, found " .. board(towns))
        -- The NPC of the seeded board: the RED player faces the enemy capital, the BLUE player faces Gushan.
        local red = _FactionWarAttack:Targets("gushan", "RED", towns)
        local blue = _FactionWarAttack:Targets("yancheng", "BLUE", towns)
        assert(#red == 1 and red[1].town == "yancheng" and red[1].capital == true, "P is offered the enemy capital, found " .. names(red))
        assert(#blue == 1 and blue[1].town == "gushan" and blue[1].capital == false, "Q is offered Gushan, found " .. names(blue))
        assert(_FactionWarGuard.WaitSeconds == 10, "the guard clock is the real 10 s")
        log("[VRF][Capital] SETUP PASS " .. board(towns))
    elseif STEP == 3 then
        assert(isvalid(p), "P is connected")
        queue("CAPITAL P gushan -> yancheng", p, "yancheng")
    elseif STEP == 6 then
        assert(isvalid(q), "Q is connected")
        queue("LOSS Q yancheng -> gushan", q, "gushan")
    elseif STEP == 9 then
        assert(isvalid(q), "Q is connected")
        queue("COUNTER Q yancheng -> gushan", q, "gushan")
    elseif STEP == 4 or STEP == 7 or STEP == 10 then
        -- In the match room: end the guard fight by force, then let the production settlement and return run.
        local plan = ROOM_PLAN[STEP]
        local map = _EntityService:GetEntityByPath("/maps/matchprobe")
        local battle = map:GetComponent("script.BattleSession")
        assert(await(function() return battle:IsBattleActive() end, 300), "the battle is on, phase " .. tostring(battle.Phase))
        local human = nil
        for _, user in ipairs(_UserService.UserEntities.Values) do
            if isvalid(user) and isvalid(user.PlayerComponent) then human = user end
        end
        assert(isvalid(human), "the human is in the room")
        local profile, userId, key = human.PlayerComponent.ProfileCode, human.PlayerComponent.UserId, _RoomService.RoomKey
        assert(battle.HomeProfile == profile and _FactionWarGuard:IsGuardProfile(battle.AwayProfile), "a guard fight: the human at home, the guard away")
        -- The human is "PLAYER", the guard "ENEMY": a forced WIN kills the guard's units, a forced LOSS kills the human's.
        local doomed = plan == "WIN" and "ENEMY" or "PLAYER"
        local units = map:GetChildComponentsByTypeName("BattleUnit", true)
        if #units == 0 then units = map:GetChildComponentsByTypeName("script.BattleUnit", true) end
        local killed = 0
        for _, unit in ipairs(units) do
            if unit.Faction == doomed and unit:IsAlive() then
                unit:ApplyResolvedDamage(99999, nil, false, "", 0, 0)
                killed = killed + 1
            end
        end
        assert(killed > 0, "found units of " .. doomed .. " to kill")
        assert(await(function() return battle.Phase == "RESULT" end, 300), "the fight reached its result, phase " .. tostring(battle.Phase))
        assert(battle:ResultForProfile(profile) == plan, "the forced result is " .. plan .. ", found " .. battle:ResultForProfile(profile))
        local towns = readTowns()
        if STEP == 10 then
            assert(await(function()
                towns = readTowns()
                return recordsOf(towns, key) == 1
            end, 300), "the capture is stored exactly once")
        else
            -- A capital and a loss leave no record: give the settlement time to answer NO_CHANGE, then look.
            wait(4)
            towns = readTowns()
            assert(recordsOf(towns, key) == 0, "no record is stored")
        end
        log(PREFIX .. "ROOM " .. (STEP == 4 and "CAPITAL" or (STEP == 7 and "LOSS" or "COUNTER")) .. " forced " .. plan .. " killed=" .. tostring(killed) .. " " .. doomed .. " units match=" .. key .. " board " .. board(towns))
        _MatchFlow:ReturnForUser(userId)
        log(PREFIX .. "RETURN issued for " .. profile .. "; run the CHECK step in server_main")
    elseif STEP == 5 then
        assert(await(function()
            p = find()[P_PROFILE]
            return isvalid(p) and p.CurrentMapName == "gushan"
        end, 400), "P is back in Gushan, where he set out")
        assert(await(function() return not _FactionWarAttack:IsEngaged(id(p)) end, 100), "P is unlocked")
        local towns = readTowns()
        assert(towns.yancheng.owner == "BLUE" and towns.yancheng.strength == 100 and _FactionWar:EpochOf(towns, "yancheng") == 0, "the enemy capital keeps its owner and its full strength, found " .. board(towns))
        assert(towns.gushan.owner == "RED" and towns.gushan.strength == 10 and _FactionWar:EpochOf(towns, "gushan") == 1, "Gushan is untouched, found " .. board(towns))
        assert(#(towns.settled or {}) == 0, "a win over a capital leaves no settlement record")
        local key = matchKeyOf(P_PROFILE, id(p))
        assert(key ~= "", "the closed ticket remembers the match")
        assert(await(function() return credited(history(P_PROFILE), key) == 1 end, 100), "the guard fight is credited to P exactly once")
        log("[VRF][Capital] CAPITAL PASS match=" .. key .. " " .. board(towns))
    elseif STEP == 8 then
        assert(await(function()
            q = find()[Q_PROFILE]
            return isvalid(q) and q.CurrentMapName == "yancheng"
        end, 400), "Q is back in Yancheng, where he set out")
        assert(await(function() return not _FactionWarAttack:IsEngaged(id(q)) end, 100), "Q is unlocked")
        local towns = readTowns()
        assert(towns.gushan.owner == "RED" and towns.gushan.strength == 10 and _FactionWar:EpochOf(towns, "gushan") == 1, "a lost guard fight changes nothing: Gushan, found " .. board(towns))
        assert(towns.yancheng.owner == "BLUE" and towns.yancheng.strength == 100, "and nothing at Yancheng, found " .. board(towns))
        assert(#(towns.settled or {}) == 0, "no settlement record")
        assert(find()[P_PROFILE].CurrentMapName == "gushan", "P was not moved: nothing fell")
        local key = matchKeyOf(Q_PROFILE, id(q))
        assert(key ~= "", "the closed ticket remembers the match")
        local document
        assert(await(function()
            document = history(Q_PROFILE)
            return credited(document, key) == 1
        end, 100), "the lost fight is credited to Q exactly once")
        -- The three tanks were killed by force, not in combat: whether the battle counts such a death for the experience is an observation here, not a verdict.
        local tank = document.monsters.monster_tank ~= nil and _HttpService:JSONEncode(document.monsters.monster_tank) or "none"
        log("[VRF][Capital] LOSS PASS match=" .. key .. " " .. board(towns) .. " experience of the three killed tanks: monster_tank=" .. tank)
    elseif STEP == 11 then
        assert(await(function()
            users = find()
            p, q = users[P_PROFILE], users[Q_PROFILE]
            return isvalid(p) and isvalid(q) and q.CurrentMapName == "gushan" and p.CurrentMapName == "nanzih"
        end, 600), "Q (the conqueror) is in Gushan and the idle RED player was sent to Nanzih")
        for _, user in ipairs({ p, q }) do assert(await(function() return not _FactionWarAttack:IsEngaged(id(user)) end, 100), "unlocked") end
        local towns = readTowns()
        assert(towns.gushan.owner == "BLUE" and towns.gushan.strength == 100 and _FactionWar:EpochOf(towns, "gushan") == 2, "Gushan flipped to BLUE, refilled to 100 and counted twice, found " .. board(towns))
        assert(towns.yancheng.owner == "BLUE" and towns.yancheng.strength == 100 and towns.nanzih.owner == "RED" and towns.nanzih.strength == 100 and towns.zuoying.owner == "RED" and towns.zuoying.strength == 100, "no other town moved, found " .. board(towns))
        assert(#towns.settled == 1, "one settlement record, found " .. tostring(#towns.settled))
        local record = towns.settled[1]
        assert(record.w == "yancheng" and record.l == "gushan" and record.o == "BLUE" and record.s == 100, "the record says BLUE took Gushan from its capital and refilled it")
        local key = matchKeyOf(Q_PROFILE, id(q))
        assert(record.k == key, "the record belongs to the last match of Q")
        assert(await(function() return credited(history(Q_PROFILE), key) == 1 end, 100), "the counterattack is credited to Q exactly once")
        -- The new front: RED at Zuoying facing Gushan, BLUE at Gushan facing Zuoying.
        assert(_FactionWar:FindFrontline("RED", towns) == "zuoying" and _FactionWar:FindFrontline("BLUE", towns) == "gushan", "new players land on the new front")
        log("[VRF][Capital] COUNTER PASS match=" .. key .. " " .. board(towns))
        log("[VRF][Capital] E2E PASS capital win = no change, guard loss = no change, counterattack from the only capital = flip + 100 + landing")
    elseif STEP == 12 then
        _FactionWarGuard.WaitSeconds = 10
        -- A remember-write may still be in flight for a player who just moved.
        wait(2)
        for _, profile in ipairs({ P_PROFILE, Q_PROFILE }) do wipe(profile) end
        local code = _DataStorageService:DeleteGlobalDataStorageAndWait(_FactionWar.TownStorageName)
        log("[VRF][Capital] CLEANUP town storage deleted code=" .. tostring(code) .. ", the two profiles' keys wiped, guard clock back to 10 s")
    end
end)
if not ok then log_error("[VRF][Capital] STEP " .. tostring(STEP) .. " FAIL " .. tostring(reason)) end
