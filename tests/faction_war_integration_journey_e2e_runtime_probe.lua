-- Maker end-to-end for #110 (integration): ONE chained journey, in the order a player lives it. It adds no rule; it chains what the #105-#109 probes show one by one:
--   choose a faction and enter the front, pass a gate to an adjacent friendly town, read the NPC options, queue and cancel in place, a human fight that makes
--   Gushan fall (the queued player is cancelled, the idle ones are sent to their capital), the landing of conqueror and loser, a player who left before the fall
--   and logs in after it (landing by the live owner), and the monster experience of both sides. It logs the observables the issue names with "ROW" lines
--   (what the player can do, the opponent, the strength, the owner, the landing, the experience) and prints them as one table in STEP 11.
-- A script cannot call FactionWar:RequestEntry, FactionWar:RequestGate or FactionWarAttack:OptionsFor (Server methods that read senderUserId, which only a real
-- client call has). The helpers entry(), gate() and options() below repeat their bodies with the same production calls in the same order
-- (CanEnterFromLobby, ReadFaction, the write of the choice, EnterFrontline; FindGate, NearGate, IsEngaged, CanPass, Enforce, Move; Targets, IsEngaged);
-- tests/faction_war_integration_contract.test.cjs pins those bodies so the mirror cannot drift. AttackFor and CancelForUser run as they are.
-- What only a real client does is NOT here: walking to the gate or the NPC, the interaction key, the dialog, the siege panel, the HUD (README "Manual visual checklist").
-- The human fight is NOT forced: 3 tanks (RED) against 1 tank (BLUE) is played out, about a minute.
-- Joins: 6 of the 10 virtual players a Play allows (kicked players count too): five adds before STEP 2 and one add after STEP 10.
--   add_virtual_player -profile_code wp2631 -nickname JourneyR1    (R1, RED,  3 tanks, enters at Zuoying)
--   add_virtual_player -profile_code wp2632 -nickname JourneyB1    (B1, BLUE, 1 tank,  enters at Gushan, fights R1)
--   add_virtual_player -profile_code wp2633 -nickname JourneyB2    (B2, BLUE, 1 tank,  queues AFTER the pair formed: must be cancelled by the fall)
--   add_virtual_player -profile_code wp2634 -nickname JourneyB3    (B3, BLUE, stands in Gushan: must be sent to Yancheng by the fall)
--   add_virtual_player -profile_code wp2635 -nickname JourneyB4    (B4, BLUE, kicked in STEP 7, added AGAIN after STEP 10)
-- Writes the REAL town storage (Gushan starts at 20, because the match room reads the real one); STEP 12 deletes it. Keep the real player in formationlobby.
-- STEP 1 runs BEFORE any virtual player exists and wipes what an earlier run left for the five profiles (faction, last town, monster levels, ticket), because a
-- profile with a faction and a last town is placed in that town at login and the journey needs fresh logins in formationlobby.
-- The guard clock is parked at 600 s so no guard claims B2 before the capture; STEP 12 puts it back to 10.
-- Steps are numbered; set STEP below, dispatch, wait for the line it announces. STEP 9 runs in server_instance_<matchKey> (the key is in the "QUEUED match=" line), the others in server_main.
--   1 SEED      server_main, no virtual player yet: wipes the five profiles, seeds Gushan at 20 (BLUE), parks the guard. Then add the five players and wait 14 s
--   2 SETUP     server_main, ~30 s: every player stands in formationlobby (a fresh login), formations saved for R1, B1, B2 ("SETUP PASS")
--   3 ENTRY     server_main: a call with no choice moves nobody; R1 chooses RED and enters at Zuoying, B1-B4 choose BLUE and enter at Gushan, the choice is stored ("ENTRY PASS")
--   4 GATE      server_main: R1 at Zuoying: no gate to Yancheng, the gate to enemy Gushan is refused, the gate to friendly Nanzih opens and shuts again ("GATE PASS")
--   5 OPTIONS   server_main: the NPC lists exactly the adjacent enemy town: Gushan for R1, Zuoying for B1-B4 ("OPTIONS PASS")
--   6 CANCEL    server_main: R1 queues, is ENGAGED, is told to cancel at the gate, cancels in place; clock cleared, nobody moved, unlocked ("CANCEL PASS")
--   7 QUEUE     server_main: R1 -> Gushan, B1 -> Zuoying (the pair forms), then B2 -> Zuoying (waits), then B4 is kicked. Wait for [VRF][MatchedBattle] result published once
--   8 CAPTURE   server_main, after the result: Gushan is RED and 100, counted once, one record; B2's ticket was cancelled; B2 and B3 stand in Yancheng ("CAPTURE PASS")
--   9 RETURN    server_instance_<matchKey>: ReturnForUser for everyone in the room (logs the result and the deaths per side)
--   10 LANDING  server_main (ADR 0016 update: written, not run): R1 in Zuoying (capturer), B1 in Yancheng (origin lost), nobody locked. R1 then uses
--               the gate to Gushan; NPC options follow the new owner. The experience of both sides is
--               credited once ("LANDING PASS"). Then add_virtual_player -profile_code wp2635 again and wait 14 s
--   11 RELOGIN  server_main: B4 has a NEW user id and was put in Yancheng by the live owner of Gushan; the login changed no town ("RELOGIN PASS", the table, "JOURNEY PASS")
--   12 CLEANUP  puts the guard clock back, deletes the war town storage and the five profiles' keys
-- Expected [VRF] lines (read with logs): see tests/README.md, "War integration (#110)".
local STEP = 1
local PREFIX = "[VRF][Journey] "
local PROFILES = { R1 = "wp2631", B1 = "wp2632", B2 = "wp2633", B3 = "wp2634", B4 = "wp2635" }
local ALIASES = { "R1", "B1", "B2", "B3", "B4" }
local function await(predicate, tries) for _ = 1, tries or 300 do if predicate() then return true end wait(0.1) end return false end
local function find()
    local byProfile = {}
    for _, user in ipairs(_UserService.UserEntities.Values) do
        if isvalid(user) and isvalid(user.PlayerComponent) then byProfile[user.PlayerComponent.ProfileCode] = user end
    end
    local found = {}
    for alias, profile in pairs(PROFILES) do found[alias] = byProfile[profile] end
    return found
