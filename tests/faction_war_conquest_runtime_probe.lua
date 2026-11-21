-- #107 rules probe. Run in Maker's server_main after refresh and a fresh Play; no virtual player is needed.
-- Uses an isolated global storage name only. Keep every real player in formationlobby: a flip sweeps the town it took.
-- Final line: [VRF][FactionWarConquest] PROBE PASS (or FAIL <reason>).
-- Covers: flip + refill at zero, repeat result, guard flip, capital invariants, who lands where, and the board the
-- NPC / gate / front line read after a flip (AC1, AC3, AC4 rules). The matching two-player scene is
-- faction_war_conquest_e2e_runtime_probe.lua.
local STORAGE = "CountryWarProbe107V1"
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
local function write(towns)
    local saved = false
    _FactionWar:WriteTowns(towns, function(ok) saved = ok end)
    assert(await(function() return saved end), "town write confirmed")
end
local function seed(owners, strengths, settled)
    local towns = _FactionWar:InitialTowns()
    for id, owner in pairs(owners or {}) do towns[id].owner = owner end
    for id, strength in pairs(strengths or {}) do towns[id].strength = strength end
    -- The engine's JSONEncode rejects an empty table, so an empty history is stored as no field at all.
    if settled ~= nil and #settled > 0 then towns.settled = settled end
    write(towns)
end
local function settle(matchKey, home, away, homeResult, kind)
    local status, detail, outcome, done = nil, nil, nil, false
    _FactionWarAttack:Settle(matchKey, home, away, homeResult, kind or "HUMAN", function(s, d, o) status, detail, outcome, done = s, d, o, true end)
    assert(await(function() return done end, 80), "settlement completed " .. matchKey)
    return status, detail, outcome
end
local function names(list) local out = {} for _, o in ipairs(list) do table.insert(out, o.town) end return table.concat(out, ",") end

