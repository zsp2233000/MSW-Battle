-- Run in Maker's server_main after refresh and a fresh Play. Uses an isolated global storage name and fake queue entries only.
-- Final line: [VRF][FactionWarAttack] PROBE PASS (or FAIL <reason>).
local STORAGE = "CountryWarProbeV1"
local original = _FactionWar.TownStorageName
local function await(predicate, tries)
    for _ = 1, tries or 100 do if predicate() then return true end wait(0.1) end
    return false
end
local function read()
    local result, done = nil, false
    _FactionWar:ReadTowns(function(towns) result, done = towns, true end)
    assert(await(function() return done end), "town read answered")
    return result
end
local function settle(matchKey, home, away, homeResult, kind)
    local status, detail, done = nil, nil, false
    _FactionWarAttack:Settle(matchKey, home, away, homeResult, kind or "HUMAN", function(s, d) status, detail, done = s, d, true end)
    assert(await(function() return done end, 80), "settlement completed " .. matchKey)
    return status, detail
end

local ok, reason = pcall(function()
    local attack = _FactionWarAttack
    -- Rules.
    assert(attack:IsCapital("nanzih") and attack:IsCapital("yancheng"), "both capitals are protected")
    assert(not attack:IsCapital("zuoying") and not attack:IsCapital("gushan"), "front towns are contestable")
    assert(attack:Deduction("gushan", "WIN", "HUMAN") == 20, "human win takes 20 from a contestable town")
    assert(attack:Deduction("gushan", "WIN", "GUARD") == 10, "guard win takes 10 from a contestable town")
    assert(attack:Deduction("gushan", "LOSE", "HUMAN") == 0 and attack:Deduction("gushan", "DRAW", "GUARD") == 0, "only a win deducts")
    assert(attack:Deduction("yancheng", "WIN", "HUMAN") == 0 and attack:Deduction("nanzih", "WIN", "GUARD") == 0, "a capital never loses strength")

    -- Options: only adjacent enemy towns, from the authored gates.
    local towns = _FactionWar:InitialTowns()
    local function names(list) local out = {} for _, o in ipairs(list) do table.insert(out, o.town) end return table.concat(out, ",") end
    assert(names(attack:Targets("zuoying", "RED", towns)) == "gushan", "red at Zuoying sees Gushan only")
    assert(names(attack:Targets("nanzih", "RED", towns)) == "", "Nanzih has no enemy neighbour at the start")
    assert(names(attack:Targets("gushan", "BLUE", towns)) == "zuoying", "blue at Gushan sees Zuoying only")
    assert(names(attack:Targets("gushan", "RED", towns)) == "", "a town not owned by the faction offers nothing")
    towns.zuoying.owner = "BLUE"
    local fromCapital = attack:Targets("nanzih", "RED", towns)
    assert(#fromCapital == 1 and fromCapital[1].town == "zuoying" and fromCapital[1].capital == false, "the capital can counter-attack the lost town")
    towns.gushan.owner = "RED"
    local both = attack:Targets("gushan", "RED", towns)
    assert(#both == 2 and both[1].town == "zuoying" and both[1].capital == false and both[2].town == "yancheng" and both[2].capital == true,
        "a town with two enemy neighbours offers both and flags the capital")
    assert(attack:CanTarget("gushan", "yancheng", "RED", towns) and not attack:CanTarget("zuoying", "yancheng", "BLUE", towns), "no target that skips a town")

    -- Local queue: only mutual targets pair; lobby tickets never pair with war tickets.
    local queue = _MatchQueueLocal
    local delivered = {}
    local function entry(userId, profile, origin, target)
        local request = { userId = userId, profile = profile, requestId = userId .. "r", attempt = userId .. "a", source = "probe",
            origin = origin, target = target, live = function() return true end }
        queue:Enqueue(request, function(outcome) delivered[userId] = outcome end)
    end
    entry("p1", "profile1", "zuoying", "gushan")
    entry("p2", "profile2", "zuoying", "gushan")
    assert(queue:Poll() == false and delivered.p1 == nil, "two attackers from the same town do not pair")
    entry("p3", "profile3", "", "")
    assert(queue:Poll() == false and delivered.p3 == nil, "a lobby ticket does not pair with a war ticket")
    entry("p4", "profile4", "gushan", "yancheng")
    assert(queue:Poll() == false and delivered.p4 == nil, "non-mutual targets do not pair")
    entry("p5", "profile5", "gushan", "zuoying")
    assert(queue:Poll() == true and delivered.p1 == "MATCHED" and delivered.p5 == "MATCHED", "the oldest mutual pair is matched")
    assert(delivered.p2 == nil and delivered.p4 == nil, "everyone else keeps waiting")
    local matched = queue:Lookup("profile1")
    assert(matched ~= nil and matched.homeOrigin == "zuoying" and matched.awayOrigin == "gushan", "the pairing records both towns")
    for _, id in ipairs({ "p2", "p3", "p4" }) do queue:Withdraw(id) end
    queue:Release("profile1")
    queue:Release("profile5")

    -- Belongs: a notification must match the ticket's towns.
    local data = { profile = "profile1", requestId = "p1r", origin = "zuoying", target = "gushan" }
    assert(_MatchFlow:Belongs(data, matched), "the owner of a mutual match belongs")
    data.target = "nanzih"
    assert(not _MatchFlow:Belongs(data, matched), "a different target does not belong")
    assert(_MatchFlow:Belongs({ profile = "profile1", requestId = "p1r" }, matched), "a lobby ticket still belongs by attempt")
    local guardMatch = { key = "guard-x", home = "profile1", away = "guard:gushan", homeAttempt = "p1r", awayAttempt = "guard",
        homeOrigin = "zuoying", awayOrigin = "gushan", guard = true }
    assert(_MatchFlow:Belongs({ profile = "profile1", requestId = "p1r", origin = "zuoying", target = "gushan" }, guardMatch), "the ticket owner belongs to its guard match")
    assert(not _MatchFlow:Belongs({ profile = "profile1", requestId = "p1r", origin = "zuoying", target = "nanzih" }, guardMatch), "a guard match of another target does not belong")
    assert(not _MatchFlow:Belongs({ profile = "profile1", requestId = "stale", origin = "zuoying", target = "gushan" }, guardMatch), "a stale attempt does not belong")

    -- Guard identity and rosters.
    local guards = _FactionWarGuard
    assert(guards.WaitSeconds == 10, "the guard waits ten seconds")
    assert(guards:Profile("gushan") == "guard:gushan" and guards:IsGuardProfile("guard:gushan") and guards:TownOf("guard:gushan") == "gushan", "guard profile round trip")
    assert(not guards:IsGuardProfile("wp2601") and guards:TownOf("wp2601") == "", "a player profile is never a guard")
    for _, id in ipairs(_FactionWar.TownOrder) do
        local roster = guards:Roster(id)
        assert(roster ~= nil and #roster >= 1 and #roster <= 6, id .. " has a guard roster")
        roster[1].x = 99
        assert(guards:Roster(id)[1].x ~= 99, id .. " roster is a detached copy")
    end
    assert(guards:Roster("nowhere") == nil, "no guard outside the four towns")

    -- Settlement on isolated storage.
    _FactionWar.TownStorageName = STORAGE
    local fresh = _FactionWar:InitialTowns()
    local written = false
    _FactionWar:WriteTowns(fresh, function(saved) written = saved end)
    assert(await(function() return written end), "isolated storage seeded")
    local status, strength = settle("probe-m1", "zuoying", "gushan", "WIN")
    assert(status == "SAVED" and strength == 80, "red human win lowers Gushan from 100 to 80, got " .. tostring(status) .. "/" .. tostring(strength))
    status = settle("probe-m1", "zuoying", "gushan", "WIN")
    assert(status == "DUPLICATE", "a repeated result for the same match is ignored, got " .. tostring(status))
    towns = read()
    assert(towns.gushan.strength == 80 and towns.zuoying.strength == 100, "stored strength is 80 after the repeat")
    status, strength = settle("probe-m2", "gushan", "zuoying", "WIN")
    assert(status == "SAVED" and strength == 80, "a blue home win takes 20 from Zuoying, got " .. tostring(status))
    towns = read()
    assert(towns.gushan.strength == 80 and towns.zuoying.strength == 80, "Zuoying lost 20 too")
    status = settle("probe-m3", "zuoying", "gushan", "DRAW")
    assert(status == "NO_CHANGE", "a draw changes nothing")
    status = settle("probe-m4", "zuoying", "gushan", "LOSE")
    assert(status == "SAVED", "a red home loss means Gushan won and Zuoying settles")
    towns = read()
    assert(towns.zuoying.strength == 60, "Zuoying is down to 60")
    -- Guard matches: only a home win costs the guarded town, and only 10.
    local g, left = settle("probe-g1", "zuoying", "gushan", "WIN", "GUARD")
    assert(g == "SAVED" and left == 70, "red guard win lowers Gushan from 80 to 70, got " .. tostring(g) .. "/" .. tostring(left))
    assert(settle("probe-g1", "zuoying", "gushan", "WIN", "GUARD") == "DUPLICATE", "a repeated guard result is ignored")
    assert(settle("probe-g2", "zuoying", "gushan", "LOSE", "GUARD") == "NO_CHANGE", "losing to the guard changes no town")
    assert(settle("probe-g3", "zuoying", "gushan", "DRAW", "GUARD") == "NO_CHANGE", "drawing the guard changes no town")
    towns = read()
    assert(towns.gushan.strength == 70 and towns.zuoying.strength == 60, "only the one guard win was applied")
    -- Capital protection needs an enemy capital: make Zuoying blue, then red-side Nanzih loses nothing when blue wins.
    towns.zuoying.owner = "BLUE"
    written = false
    _FactionWar:WriteTowns(towns, function(saved) written = saved end)
    assert(await(function() return written end), "ownership change written")
    status = settle("probe-m5", "zuoying", "nanzih", "WIN")
    assert(status == "NO_CHANGE", "winning against a capital deducts nothing")
    towns = read()
    assert(towns.nanzih.strength == 100 and towns.nanzih.owner == "RED", "the capital keeps its strength and owner")
    assert(settle("probe-g4", "zuoying", "nanzih", "WIN", "GUARD") == "NO_CHANGE", "beating a capital guard deducts nothing")
    status = settle("probe-m6", "zuoying", "gushan", "WIN")
    assert(status == "SKIPPED", "a result between towns of the same faction deducts nothing")
    assert(settle("", "zuoying", "gushan", "WIN") == "SKIPPED", "a result without a match key is refused")
end)

_FactionWar.TownStorageName = original
_DataStorageService:DeleteGlobalDataStorageAndWait(STORAGE)
if ok then log("[VRF][FactionWarAttack] PROBE PASS") else log_error("[VRF][FactionWarAttack] PROBE FAIL " .. tostring(reason)) end