end
local function id(user) return user.PlayerComponent.UserId end
local function readTowns()
    local towns, done = nil, false
    _FactionWarTownDocument:Read(function(result) towns, done = result, true end)
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
local function readTown(profile)
    local town, done = nil, false
    _FactionWar:ReadTown(profile, function(result) town, done = result, true end)
    assert(await(function() return done end, 100), "last town read")
    return town
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
local function wipe(profile)
    local storage = _DataStorageService:GetUserDataStorage(profile)
    storage:DeleteAndWait(_FactionWar.FactionKey)
    storage:DeleteAndWait(_FactionWar.TownKey)
    storage:DeleteAndWait(_MonsterLevelStorage.StorageKey)
    storage:DeleteAndWait(_FormationHandoff.StorageKey)
end
-- The observables are kept in the Play (not in the script, which is gone after each dispatch) and printed together at the end.
local function journeyRows()
    _FactionWar._T.journeyRows = _FactionWar._T.journeyRows or {}
    return _FactionWar._T.journeyRows
end
local function row(step, who, can, opponent, strength, owner, landing, xp)
    table.insert(journeyRows(), { step, who, can, opponent, strength, owner, landing, xp })
    log(PREFIX .. "ROW " .. step .. " | " .. who .. " | can: " .. can .. " | opponent: " .. opponent .. " | strength: " .. strength .. " | owner: " .. owner .. " | landing: " .. landing .. " | xp: " .. xp)
end
local function board(towns)
    local parts = {}
    for _, town in ipairs(_FactionWarTownDocument.TownOrder) do
        table.insert(parts, town .. "=" .. towns[town].owner .. "/" .. tostring(towns[town].strength) .. "/e" .. tostring(_FactionWarTownDocument:EpochOf(towns, town)))
    end
    return table.concat(parts, " ")
end
local function names(list)
    local parts = {}
    for _, option in ipairs(list) do table.insert(parts, option.town .. (option.capital and "(capital)" or "")) end
    if #parts == 0 then return "nothing to attack" end
    return "attack " .. table.concat(parts, ",")
