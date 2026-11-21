-- Maker end-to-end for #107 (capture, landing, eviction). Needs four virtual players, added in Play before running this in server_main:
--   add_virtual_player -profile_code wp2601 -nickname Conqueror   (RED,  Zuoying, 3 tanks)
--   add_virtual_player -profile_code wp2602 -nickname Loser       (BLUE, Gushan,   1 tank, fights A)
--   add_virtual_player -profile_code wp2603 -nickname Queued      (BLUE, Gushan,   queues AFTER the pair formed, must be cancelled)
--   add_virtual_player -profile_code wp2604 -nickname Idle        (BLUE, Gushan,   stands still, must be sent home)
-- Writes the REAL town storage (Gushan starts at 20); STEP 8 deletes it. Keep the real player in formationlobby.
-- Steps are numbered; set STEP below, dispatch, wait for the line it announces.
--   1 SETUP      server_main, ~60 s, wait "SETUP PASS"
--   2 QUEUE1     server_main: A -> Gushan, B -> Zuoying (the pair forms), then C -> Zuoying (waits, cannot match)
--   3 CAPTURE    server_main, after the match room logged "[VRF][MatchedBattle] result published once": the town flipped,
--                the announcement reached the static room, C was cancelled and C + D stand in Yancheng
--   4 RETURN     server_instance_<matchKey> (each match): ReturnForUser for every user in the room
--   5 LANDING1   server_main: A is in Gushan (the conqueror), B in Yancheng (the loser), nobody is locked
--   6 QUEUE2     server_main: A (red, Gushan) -> Yancheng, B (blue, Yancheng) -> Gushan  (red wins a capital: nothing changes)
--   7 LANDING2   server_main, after STEP 4 again: Yancheng is still BLUE/100, Gushan RED/100, A in Gushan, B in Yancheng
--   8 CLEANUP
-- Expected [VRF] lines (read with logs): see the probe plan in the #107 report.
local STEP = 1
local PROFILES = { "wp2601", "wp2602", "wp2603", "wp2604" }
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
local ok, reason = pcall(function()
    local users = find()
    local a, b, c, d = users.wp2601, users.wp2602, users.wp2603, users.wp2604
    if STEP == 1 then
        assert(isvalid(a) and isvalid(b) and isvalid(c) and isvalid(d), "all four virtual players connected")
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
        setup(c, {{ monsterId = "monster_tank", x = -3.25, y = -1.25 }})
        for user, value in pairs({ [a] = "RED", [b] = "BLUE", [c] = "BLUE", [d] = "BLUE" }) do
            local saved = false
            _FormationStorage:Write(user.PlayerComponent.ProfileCode, _FactionWar.FactionKey, "", value, function(code) saved = code == 0 end)
            await(function() return saved end, 100)
        end
        -- Gushan one win from falling; the guard must not claim the queued player before the capture.
        local towns = _FactionWar:InitialTowns()
        towns.gushan.strength = 20
        local written = false
        _FactionWar:WriteTowns(towns, function(saved) written = saved end)
        assert(await(function() return written end, 100), "Gushan seeded at 20")
        _FactionWarGuard.WaitSeconds = 600
        assert(_FactionWar:Move(a, "zuoying") and _FactionWar:Move(b, "gushan") and _FactionWar:Move(c, "gushan") and _FactionWar:Move(d, "gushan"), "moves dispatched")
        assert(await(function() return a.CurrentMapName == "zuoying" and b.CurrentMapName == "gushan" and c.CurrentMapName == "gushan" and d.CurrentMapName == "gushan" end), "players in their towns")
        log("[VRF][ConquestE2E] SETUP PASS")
    elseif STEP == 2 then
        _FactionWarAttack:AttackFor(id(a), "gushan")
        assert(await(function() return _FactionWarAttack:IsEngaged(id(a)) end, 100), "A engaged")
        _FactionWarAttack:AttackFor(id(b), "zuoying")
        assert(await(function() return _FactionWarAttack:IsEngaged(id(b)) end, 100), "B engaged")
        -- The pair must exist before the third ticket, or FIFO could pair C with A.
        assert(await(function() return _MatchFlow:StateForUser(id(a)) ~= "QUEUED" and _MatchFlow:StateForUser(id(b)) ~= "QUEUED" end, 200), "A and B matched")
        _FactionWarAttack:AttackFor(id(c), "zuoying")
        assert(await(function() return _MatchFlow:StateForUser(id(c)) == "QUEUED" end, 100), "C waits in the queue")
        assert(c.CurrentMapName == "gushan" and d.CurrentMapName == "gushan", "C and D still stand in Gushan")
        log("[VRF][ConquestE2E] QUEUED; wait for [VRF][MatchedBattle] result published once, then STEP 3")
    elseif STEP == 3 then
        local towns
        assert(await(function()
            towns = readTowns()
            return towns ~= nil and towns.gushan.owner == "RED"
        end, 1500), "Gushan changed flag within 150 s")
        assert(towns.gushan.strength == 100, "and refilled to 100, got " .. tostring(towns.gushan.strength))
        assert(towns.nanzih.strength == 100 and towns.nanzih.owner == "RED" and towns.yancheng.strength == 100 and towns.yancheng.owner == "BLUE", "capitals untouched")
        assert(await(function() return c.CurrentMapName == "yancheng" and d.CurrentMapName == "yancheng" end, 300), "the queued and the idle blue player were sent to Yancheng")
        assert(_MatchFlow:StateForUser(id(c)) == "IDLE" and not _FactionWarAttack:IsEngaged(id(c)), "C's ticket was cancelled before the move")
        log("[VRF][ConquestE2E] CAPTURE PASS")
    elseif STEP == 4 then
        for _, user in ipairs(_UserService.UserEntities.Values) do _MatchFlow:ReturnForUser(id(user)) end
        log("[VRF][ConquestE2E] RETURN issued")
    elseif STEP == 5 then
        assert(await(function()
            users = find()
            a, b = users.wp2601, users.wp2602
            return isvalid(a) and isvalid(b) and a.CurrentMapName == "gushan" and b.CurrentMapName == "yancheng"
        end, 400), "the conqueror entered Gushan and the loser went to Yancheng")
        for _, user in ipairs({ a, b, c, d }) do assert(await(function() return not _FactionWarAttack:IsEngaged(id(user)) end), "unlocked") end
        local towns = readTowns()
        assert(_FactionWar:FindFrontline("RED", towns) == "gushan" and _FactionWar:FindFrontline("BLUE", towns) == "yancheng", "new players land on the new front")
        assert(_FactionWar:CanPass("RED", "zuoying", "gushan", towns) and not _FactionWar:CanPass("BLUE", "yancheng", "gushan", towns), "the gate follows the new owner")
        local red = _FactionWarAttack:Targets("gushan", "RED", towns)
        local blue = _FactionWarAttack:Targets("yancheng", "BLUE", towns)
        assert(#red == 1 and red[1].town == "yancheng" and red[1].capital == true and #blue == 1 and blue[1].town == "gushan", "the NPC options follow the new owner")
        log("[VRF][ConquestE2E] LANDING1 PASS")
    elseif STEP == 6 then
        _FactionWarAttack:AttackFor(id(a), "yancheng")
        assert(await(function() return _FactionWarAttack:IsEngaged(id(a)) end, 100), "A engaged")
        _FactionWarAttack:AttackFor(id(b), "gushan")
        assert(await(function() return _FactionWarAttack:IsEngaged(id(b)) end, 100), "B engaged")
        log("[VRF][ConquestE2E] ROUND 2 QUEUED; wait for the result, run STEP 4 inside the new match room, then STEP 7")
    elseif STEP == 7 then
        assert(await(function()
            users = find()
            a, b = users.wp2601, users.wp2602
            return isvalid(a) and isvalid(b) and a.CurrentMapName == "gushan" and b.CurrentMapName == "yancheng"
        end, 1500), "both are back where they were")
        local towns = readTowns()
        assert(towns.yancheng.owner == "BLUE" and towns.yancheng.strength == 100, "a red win over the capital changes nothing")
        assert(towns.gushan.owner == "RED" and towns.gushan.strength == 100, "Gushan stays red and full")
        log("[VRF][ConquestE2E] LANDING2 PASS")
    elseif STEP == 8 then
        _FactionWarGuard.WaitSeconds = 10
        local code = _DataStorageService:DeleteGlobalDataStorageAndWait(_FactionWar.TownStorageName)
        log("[VRF][ConquestE2E] CLEANUP town storage deleted code=" .. tostring(code))
    end
end)
if not ok then log_error("[VRF][ConquestE2E] STEP " .. tostring(STEP) .. " FAIL " .. tostring(reason)) end