local ok, reason = pcall(function()
    local war, attack = _FactionWar, _FactionWarAttack

    -- Pure rules: capital, landing, passage.
    assert(war:CapitalOf("RED") == "nanzih" and war:CapitalOf("BLUE") == "yancheng" and war:CapitalOf("") == "", "capital of each faction")
    local board = war:InitialTowns()
    board.gushan.owner = "RED"
    assert(war:Landing("RED", "gushan", board) == "gushan", "a faction lands in a town it owns")
    assert(war:Landing("BLUE", "gushan", board) == "yancheng", "a faction that lost the town lands in its capital")
    assert(war:Landing("RED", "yancheng", board) == "nanzih", "an enemy capital is never a landing")
    assert(war:Landing("BLUE", "nowhere", board) == "yancheng" and war:Landing("BLUE", "gushan", nil) == "yancheng", "unknown town or no table falls back to the capital")
    assert(war:CanPass("RED", "zuoying", "gushan", board) and not war:CanPass("BLUE", "gushan", "zuoying", board), "a gate needs both towns to be the traveller's")

    -- AC3 board after Gushan turns red: front line for new players, gate and NPC options follow the new owner.
    assert(war:FindFrontline("RED", board) == "gushan", "a new red player lands in Gushan")
    assert(war:FindFrontline("BLUE", board) == "yancheng", "a new blue player lands in Yancheng (the capital faces Gushan)")
    assert(names(attack:Targets("gushan", "RED", board)) == "yancheng" and attack:Targets("gushan", "RED", board)[1].capital == true, "red at Gushan can only pick the blue capital")
    assert(names(attack:Targets("zuoying", "RED", board)) == "", "Zuoying no longer borders an enemy")
    assert(names(attack:Targets("yancheng", "BLUE", board)) == "gushan" and attack:Targets("yancheng", "BLUE", board)[1].capital == false, "blue at its capital can pick Gushan")
    assert(names(attack:Targets("gushan", "BLUE", board)) == "", "a town the faction lost offers nothing")
    assert(attack:CanTarget("yancheng", "gushan", "BLUE", board) and attack:CanTarget("gushan", "yancheng", "RED", board), "blue with only Yancheng and red at Gushan pick each other")

    _FactionWar.TownStorageName = STORAGE

    -- AC1: a human win over a 20-strength town flips it at once and refills it to 100.
    seed({}, { gushan = 20 })
    local status, strength, outcome = settle("c107-m1", "zuoying", "gushan", "WIN")
    assert(status == "SAVED" and strength == 100, "flip reports the refilled strength, got " .. tostring(status) .. "/" .. tostring(strength))
    assert(outcome.flipped == true and outcome.owner == "RED" and outcome.winner == "zuoying" and outcome.loser == "gushan" and outcome.amount == 20, "outcome names the capture")
    local towns = read()
    assert(towns.gushan.owner == "RED" and towns.gushan.strength == 100, "stored Gushan is red with 100")
    assert(towns.zuoying.owner == "RED" and towns.zuoying.strength == 100 and towns.nanzih.strength == 100 and towns.yancheng.owner == "BLUE" and towns.yancheng.strength == 100, "nothing else moved")
    assert(towns.settled[1].k == "c107-m1" and towns.settled[1].o == "RED" and towns.settled[1].s == 100, "the settled record keeps what the match did")
    -- A repeat of the same result changes nothing and answers the same capture.
    status, strength, outcome = settle("c107-m1", "zuoying", "gushan", "WIN")
    assert(status == "DUPLICATE" and outcome.flipped == true and outcome.owner == "RED" and outcome.strength == 100, "a repeat is DUPLICATE and still reports the capture")
    towns = read()
    assert(towns.gushan.strength == 100 and #towns.settled == 1, "the repeat wrote nothing new")
    assert(attack._T.outcomes["c107-m1"].flipped == true, "the room remembers the outcome for the returning players")

    -- Winning from 40 leaves 20 and does not flip; the next win then does.
    seed({}, { gushan = 40 })
    status, strength, outcome = settle("c107-m2", "zuoying", "gushan", "WIN")
    assert(status == "SAVED" and strength == 20 and outcome.flipped == false and outcome.owner == "", "40 -> 20 is no capture")
    assert(read().gushan.owner == "BLUE", "still blue at 20")
    status, strength, outcome = settle("c107-m3", "gushan", "zuoying", "LOSE")
    assert(status == "SAVED" and strength == 100 and outcome.flipped == true and outcome.owner == "RED", "a blue home loss (red won) takes the town at 20")

    -- A guard win from 10 also captures; a guard win at 20 only takes 10.
    seed({}, { gushan = 10 })
    status, strength, outcome = settle("c107-g1", "zuoying", "gushan", "WIN", "GUARD")
    assert(status == "SAVED" and strength == 100 and outcome.flipped and outcome.winner == "zuoying", "guard win from 10 takes the town")
    seed({}, { gushan = 20 })
    status, strength, outcome = settle("c107-g2", "zuoying", "gushan", "WIN", "GUARD")
    assert(status == "SAVED" and strength == 10 and not outcome.flipped, "guard win from 20 leaves 10")
    assert(settle("c107-g3", "zuoying", "gushan", "LOSE", "GUARD") == "NO_CHANGE" and read().gushan.strength == 10, "losing to the guard changes nothing")

    -- AC4 on the flipped board: blue (only Yancheng left) wins -> Gushan -20; red wins at Yancheng -> nothing.
    seed({ gushan = "RED" }, {}, {})
    status, strength, outcome = settle("c107-b1", "yancheng", "gushan", "WIN")
    assert(status == "SAVED" and strength == 80 and not outcome.flipped, "blue human win takes 20 from Gushan")
    status, strength, outcome = settle("c107-b2", "gushan", "yancheng", "WIN")
    assert(status == "NO_CHANGE" and outcome.flipped == false, "red winning over the capital changes nothing")
    assert(settle("c107-b3", "gushan", "yancheng", "WIN", "GUARD") == "NO_CHANGE", "beating the capital guard changes nothing either")
    towns = read()
    assert(towns.yancheng.owner == "BLUE" and towns.yancheng.strength == 100 and towns.nanzih.owner == "RED" and towns.nanzih.strength == 100, "capitals keep owner and strength")
    assert(towns.gushan.owner == "RED" and towns.gushan.strength == 80, "Gushan took exactly one 20")
    -- Capture back from the capital's side: 80 -> 60 -> 40 -> 20 -> flip, one human win each.
    for index = 1, 3 do assert(settle("c107-back" .. index, "yancheng", "gushan", "WIN") == "SAVED", "counter-attack " .. index) end
    assert(read().gushan.strength == 20 and read().gushan.owner == "RED", "Gushan is down to 20")
    status, strength, outcome = settle("c107-back4", "yancheng", "gushan", "WIN")
    assert(status == "SAVED" and strength == 100 and outcome.flipped and outcome.owner == "BLUE" and read().gushan.owner == "BLUE", "blue takes Gushan back from its capital")

    -- Legacy documents (bare match keys) are still understood and kept, and the whole list stays small.
    seed({}, { gushan = 20 }, { "legacy-1" })
    status, strength, outcome = settle("legacy-1", "zuoying", "gushan", "WIN")
    assert(status == "DUPLICATE" and outcome.flipped == false, "a legacy key still dedupes")
    assert(settle("c107-new", "zuoying", "gushan", "WIN") == "SAVED", "a new result appends to a legacy list")
    towns = read()
    assert(towns.settled[1] == "legacy-1" and towns.settled[2].k == "c107-new", "legacy entries stay as they were")
    -- 24 stored results: the history stays capped and the document stays under one storage credit (4000 bytes).
    seed({}, {}, {})
    for index = 1, 24 do
        assert(settle("c107-size" .. index .. "-" .. _UtilLogic:NewGuid(), "zuoying", "gushan", "WIN") == "SAVED", "result " .. index .. " stored")
        -- Put the town back to full strength so the loop never captures it; the history list is kept as it is.
        local current = read()
        current.gushan.strength = 100
        write(current)
    end
    towns = read()
    local bytes = #_HttpService:JSONEncode(towns)
    assert(#towns.settled == attack.SettledHistory, "the history is capped at " .. tostring(attack.SettledHistory) .. ", got " .. tostring(#towns.settled))
    assert(bytes < 4000, "the town document stays under one storage credit, bytes=" .. tostring(bytes))
    log("[VRF][FactionWarConquest] document bytes=" .. tostring(bytes) .. " settled=" .. tostring(#towns.settled))
end)

_FactionWar.TownStorageName = original
_DataStorageService:DeleteGlobalDataStorageAndWait(STORAGE)
if ok then log("[VRF][FactionWarConquest] PROBE PASS") else log_error("[VRF][FactionWarConquest] PROBE FAIL " .. tostring(reason)) end