end
-- FactionWar:RequestEntry without senderUserId: the same guard, the same pending mark, the same read of the faction, the same write of the choice, then EnterFrontline.
local function entry(user, choice)
    local userId, profile = id(user), user.PlayerComponent.ProfileCode
    assert(_FactionWar:CanEnterFromLobby(user, userId), "the player may enter from the lobby")
    assert(_FactionWar._T.pending[userId] ~= user, "no entry of this player is running")
    _FactionWar._T.pending[userId] = user
    local faction = readFaction(profile)
    if faction == "" and choice ~= "" then
        local saved = false
        _FormationStorage:Write(profile, _FactionWar.FactionKey, "", choice, function(code) saved = code == 0 end)
        assert(await(function() return saved end, 100), "the choice was written")
        faction = choice
    end
    _FactionWar:EnterFrontline(userId, user, faction)
    assert(await(function() return _FactionWar._T.pending[userId] == nil end, 100), "the entry ended")
    return faction
end
-- FactionWar:RequestGate without senderUserId. A real player walks to the gate; the script puts the player on it, and the same NearGate check then holds.
local function gate(user, destination)
    local userId, origin = id(user), user.CurrentMapName
    local door = _FactionWar:FindGate(origin, destination)
    if not isvalid(door) then return "NO_GATE" end
    _TeleportService:TeleportToMapPosition(user, door.TransformComponent.WorldPosition, origin)
    assert(await(function() return _FactionWar:NearGate(user, door) end, 50), "the player stands at the gate to " .. destination)
    if _FactionWarAttack:IsEngaged(userId) then return "ENGAGED" end
    local faction = readFaction(user.PlayerComponent.ProfileCode)
    local towns = readTowns()
    if faction == nil or faction == "" then return "UNREADABLE" end
    if not _FactionWarTownDocument:CanPass(faction, origin, destination, towns) then
        _FactionWarLanding:Judge(userId, { kind = "CHECK", town = origin, board = towns })
        return "DENIED"
    end
    assert(_FactionWar:Move(user, destination), "the move was dispatched")
    assert(await(function() return user.CurrentMapName == destination end, 100), "arrived in " .. destination)
    return "PASSED"
end
-- FactionWarAttack:OptionsFor without senderUserId: what the NPC dialog would be handed, as a status and a list.
local function options(user)
    local town = user.CurrentMapName
    local faction = readFaction(user.PlayerComponent.ProfileCode)
    local towns = readTowns()
    if faction == nil or faction == "" then return "UNAVAILABLE", {} end
    if towns[town].owner ~= faction then return "NOT_OWNED", {} end
    return _FactionWarAttack:IsEngaged(id(user)) and "ENGAGED" or "READY", _FactionWarAttack:Targets(town, faction, towns)
end
local function total(counts)
    local n = 0
    for _, count in pairs(counts or {}) do n = n + count end
    return n
