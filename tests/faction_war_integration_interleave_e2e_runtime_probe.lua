-- Maker end-to-end for #110 (integration): the human-versus-guard timeout race. Ticket A (RED, Zuoying, attacks Gushan) starts its ten-second guard clock at t0.
-- Ticket B (BLUE, Gushan, attacks Zuoying: the opposite direction) queues at a measured offset around that clock, one trial per step group:
--   trial 1  B queues about 9.5 s after t0   (before the clock: the two humans pair, A's clock is cleared and no guard claim is made)
--   trial 2  B queues about 9.9 s after t0   (just before: normally a human pairing; either outcome is allowed inside the band below)
--   trial 3  B queues about 10.1 s after t0  (just after: A's claim has fired, A fights the guard and B is left waiting)
--   trial 4  B queues about 10.5 s after t0 while A's claim is IN FLIGHT: the fault adapter makes every cancel take 2 s, and the guard's withdrawal is such a cancel
-- The realized offset is measured, not assumed: B.ticket.guardStarted - A.ticket.guardStarted (both are set when the queue accepted the ticket); SETUP measures how long
-- AttackFor takes to reach the queue and B is called that much earlier. Offsets below 9.7 s must pair humans and offsets above 10.3 s must be a guard fight; inside the
-- band either outcome is allowed. Every trial asserts, whatever the outcome: exactly one match key per ticket (both tickets sampled every 50 ms until the pairing is sealed),
-- exactly one match room, a ticket never in two rooms, the guard claim dropped when a human match stands (A's and B's clocks cleared, no guard- key appears, still none
-- 1.5 s after the clock would have fired), B never pulled into A's guard fight (B keeps waiting and is cancelled in place), the result settled once (at most one record,
-- strength arithmetic against the board before the trial) and each profile credited with its experience once.
-- A trial that pairs humans plays a WHOLE FIGHT (3 tanks against 1 tank, about a minute: FORCE.HUMAN is false in the ROOM steps); a guard fight is FORCED to a RED win (the
-- guard's units are killed in the room) so it takes seconds. Set FORCE.HUMAN to true in the ROOM steps to force the human fights too.
-- NOT reachable in Maker: the local queue confirms every cancel and cannot pair a ticket that is being claimed (a claimed ticket is not "live"), so the deferred-human-result
-- path of the claim ("[VRF][Guard] human result deferred", "[VRF][Guard] a human match stands") and the native service answering AlreadyMatched (ADR 0011) need two real accounts
-- at the ten-second mark; they are rows of docs/Issue-110-War-Acceptance.md.
-- Joins: 2 of the 10 virtual players a Play allows (kicked players count too); nobody is kicked, both players are reused by all four trials.
--   add_virtual_player -profile_code wp2638 -nickname RaceRed110    (A, RED,  3 tanks, stands in Zuoying)
--   add_virtual_player -profile_code wp2639 -nickname RaceBlue110   (B, BLUE, 1 tank,  stands in Gushan)
-- Writes the REAL town storage (the match room reads the real one; Gushan starts BLUE at 100 and cannot fall in four trials); STEP 15 deletes it. Keep the real player in formationlobby.
-- STEP 1 runs BEFORE any virtual player exists: it wipes what an earlier run left for the two profiles (a profile with a last town is placed there at login), writes their factions
-- and seeds the board. The guard clock is the real 10 s here (every other e2e parks it at 600 s); STEP 15 puts it back to 10.
-- Steps are numbered; set STEP below, dispatch, wait for the line it announces. ROOM steps run in server_instance_<matchKey> (the key is in the "TRIAL n" line), after
-- "[VRF][MatchedBattle] admission started=true"; the others in server_main.
--   1 SEED      server_main, no virtual player yet: wipes the two profiles, writes their factions, seeds the board. Then add the two players and wait 14 s
--   2 SETUP     server_main, ~40 s: formations, A in Zuoying, B in Gushan, the guard clock set to 10 s, the AttackFor latency measured twice ("SETUP PASS")
--   3 TRIAL1    server_main, ~25 s: the race at 9.5 s; asserts the pairing and prints "TRIAL 1 ... outcome="
--   4 ROOM1     room: ends or waits for the fight, waits for the settlement, returns everyone in the room
--   5 CHECK1    server_main: both back in their towns, no room left, settled once, experience once ("RACE1 PASS")
--   6 TRIAL2    server_main: the race at 9.9 s
--   7 ROOM2     room
--   8 CHECK2    server_main ("RACE2 PASS")
--   9 TRIAL3    server_main: the race at 10.1 s
--   10 ROOM3    room
--   11 CHECK3   server_main ("RACE3 PASS")
--   12 TRIAL4   server_main: the race at 10.5 s with the guard's claim in flight (asserts that the claim really was in flight)
--   13 ROOM4    room
--   14 CHECK4   server_main ("RACE4 PASS", the table of the four trials, "E2E PASS")
--   15 CLEANUP  puts the guard clock and the adapters back, deletes the war town storage and the two profiles' keys
-- Expected [VRF] lines (read with logs): see tests/README.md, "War integration (#110)".
local STEP = 1
local PREFIX = "[VRF][Interleave] "
local A_PROFILE, B_PROFILE = "wp2638", "wp2639"
local TRIALS = {
    [3] = { n = 1, offset = 9.5, delay = 0 },
    [6] = { n = 2, offset = 9.9, delay = 0 },
    [9] = { n = 3, offset = 10.1, delay = 0 },
    [12] = { n = 4, offset = 10.5, delay = 2 },
}
local CHECKS = { [5] = 1, [8] = 2, [11] = 3, [14] = 4 }
local PASS = { [5] = "[VRF][Interleave] RACE1 PASS", [8] = "[VRF][Interleave] RACE2 PASS", [11] = "[VRF][Interleave] RACE3 PASS", [14] = "[VRF][Interleave] RACE4 PASS" }
local FORCE = { HUMAN = false, GUARD = true }
local function await(predicate, tries) for _ = 1, tries or 300 do if predicate() then return true end wait(0.1) end return false end
-- A finer wait for the race itself: polls every 20 ms for at most the given seconds.
local function waitFor(predicate, seconds)
    local waited = 0
    while waited < seconds do
        if predicate() then return true end
        wait(0.02)
        waited = waited + 0.02
    end
    return predicate()
end
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
local function history(profile)
    local document, code, done = nil, nil, false
    _MonsterLevelStorage:Read(profile, function(c, d) code, document, done = c, d, true end)
    assert(await(function() return done end, 100) and code == 0, "monster levels read " .. profile)
    return document
end
local function credited(profile, key)
    local count = 0
    for _, matchId in ipairs(history(profile).settled or {}) do if matchId == key then count = count + 1 end end
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
local function liveRooms()
    local keys = {}
    for _, room in ipairs(_RoomService.InstanceRooms.Values) do
        if room ~= nil and room:IsValid() then table.insert(keys, room.InstanceKey) end
    end
    return #keys, keys
end
local function ticketOf(userId) return _MatchFlow._T.records[userId] end
local function keyOf(userId)
    local ticket = ticketOf(userId)
    return ticket ~= nil and ticket.data ~= nil and ticket.data.matchKey or ""
end
local function count(set)
    local n = 0
    for _ in pairs(set) do n = n + 1 end
    return n
end
local function isGuardKey(key) return string.sub(key, 1, 6) == "guard-" end
-- How long AttackFor takes from the call until the queue accepted the ticket (the moment the ticket's clock starts); the ticket is cancelled again.
local function enqueueLatency(user, target)
    local userId = id(user)
    local started = DateTime.UtcNow.Elapsed
    _FactionWarAttack:AttackFor(userId, target)
    assert(waitFor(function()
        local ticket = ticketOf(userId)
        return ticket ~= nil and ticket.guardStarted ~= nil
    end, 10), "the ticket reached the queue")
    local took = DateTime.UtcNow.Elapsed - started
    _MatchFlow:CancelForUser(userId)
    assert(await(function() return _MatchFlow:StateForUser(userId) == "IDLE" and not _FactionWarAttack:IsEngaged(userId) end, 100), "cancelled again")
    return took
end
local ok, reason = pcall(function()
    local users = find()
    local a, b = users[A_PROFILE], users[B_PROFILE]
    if STEP == 1 then
        assert(a == nil and b == nil, "no virtual player may be connected yet: stop, play, and run STEP 1 before the adds")
        for _, profile in ipairs({ A_PROFILE, B_PROFILE }) do wipe(profile) end
        for profile, faction in pairs({ [A_PROFILE] = "RED", [B_PROFILE] = "BLUE" }) do
            local saved = false
            _FormationStorage:Write(profile, _FactionWar.FactionKey, "", faction, function(code) saved = code == 0 end)
            assert(await(function() return saved end, 100), "faction written for " .. profile)
        end
        local towns = _FactionWar:InitialTowns()
        local written = false
        _FactionWar:WriteTowns(towns, function(saved) written = saved end)
        assert(await(function() return written end, 100), "the board is seeded")
        _FactionWar._T.raceRows = {}
        log("[VRF][Interleave] SEED " .. board(towns) .. "; now add the two virtual players (see the header), wait 14 s, then STEP 2")
    elseif STEP == 2 then
        assert(isvalid(a) and isvalid(b), "both virtual players are connected")
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
        assert(_FactionWar:Move(a, "zuoying") and _FactionWar:Move(b, "gushan"), "moves dispatched")
        assert(await(function() return a.CurrentMapName == "zuoying" and b.CurrentMapName == "gushan" end), "players in their towns")
        _FactionWarGuard.WaitSeconds = 10
        _MatchFaults:Remove()
        -- B's tickets are the ones that have to arrive on time: measure how long AttackFor takes to reach the queue.
        local first = enqueueLatency(b, "zuoying")
        local second = enqueueLatency(b, "zuoying")
        local latency = math.max(first, second) + 50
        assert(latency < 3000, "AttackFor reaches the queue within 3 s, took " .. tostring(latency) .. " ms")
        _FactionWar._T.raceLatency = latency
        local towns = readTowns()
        assert(towns.gushan.owner == "BLUE" and towns.gushan.strength == 100 and towns.zuoying.strength == 100, "the board is the initial one, found " .. board(towns))
        log("[VRF][Interleave] SETUP PASS latency=" .. tostring(latency) .. " ms (" .. tostring(first) .. ", " .. tostring(second) .. ") " .. board(towns))
    elseif STEP == 3 or STEP == 6 or STEP == 9 or STEP == 12 then
        local trial = TRIALS[STEP]
        assert(isvalid(a) and isvalid(b), "both virtual players are connected")
        assert(_FactionWar._T.raceLatency ~= nil, "STEP 2 measured the queue latency")
        -- A user entity loses its PlayerComponent once it is transferred to a match room, so the ids are read first.
        local idA, idB = id(a), id(b)
        assert(a.CurrentMapName == "zuoying" and b.CurrentMapName == "gushan", "A stands in Zuoying and B in Gushan")
        assert(await(function()
            return _MatchFlow:StateForUser(idA) == "IDLE" and _MatchFlow:StateForUser(idB) == "IDLE" and not _FactionWarAttack:IsEngaged(idA) and not _FactionWarAttack:IsEngaged(idB)
        end, 150), "both are idle and unlocked")
        assert(await(function() return (liveRooms()) == 0 end, 150), "no match room is left from before")
        local before = readTowns()
        if trial.delay > 0 then _MatchFaults:ConfigureCancel(0, trial.delay) else _MatchFaults:Remove() end
        -- A queues; its clock starts when the queue accepts the ticket. That moment is t0.
        _FactionWarAttack:AttackFor(idA, "gushan")
        local ticketA = nil
        assert(waitFor(function()
            ticketA = ticketOf(idA)
            return ticketA ~= nil and ticketA.guardStarted ~= nil
        end, 10), "A's guard clock started")
        local t0 = ticketA.guardStarted
        -- B is called early by the time AttackFor needs to reach the queue, so that its ticket arrives at about the offset.
        local callAt = t0 + trial.offset * 1000 - _FactionWar._T.raceLatency
        while DateTime.UtcNow.Elapsed < callAt do wait(0.02) end
        local calledAt = (DateTime.UtcNow.Elapsed - t0) / 1000
        _FactionWarAttack:AttackFor(idB, "zuoying")
        local ticketB = nil
        assert(waitFor(function()
            ticketB = ticketOf(idB)
            return ticketB ~= nil and ticketB.guardStarted ~= nil
        end, 10), "B's ticket reached the queue")
        local realized = (ticketB.guardStarted - t0) / 1000
        local inClaim = ticketA.guarding == true
        if trial.delay > 0 then
            assert(inClaim, "A's guard claim was in flight when B queued (realized " .. tostring(realized) .. " s); if this fails the race was not exercised: run the trial again")
        end
        local expected = realized < 9.7 and "HUMAN" or (realized > 10.3 and "GUARD" or "EITHER")
        -- Sample both tickets until A's pairing is sealed: every match key either ticket ever carries.
        local seen = { A = {}, B = {} }
        local function sample()
            for label, userId in pairs({ A = idA, B = idB }) do
                local key = keyOf(userId)
                if key ~= "" then seen[label][key] = true end
                local ticket = ticketOf(userId)
                if ticket ~= nil and ticket.guardPairing ~= nil then seen[label][ticket.guardPairing.key] = true end
            end
        end
        local deadline = os.clock() + 25
        while os.clock() < deadline do
            sample()
            local keyA = keyOf(idA)
            if keyA ~= "" and (isGuardKey(keyA) or keyOf(idB) == keyA) then break end
            wait(0.05)
        end
        sample()
        local keyA, keyB = keyOf(idA), keyOf(idB)
        assert(keyA ~= "", "A's ticket was matched within 25 s")
        local outcome = isGuardKey(keyA) and "GUARD" or "HUMAN"
        assert(expected == "EITHER" or outcome == expected, "a ticket queued " .. tostring(realized) .. " s after A's clock must give a " .. expected .. " match, found " .. outcome)
        assert(count(seen.A) == 1, "A's ticket carried exactly one match key, found " .. tostring(count(seen.A)))
        assert(count(seen.B) <= 1, "B's ticket carried at most one match key, found " .. tostring(count(seen.B)))
        if outcome == "HUMAN" then
            assert(keyB == keyA, "the two humans share one match key")
            assert(not _MatchFlow:IsGuard(ticketA) and not _MatchFlow:IsGuard(ticketB) and ticketA.guardPairing == nil, "no guard pairing was made for a human match")
            assert(_MatchFlow._T.guardTimers[idA] == nil and _MatchFlow._T.guardTimers[idB] == nil, "the guard claim is dropped: both clocks are cleared")
        else
            assert(_MatchFlow:IsGuard(ticketA) and ticketA.guardPairing ~= nil, "A holds the guard pairing")
            assert(keyB == "" and count(seen.B) == 0, "B was not pulled into A's guard fight: it carries no match key")
            assert(ticketB.data ~= nil and ticketB.data.state == "QUEUED", "B keeps waiting for a human")
            assert(_MatchFlow._T.guardTimers[idB] ~= nil, "B's own clock is running")
        end
        -- One match, one room; the late guard claim of a human match never shows.
        local rooms, roomKeys
        assert(await(function()
            rooms, roomKeys = liveRooms()
            return rooms >= 1
        end, 200), "A's match room exists")
        assert(rooms == 1 and roomKeys[1] == keyA, "exactly one match room, the one of A's key, found " .. tostring(rooms))
        local quietUntil = t0 + 11500
        while DateTime.UtcNow.Elapsed < quietUntil do wait(0.05) end
        sample()
        -- A player who was moved into the match room is no longer in the static room's records (its coordinator forgets the ticket on the move), so an empty key is fine here:
        -- what must hold is that no other key was ever carried and, below, that no guard room appeared.
        assert(count(seen.A) == 1 and (keyOf(idA) == keyA or keyOf(idA) == ""), "A's match did not change after the clock would have fired")
        assert((liveRooms()) == 1, "still one room")
        if outcome == "GUARD" then
            -- B must not be in any room; it cancels in place.
            assert(keyOf(idB) == "" and _MatchFlow:StateForUser(idB) == "QUEUED", "B is still waiting and is in no room")
            _MatchFlow:CancelForUser(idB)
            assert(await(function() return _MatchFlow:StateForUser(idB) == "IDLE" and not _FactionWarAttack:IsEngaged(idB) end, 150), "B cancelled in place")
            assert(_MatchFlow._T.guardTimers[idB] == nil, "cancelling stops B's guard clock")
            assert(b.CurrentMapName == "gushan", "B did not move")
        end
        _MatchFaults:Remove()
        _FactionWar._T.race = { n = trial.n, key = keyA, kind = outcome, before = before, realized = realized, calledAt = calledAt, expected = expected, inClaim = inClaim }
        log(PREFIX .. "TRIAL " .. tostring(trial.n) .. " target=" .. tostring(trial.offset) .. " called=" .. string.format("%.2f", calledAt) .. " realized=" .. string.format("%.2f", realized) .. " expected=" .. expected
            .. " outcome=" .. outcome .. " inClaim=" .. tostring(inClaim) .. " rooms=1 key=" .. keyA .. " before " .. board(before)
            .. "; wait for [VRF][MatchedBattle] admission started=true, then run the ROOM step in server_instance_" .. keyA)
    elseif STEP == 4 or STEP == 7 or STEP == 10 or STEP == 13 then
        -- In the match room: let the fight end (a human fight is played, a guard fight is forced to a RED win), wait for the settlement, return everyone.
        local map = _EntityService:GetEntityByPath("/maps/matchprobe")
        local battle = map:GetComponent("script.BattleSession")
        local flow = map:GetFirstChildComponentByTypeName("script.MatchedBattle", true)
        assert(await(function() return battle:IsBattleActive() end, 400), "the battle is on, phase " .. tostring(battle.Phase))
        local key, kind = _RoomService.RoomKey, flow._T.kind
        local inRoom = find()
        assert(inRoom[A_PROFILE] ~= nil, "A is in the room")
        if kind == "GUARD" then
            assert(inRoom[B_PROFILE] == nil, "B is not in a guard room")
        else
            assert(kind == "HUMAN" and inRoom[B_PROFILE] ~= nil, "both humans are in a human room")
        end
        local forced = FORCE[kind] == true
        if forced then
            -- A is the home side (PLAYER) in a guard fight and the first ticket (home) of a human pairing; kill the other side so that RED wins.
            local doomed = battle.HomeProfile == A_PROFILE and "ENEMY" or "PLAYER"
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
        end
        assert(await(function() return battle.Phase == "RESULT" end, forced and 300 or 4000), "the fight reached its result, phase " .. tostring(battle.Phase))
        local result = battle:ResultForProfile(A_PROFILE)
        -- A decisive result is settled once and leaves one record; a draw leaves none.
        local towns = readTowns()
        if result == "DRAW" then
            wait(4)
            towns = readTowns()
            assert(recordsOf(towns, key) == 0, "a draw leaves no record")
        else
            assert(await(function()
                towns = readTowns()
                return recordsOf(towns, key) == 1
            end, 300), "the result was settled exactly once (one record)")
            wait(3)
            towns = readTowns()
            assert(recordsOf(towns, key) == 1, "and it is still one record after the room had time to publish again")
        end
        log(PREFIX .. "ROOM kind=" .. kind .. " forced=" .. tostring(forced) .. " result=" .. result .. " key=" .. key .. " home=" .. battle.HomeProfile .. " board " .. board(towns))
        for _, user in pairs(inRoom) do _MatchFlow:ReturnForUser(id(user)) end
        log(PREFIX .. "RETURN issued; run the CHECK step in server_main")
    elseif STEP == 5 or STEP == 8 or STEP == 11 or STEP == 14 then
        local n = CHECKS[STEP]
        local race = _FactionWar._T.race
        assert(race ~= nil and race.n == n, "the TRIAL step of trial " .. tostring(n) .. " ran first")
        assert(await(function()
            users = find()
            a, b = users[A_PROFILE], users[B_PROFILE]
            return isvalid(a) and isvalid(b) and a.CurrentMapName == "zuoying" and b.CurrentMapName == "gushan"
        end, 600), "both are back in their own towns")
        local idA, idB = id(a), id(b)
        assert(await(function() return _MatchFlow:StateForUser(idA) == "IDLE" and _MatchFlow:StateForUser(idB) == "IDLE" and not _FactionWarAttack:IsEngaged(idA) and not _FactionWarAttack:IsEngaged(idB) end, 150), "both are idle and unlocked")
        assert(await(function() return (liveRooms()) == 0 end, 150), "the match room was reclaimed: no room is left")
        local towns = readTowns()
        local records = recordsOf(towns, race.key)
        assert(records <= 1, "the result is settled once, found " .. tostring(records) .. " records")
        local amount = race.kind == "GUARD" and 10 or 20
        local changed = 0
        for _, town in ipairs(_FactionWar.TownOrder) do
            if towns[town].strength ~= race.before[town].strength or towns[town].owner ~= race.before[town].owner then changed = changed + 1 end
        end
        if records == 1 then
            local record = nil
            for _, entry in ipairs(towns.settled) do if type(entry) == "table" and entry.k == race.key then record = entry end end
            assert(record ~= nil and record.o == "", "the record belongs to the match and nobody flipped a town")
            assert(towns[record.l].strength == race.before[record.l].strength - amount, record.l .. " lost exactly " .. tostring(amount) .. ": " .. tostring(race.before[record.l].strength) .. " -> " .. tostring(towns[record.l].strength))
            assert(changed == 1, "only the loser's town changed, found " .. tostring(changed))
        else
            assert(changed == 0, "no record means no town changed, found " .. tostring(changed))
        end
        -- Experience: A fought in every trial; B only in a human fight.
        assert(await(function() return credited(A_PROFILE, race.key) == 1 end, 100), "A's match is credited exactly once")
        if race.kind == "HUMAN" then
            assert(await(function() return credited(B_PROFILE, race.key) == 1 end, 100), "B's match is credited exactly once")
        else
            assert(credited(B_PROFILE, race.key) == 0, "B was not in the guard fight and earns nothing from it")
        end
        table.insert(_FactionWar._T.raceRows, "trial " .. tostring(race.n) .. " | target " .. string.format("%.1f", TRIALS[STEP - 2].offset) .. " s | realized " .. string.format("%.2f", race.realized) .. " s | expected " .. race.expected
            .. " | outcome " .. race.kind .. " | in claim " .. tostring(race.inClaim) .. " | records " .. tostring(records) .. " | board " .. board(towns))
        log(PASS[STEP] .. " " .. race.kind .. " match=" .. race.key .. " records=" .. tostring(records) .. " " .. board(towns))
        if n == 4 then
            log("[VRF][Interleave] SUMMARY trial | target | realized | expected | outcome | in claim | records | board")
            for _, line in ipairs(_FactionWar._T.raceRows) do log("[VRF][Interleave] SUMMARY " .. line) end
            log("[VRF][Interleave] E2E PASS four trials: one match key per ticket, one room, one settlement, the claim dropped or the human pairing standing")
        end
    elseif STEP == 15 then
        _FactionWarGuard.WaitSeconds = 10
        _MatchFaults:Remove()
        -- A remember-write may still be in flight for a player who just moved.
        wait(2)
        for _, profile in ipairs({ A_PROFILE, B_PROFILE }) do wipe(profile) end
        _FactionWar._T.race = nil
        _FactionWar._T.raceRows = nil
        _FactionWar._T.raceLatency = nil
        local code = _DataStorageService:DeleteGlobalDataStorageAndWait(_FactionWar.TownStorageName)
        log("[VRF][Interleave] CLEANUP town storage deleted code=" .. tostring(code) .. ", the two profiles' keys wiped, guard clock and adapters back")
    end
end)
if not ok then log_error("[VRF][Interleave] STEP " .. tostring(STEP) .. " FAIL " .. tostring(reason)) end