end
local ok, reason = pcall(function()
    local users = find()
    if STEP == 1 then
        for _, alias in ipairs(ALIASES) do assert(users[alias] == nil, alias .. " (" .. PROFILES[alias] .. ") must not be connected yet: stop, play, and run STEP 1 before the adds") end
        for _, alias in ipairs(ALIASES) do wipe(PROFILES[alias]) end
        _FactionWar._T.journeyRows = {}
        -- Gushan one human win from falling; the guard must not claim the queued player before the capture.
        local towns = _FactionWarTownDocument:InitialTowns()
        towns.gushan.strength = 20
        local written = false
        _FactionWarTownDocument:WriteTowns(towns, function(saved) written = saved end)
        assert(await(function() return written end, 100), "Gushan seeded at 20")
        _FactionWarGuard.WaitSeconds = 600
        log("[VRF][Journey] SEED the five profiles are wiped, Gushan is BLUE at 20; now add the five virtual players (see the header), wait 14 s, then STEP 2")
    elseif STEP == 2 then
        for _, alias in ipairs(ALIASES) do assert(isvalid(users[alias]), alias .. " is connected") end
        local function setup(user, units)
            local record = _FormationService:GetSession(id(user))
            if not record.initialized then _FormationService:Load(record) end
            assert(await(function() return record.initialized and not record.pending end), "formation loaded")
            if units == nil then return end
            local slotId = record.editSlot
            _FormationService:SaveForUser(id(user), units, slotId, record.saved.slots[tostring(slotId)].revision, _UtilLogic:NewGuid())
            assert(await(function() return not record.pending and #record.saved.slots[tostring(slotId)].units == #units end), "save confirmed")
            _FormationService:ActivateForUser(id(user), slotId, record.saved.slots[tostring(slotId)].revision)
            assert(await(function() return not record.pending and record.saved.activeSlot == slotId end), "activate confirmed")
        end
        local three = {}
        for index = 1, 3 do three[index] = { monsterId = "monster_tank", x = -3.25 - (index - 1) * 0.75, y = -1.25 } end
        local one = {{ monsterId = "monster_tank", x = -3.25, y = -1.25 }}
        setup(users.R1, three)
        setup(users.B1, one)
        setup(users.B2, one)
        setup(users.B3, nil)
        setup(users.B4, nil)
        -- A fresh login with no faction and no last town stays where the engine puts it: the lobby.
        for _, alias in ipairs(ALIASES) do assert(users[alias].CurrentMapName == "formationlobby", alias .. " stands in formationlobby, found " .. users[alias].CurrentMapName) end
        local towns = readTowns()
        assert(towns.gushan.owner == "BLUE" and towns.gushan.strength == 20, "Gushan is BLUE at 20, found " .. board(towns))
        assert(_FactionWarGuard.WaitSeconds == 600, "the guard is parked")
        log("[VRF][Journey] SETUP PASS " .. board(towns))
    elseif STEP == 3 then
        local r1 = users.R1
        -- No choice and nothing stored: the production entry answers CHOOSE and moves nobody.
        assert(entry(r1, "") == "", "no faction is stored and none was chosen")
        wait(1)
        assert(r1.CurrentMapName == "formationlobby", "nobody moves without a choice")
        -- The choice is written once, then the player is put on the front: RED at Zuoying, BLUE at Gushan.
        assert(entry(r1, "RED") == "RED", "R1 chose RED")
        assert(await(function() return r1.CurrentMapName == "zuoying" end, 100), "RED enters at Zuoying")
        for _, alias in ipairs({ "B1", "B2", "B3", "B4" }) do
            assert(entry(users[alias], "BLUE") == "BLUE", alias .. " chose BLUE")
            assert(await(function() return users[alias].CurrentMapName == "gushan" end, 100), alias .. " enters at Gushan")
        end
        local towns = readTowns()
        assert(_FactionWar:FindFrontline("RED", towns) == "zuoying" and _FactionWar:FindFrontline("BLUE", towns) == "gushan", "the front of each faction on the seeded board")
        for _, alias in ipairs(ALIASES) do
            local wanted = alias == "R1" and "RED" or "BLUE"
            assert(readFaction(PROFILES[alias]) == wanted, alias .. "'s faction is stored as " .. wanted)
            local front = alias == "R1" and "zuoying" or "gushan"
            assert(await(function() return readTown(PROFILES[alias]) == front end, 80), alias .. "'s last town is stored as " .. front)
        end
        row("ENTRY", "R1", "choose a faction, enter the front", "-", "zuoying=" .. tostring(towns.zuoying.strength), "RED", "zuoying", "-")
        row("ENTRY", "B1-B4", "choose a faction, enter the front", "-", "gushan=" .. tostring(towns.gushan.strength), "BLUE", "gushan", "-")
        log("[VRF][Journey] ENTRY PASS " .. board(towns))
    elseif STEP == 4 then
        local r1 = users.R1
        assert(r1.CurrentMapName == "zuoying", "R1 starts at Zuoying")
        assert(gate(r1, "yancheng") == "NO_GATE", "no gate leads from Zuoying to Yancheng: only directly connected towns")
        assert(gate(r1, "gushan") == "DENIED", "the gate to enemy Gushan is refused")
        assert(r1.CurrentMapName == "zuoying", "a refused gate moves nobody")
        assert(gate(r1, "nanzih") == "PASSED", "the gate to friendly Nanzih opens")
        local status, list = options(r1)
        assert(status == "READY" and #list == 0, "the capital has no enemy neighbour to attack, found " .. status .. " " .. names(list))
        assert(await(function() return readTown(PROFILES.R1) == "nanzih" end, 80), "the last town follows the gate")
        assert(gate(r1, "zuoying") == "PASSED", "and back")
        assert(await(function() return readTown(PROFILES.R1) == "zuoying" end, 80), "the last town is Zuoying again")
        row("GATE", "R1", "gate to nanzih open, gate to gushan refused, no gate to yancheng", "-", "nanzih=100", "RED", "zuoying", "-")
        log("[VRF][Journey] GATE PASS")
    elseif STEP == 5 then
        local expected = { R1 = "gushan", B1 = "zuoying", B2 = "zuoying", B3 = "zuoying", B4 = "zuoying" }
        for _, alias in ipairs(ALIASES) do
            local status, list = options(users[alias])
            assert(status == "READY", alias .. " is ready to attack, found " .. status)
            assert(#list == 1 and list[1].town == expected[alias] and list[1].capital == false, alias .. " is offered exactly " .. expected[alias] .. ", found " .. names(list))
        end
        local towns = readTowns()
        local _, redList = options(users.R1)
        local _, blueList = options(users.B1)
        row("OPTIONS", "R1", names(redList), "gushan (guard after 10 s, a human if one queues for zuoying)", "gushan=" .. tostring(towns.gushan.strength), "BLUE", "zuoying", "-")
        row("OPTIONS", "B1-B4", names(blueList), "zuoying (guard after 10 s, a human if one queues for gushan)", "zuoying=" .. tostring(towns.zuoying.strength), "RED", "gushan", "-")
        log("[VRF][Journey] OPTIONS PASS")
    elseif STEP == 6 then
        local r1 = users.R1
        local userId = id(r1)
        _FactionWarAttack:AttackFor(userId, "gushan")
        assert(await(function() return _MatchFlow:StateForUser(userId) == "QUEUED" end, 100), "R1 is queued")
        assert(_FactionWarAttack:IsEngaged(userId), "a queued player is engaged")
        assert(_MatchFlow._T.guardTimers[userId] ~= nil, "the guard clock is running")
        assert(options(r1) == "ENGAGED", "the NPC says the player is engaged")
        assert(gate(r1, "nanzih") == "ENGAGED", "the gate tells a queued player to cancel first")
        assert(r1.CurrentMapName == "zuoying", "and R1 is still in Zuoying")
        _MatchFlow:CancelForUser(userId)
        assert(await(function() return _MatchFlow:StateForUser(userId) == "IDLE" end, 100), "cancelled back to idle")
        assert(await(function() return not _FactionWarAttack:IsEngaged(userId) end, 100), "the lock is released")
        assert(_MatchFlow._T.guardTimers[userId] == nil, "cancelling stops the guard clock")
        assert(r1.CurrentMapName == "zuoying", "cancelled in place: nobody walked anywhere")
        assert(options(r1) == "READY", "the next attack can start at once")
        row("CANCEL", "R1", "queue, gate says cancel first, cancel in place", "-", "gushan=20", "BLUE", "zuoying", "-")
        log("[VRF][Journey] CANCEL PASS")
    elseif STEP == 7 then
        -- A user entity loses its PlayerComponent once it is transferred to the match room, so the ids are read first.
        local r1, b1, b2, b4 = users.R1, users.B1, users.B2, users.B4
        local idR1, idB1, idB2, idB4 = id(r1), id(b1), id(b2), id(b4)
        _FactionWarAttack:AttackFor(idR1, "gushan")
        assert(await(function() return _FactionWarAttack:IsEngaged(idR1) end, 100), "R1 engaged")
        _FactionWarAttack:AttackFor(idB1, "zuoying")
        assert(await(function() return _FactionWarAttack:IsEngaged(idB1) end, 100), "B1 engaged")
        -- The pair must exist before the third ticket, or FIFO could pair B2 with R1.
        assert(await(function() return _MatchFlow:StateForUser(idR1) ~= "QUEUED" and _MatchFlow:StateForUser(idB1) ~= "QUEUED" end, 300), "R1 and B1 matched")
        _FactionWarAttack:AttackFor(idB2, "zuoying")
        assert(await(function() return _MatchFlow:StateForUser(idB2) == "QUEUED" end, 100), "B2 waits in the queue")
        local key = ""
        assert(await(function()
            local ticket = _MatchFlow._T.records[idR1]
            key = ticket ~= nil and ticket.data ~= nil and ticket.data.matchKey or ""
            return key ~= ""
        end, 300), "the pair is sealed")
        -- B4 really leaves while standing in Gushan; it logs in again after the town has fallen.
        _UserService:KickUser(idB4, KickReason.ETC)
        assert(await(function() return find().B4 == nil end, 100), "B4 left")
        _FactionWar._T.journeyKicked = idB4
        local towns = readTowns()
        row("QUEUE", "R1", "queued against gushan", "B1 (human, queued against zuoying)", "gushan=" .. tostring(towns.gushan.strength), "BLUE", "match room " .. key, "-")
        row("QUEUE", "B2", "queued against zuoying behind the pair: cannot match", "-", "gushan=" .. tostring(towns.gushan.strength), "BLUE", "gushan", "-")
        log("[VRF][Journey] QUEUED match=" .. key .. "; B4 was kicked; wait for [VRF][MatchedBattle] result published once, then STEP 8")
    elseif STEP == 8 then
        local towns
        assert(await(function()
            towns = readTowns()
            return towns.gushan.owner == "RED"
        end, 1500), "Gushan changed flag within 150 s (a RED loss does not capture it: run the journey again)")
        assert(towns.gushan.strength == 100 and _FactionWarTownDocument:EpochOf(towns, "gushan") == 1, "refilled to 100 and counted once, found " .. board(towns))
        assert(#(towns.settled or {}) == 1, "one record, found " .. tostring(#(towns.settled or {})))
        assert(towns.nanzih.owner == "RED" and towns.nanzih.strength == 100 and towns.yancheng.owner == "BLUE" and towns.yancheng.strength == 100 and towns.zuoying.strength == 100, "no other town moved")
        assert(await(function() return users.B2.CurrentMapName == "yancheng" and users.B3.CurrentMapName == "yancheng" end, 300), "the queued and the idle blue player were sent to Yancheng")
        assert(_MatchFlow:StateForUser(id(users.B2)) == "IDLE" and not _FactionWarAttack:IsEngaged(id(users.B2)), "B2's ticket was cancelled before the move")
        assert(find().B4 == nil, "B4 is still away")
        row("CAPTURE", "B2", "ticket cancelled by the fall, sent to the capital", "-", "gushan=" .. tostring(towns.gushan.strength), "RED (was BLUE)", "yancheng", "-")
        row("CAPTURE", "B3", "idle in the fallen town, sent to the capital", "-", "gushan=" .. tostring(towns.gushan.strength), "RED (was BLUE)", "yancheng", "-")
        log("[VRF][Journey] CAPTURE PASS " .. board(towns) .. " record=" .. tostring(towns.settled[1].k))
    elseif STEP == 9 then
        local map = _EntityService:GetEntityByPath("/maps/matchprobe")
        local battle = map:GetComponent("script.BattleSession")
        assert(battle.Phase == "RESULT", "the room has its result, phase " .. tostring(battle.Phase))
        log(PREFIX .. "ROOM " .. _RoomService.RoomKey .. " home=" .. battle.HomeProfile .. ":" .. battle:ResultForProfile(battle.HomeProfile) .. " away=" .. battle.AwayProfile .. ":" .. battle:ResultForProfile(battle.AwayProfile)
            .. " deaths PLAYER=" .. tostring(total(battle._T.deaths.PLAYER)) .. " ENEMY=" .. tostring(total(battle._T.deaths.ENEMY)))
        for _, user in ipairs(_UserService.UserEntities.Values) do
            if isvalid(user) and isvalid(user.PlayerComponent) then _MatchFlow:ReturnForUser(id(user)) end
        end
        log("[VRF][Journey] RETURN issued")
    elseif STEP == 10 then
        local r1, b1
        assert(await(function()
            users = find()
            r1, b1 = users.R1, users.B1
            return isvalid(r1) and isvalid(b1) and r1.CurrentMapName == "zuoying" and b1.CurrentMapName == "yancheng"
        end, 400), "R1 returned to Zuoying and B1 went to Yancheng after losing Gushan")
        local redLanding = r1.CurrentMapName
        log("[VRF][Journey] return destinations R1=" .. redLanding .. " B1=" .. b1.CurrentMapName)
        for _, alias in ipairs({ "R1", "B1", "B2", "B3" }) do assert(await(function() return not _FactionWarAttack:IsEngaged(id(users[alias])) end), alias .. " is unlocked") end
        local towns = readTowns()
        assert(towns.gushan.owner == "RED" and towns.gushan.strength == 100 and #towns.settled == 1, "one settlement is stored, found " .. board(towns))
        local record = towns.settled[1]
        assert(record.w == "zuoying" and record.l == "gushan" and record.o == "RED" and record.s == 100, "the record says RED took Gushan from Zuoying and refilled it")
        assert(_FactionWar:FindFrontline("RED", towns) == "gushan" and _FactionWar:FindFrontline("BLUE", towns) == "yancheng", "new players land on the new front")
        -- Only a separate gate trip takes R1 to the new town. There the NPC faces the blue capital.
        assert(gate(r1, "gushan") == "PASSED", "R1 can now use the gate from Zuoying to Gushan")
        local redStatus, red = options(r1)
        local blueStatus, blue = options(b1)
        assert(redStatus == "READY" and #red == 1 and red[1].town == "yancheng" and red[1].capital == true, "R1 is offered the blue capital, found " .. names(red))
        assert(blueStatus == "READY" and #blue == 1 and blue[1].town == "gushan" and blue[1].capital == false, "B1 is offered Gushan, found " .. names(blue))
        -- Monster experience of both sides: the match is credited once to each profile; the loser's only tank died.
        local winner, loser
        assert(await(function()
            winner, loser = history(PROFILES.R1), history(PROFILES.B1)
            return credited(winner, record.k) == 1 and credited(loser, record.k) == 1
        end, 100), "the match is in both monster-level histories (R1 and B1) exactly once")
        assert(loser.monsters.monster_tank ~= nil, "B1's only tank died and earned experience")
        local tank = _HttpService:JSONEncode(loser.monsters.monster_tank)
        local redTank = winner.monsters.monster_tank ~= nil and _HttpService:JSONEncode(winner.monsters.monster_tank) or "no tank died"
        row("LANDING", "R1", "after gate to Gushan: " .. names(red), "B1 (human, lost)", "gushan=100", "RED (took it)", redLanding, "key once; " .. redTank)
        row("LANDING", "B1", names(blue), "R1 (human, won)", "gushan=100", "RED (lost it)", "yancheng", "key once; monster_tank " .. tank)
        row("LANDING", "B2, B3", "attack gushan (the town they lost)", "-", "gushan=100", "RED", "yancheng", "-")
        log("[VRF][Journey] LANDING PASS " .. board(towns) .. "; now add_virtual_player -profile_code wp2635 -nickname JourneyB4 again, wait 14 s, then STEP 11")
    elseif STEP == 11 then
        local b4 = users.B4
        assert(isvalid(b4), "wp2635 logged in again (add_virtual_player -profile_code wp2635 -nickname JourneyB4)")
        local userId = id(b4)
        assert(userId ~= _FactionWar._T.journeyKicked, "the login has a NEW user id")
        -- Gushan fell while B4 was away: its last town is Gushan, so the live board sends it to its own capital, once.
        assert(await(function() return b4.CurrentMapName == "yancheng" end, 200), "the login was placed in Yancheng, found " .. b4.CurrentMapName)
        assert(await(function() return readTown(PROFILES.B4) == "yancheng" end, 80), "the last town is now Yancheng")
        assert(await(function() return not _FactionWarLanding:IsJudging(userId) end, 100), "the placement slot is free")
        assert(not _FactionWarAttack:IsEngaged(userId), "no ticket holds the player")
        local towns = readTowns()
        assert(towns.gushan.owner == "RED" and towns.gushan.strength == 100 and #towns.settled == 1, "the login changed no town, found " .. board(towns))
        local status, list = options(b4)
        row("RELOGIN", "B4", names(list), "-", "gushan=100", "RED (fell while B4 was away)", "yancheng", "-")
        log("[VRF][Journey] RELOGIN PASS user=" .. userId .. " lands in yancheng")
        log("[VRF][Journey] SUMMARY step | who | can do | opponent | strength | owner | landing | experience")
        for _, entryRow in ipairs(journeyRows()) do
            log("[VRF][Journey] SUMMARY " .. table.concat(entryRow, " | "))
        end
        log("[VRF][Journey] SUMMARY final board " .. board(towns))
        log("[VRF][Journey] JOURNEY PASS")
    elseif STEP == 12 then
        _FactionWarGuard.WaitSeconds = 10
        -- A remember-write may still be in flight for a player who just moved.
        wait(2)
        for _, alias in ipairs(ALIASES) do wipe(PROFILES[alias]) end
        _FactionWar._T.journeyRows = nil
        _FactionWar._T.journeyKicked = nil
        local code = _DataStorageService:DeleteGlobalDataStorageAndWait(_FactionWarTownDocument.TownStorageName)
        log("[VRF][Journey] CLEANUP town storage deleted code=" .. tostring(code) .. ", the five profiles' keys wiped, guard clock back to 10 s")
    end
end)
if not ok then log_error("[VRF][Journey] STEP " .. tostring(STEP) .. " FAIL " .. tostring(reason)) end
