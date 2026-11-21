-- #108 rules probe. Run in Maker's server_main after refresh and a fresh Play; no virtual player is needed.
-- Uses an isolated global storage name (CountryWarProbe108V1) and an isolated monster-level key only. Keep every real player in
-- formationlobby: a flip sweeps the town it took.
-- Final line: [VRF][FactionWarContest] PROBE PASS (or FAIL <reason>).
-- Covers: the per-town change count and its decoder, the stamp a pairing carries (Snapshot / Stamped / Combine / ChangedSince),
-- the compare-and-swap on the stored bytes (stale swap, two first creators), two overlapping settlements of the same town (AC1),
-- a match whose town was flipped and taken back (AC2), the board where both towns changed hands, where the players of an exempt
-- match end up (AC3), and repeated results: strength, ownership and experience applied once (AC4).
-- The matching two-room scene is faction_war_contest_e2e_runtime_probe.lua.
local STORAGE = "CountryWarProbe108V1"
local original = _FactionWar.TownStorageName
local originalLevelKey = _MonsterLevelStorage.StorageKey
local function await(predicate, tries)
    for _ = 1, tries or 100 do if predicate() then return true end wait(0.1) end
    return false
end
local function readRaw()
    local result, raw, done = nil, nil, false
    _FactionWar:ReadTownsRaw(function(towns, bytes) result, raw, done = towns, bytes, true end)
    assert(await(function() return done end), "town read answered")
    return result, raw
end
local function read() local towns = readRaw() return towns end
local function write(towns)
    local saved = false
    _FactionWar:WriteTowns(towns, function(ok) saved = ok end)
    assert(await(function() return saved end), "town write confirmed")
end
local function seed(owners, strengths, epochs, settled)
    local towns = _FactionWar:InitialTowns()
    for id, owner in pairs(owners or {}) do towns[id].owner = owner end
    for id, strength in pairs(strengths or {}) do towns[id].strength = strength end
    for id, epoch in pairs(epochs or {}) do towns[id].e = epoch end
    -- The engine's JSONEncode rejects an empty table, so an empty history is stored as no field at all.
    if settled ~= nil and #settled > 0 then towns.settled = settled end
    write(towns)
end
local function copyDoc(towns) return _HttpService:JSONDecode(_HttpService:JSONEncode(towns)) end
-- Starts a settlement and returns its box; box.status / box.outcome are filled when it reports.
local function begin(matchKey, home, away, homeResult, kind, snapshot)
    local box = { done = false }
    _FactionWarAttack:Settle(matchKey, home, away, homeResult, kind or "HUMAN", function(status, detail, outcome)
        box.status, box.detail, box.outcome, box.done = status, detail, outcome, true
    end, snapshot)
    return box
end
local function finish(box, key)
    assert(await(function() return box.done end, 250), "settlement completed " .. key)
    return box.status, box.detail, box.outcome
end
local function settle(matchKey, home, away, homeResult, kind, snapshot)
    return finish(begin(matchKey, home, away, homeResult, kind, snapshot), matchKey)
end
local function swap(expected, towns)
    local result, done = nil, false
    _FactionWar:SwapTowns(expected, towns, function(r) result, done = r, true end)
    assert(await(function() return done end), "swap answered")
    return result
end
local function stamp(key, home, away)
    local snapshot = _FactionWarAttack:Snapshot({ key = key, homeOrigin = home, awayOrigin = away })
    assert(type(snapshot) == "table", "the board was readable for the stamp " .. key)
    return snapshot
end

local ok, reason = pcall(function()
    local war, attack = _FactionWar, _FactionWarAttack

    -- Pure rules: the count, its decoder, the stamp.
    assert(war:EpochOf(war:InitialTowns(), "gushan") == 0 and war:EpochOf(nil, "gushan") == 0 and war:EpochOf({}, "gushan") == 0, "no count reads as zero")
    local counted = war:InitialTowns()
    counted.gushan.e = 2
    assert(war:EpochOf(counted, "gushan") == 2 and war:DecodeTowns(_HttpService:JSONEncode(counted)) ~= nil, "a stored count is read back")
    for label, value in pairs({ negative = -1, fraction = 1.5, text = "1" }) do
        local bad = war:InitialTowns()
        bad.gushan.e = value
        assert(war:DecodeTowns(_HttpService:JSONEncode(bad)) == nil, "a " .. label .. " count makes the document unreadable")
    end
    local combined = attack:Combine({ homeEpoch = 2, awayEpoch = 3 }, { homeEpoch = 1, awayEpoch = 5 })
    assert(combined.home == 1 and combined.away == 3, "the earlier reading of each town decides")
    local alone = attack:Combine({ homeEpoch = 0, awayEpoch = 0 }, nil)
    assert(alone.home == 0 and alone.away == 0, "one stamped ticket is enough, and a zero count is a count")
    assert(attack:Combine(nil, { homeOrigin = "zuoying" }) == nil and attack:Combine(nil, nil) == nil, "tickets without a stamp give no stamp")
    local board = war:InitialTowns()
    board.gushan.e = 1
    assert(attack:ChangedSince({ home = 0, away = 0 }, "zuoying", "gushan", board) == true, "Gushan changed hands since the pairing")
    assert(attack:ChangedSince({ home = 0, away = 1 }, "zuoying", "gushan", board) == false, "an equal count is no change")
    assert(attack:ChangedSince(nil, "zuoying", "gushan", board) == false and attack:ChangedSince(false, "zuoying", "gushan", board) == false, "no stamp is no exemption")
    local pairing = { key = "k", homeOrigin = "zuoying", awayOrigin = "gushan" }
    local stamped = attack:Stamped(pairing, { home = 0, away = 1 })
    assert(stamped ~= pairing and stamped.homeEpoch == 0 and stamped.awayEpoch == 1 and stamped.key == "k" and pairing.homeEpoch == nil, "the stamp goes on a copy")
    assert(attack:Stamped(pairing, false) == pairing, "no stamp leaves the pairing alone")
    assert(attack:Snapshot({ key = "lobby", homeOrigin = "", awayOrigin = "" }) == false, "a lobby pairing has nothing to stamp")

    _FactionWar.TownStorageName = STORAGE
    _DataStorageService:DeleteGlobalDataStorageAndWait(STORAGE)

    -- The stored bytes arbitrate: a stale swap loses, and an absent document is created by exactly one of two first writers.
    seed({}, { gushan = 20 })
    local towns, raw = readRaw()
    local first, second = copyDoc(towns), copyDoc(towns)
    first.gushan.strength = 10
    second.gushan.strength = 5
    assert(swap(raw, first) == "OK", "a swap on the bytes that were read succeeds")
    assert(swap(raw, second) == "CONFLICT", "a swap on bytes that have since changed is a conflict")
    assert(read().gushan.strength == 10, "the loser changed nothing")
    _DataStorageService:DeleteGlobalDataStorageAndWait(STORAGE)
    local _, absent = readRaw()
    assert(absent == nil, "nothing stored after the delete")
    local x, y = nil, nil
    _FactionWar:SwapTowns(nil, war:InitialTowns(), function(result) x = result end)
    _FactionWar:SwapTowns(nil, war:InitialTowns(), function(result) y = result end)
    assert(await(function() return x ~= nil and y ~= nil end, 200), "both first writers answered")
    assert((x == "OK") ~= (y == "OK") and (x == "CONFLICT" or y == "CONFLICT"), "exactly one first creation wins, got " .. tostring(x) .. "/" .. tostring(y))
    log("[VRF][FactionWarContest] swap primitives ok first=" .. tostring(x) .. " second=" .. tostring(y))

    -- AC1: two human wins over Gushan at 20 settle at the same moment (writes delayed so both read the same bytes).
    seed({}, { gushan = 20 })
    local shared = stamp("c108-race", "zuoying", "gushan")
    assert(shared.home == 0 and shared.away == 0, "both matches were paired on the same board")
    _FormationStorage:ConfigureMakerFaults(0, 0, 1)
    local boxA = begin("c108-race-a", "zuoying", "gushan", "WIN", "HUMAN", shared)
    local boxB = begin("c108-race-b", "zuoying", "gushan", "WIN", "HUMAN", shared)
    local statusA, _, outcomeA = finish(boxA, "c108-race-a")
    local statusB, _, outcomeB = finish(boxB, "c108-race-b")
    _FormationStorage:ConfigureMakerFaults(0, 0, 0)
    assert((statusA == "SAVED") ~= (statusB == "SAVED") and (statusA == "EXEMPT") ~= (statusB == "EXEMPT"), "one settles, one is exempt, got " .. statusA .. "/" .. statusB)
    local winner, loser = outcomeA, outcomeB
    local winnerKey = "c108-race-a"
    if statusB == "SAVED" then winner, loser, winnerKey = outcomeB, outcomeA, "c108-race-b" end
    assert(winner.flipped == true and winner.owner == "RED" and winner.strength == 100, "the settling match took Gushan")
    assert(loser.flipped == false and loser.owner == "" and loser.amount == 20, "the other kept its result but changed no town")
    towns = read()
    assert(towns.gushan.owner == "RED" and towns.gushan.strength == 100 and war:EpochOf(towns, "gushan") == 1, "Gushan is red, full, and counted once")
    assert(towns.zuoying.strength == 100 and war:EpochOf(towns, "zuoying") == 0 and towns.nanzih.strength == 100 and towns.yancheng.strength == 100, "no other town moved")
    assert(#towns.settled == 1 and towns.settled[1].k == winnerKey, "exactly one record, the settling match's")
    log("[VRF][FactionWarContest] race ok settled=" .. winnerKey .. " statuses=" .. statusA .. "/" .. statusB)

    -- Overlapping settlements that do not flip: the loser of the swap reads again and still deducts (no lost update).
    seed({}, { gushan = 60 })
    local plain = stamp("c108-plain", "zuoying", "gushan")
    _FormationStorage:ConfigureMakerFaults(0, 0, 1)
    local plainA = begin("c108-plain-a", "zuoying", "gushan", "WIN", "HUMAN", plain)
    local plainB = begin("c108-plain-b", "zuoying", "gushan", "WIN", "HUMAN", plain)
    local pa = finish(plainA, "c108-plain-a")
    local pb = finish(plainB, "c108-plain-b")
    _FormationStorage:ConfigureMakerFaults(0, 0, 0)
    towns = read()
    assert(pa == "SAVED" and pb == "SAVED" and towns.gushan.strength == 20 and towns.gushan.owner == "BLUE" and #towns.settled == 2, "both wins counted once each: 60 -> 20")

    -- AC2: a match paired before Gushan changed hands deducts nothing, even after the town is taken back.
    seed({}, { gushan = 20 })
    local early = stamp("c108-late", "zuoying", "gushan")
    assert(settle("c108-flip", "zuoying", "gushan", "WIN", "HUMAN", early) == "SAVED" and read().gushan.owner == "RED", "another match flipped Gushan")
    for index = 1, 5 do
        local fresh = stamp("c108-back" .. index, "yancheng", "gushan")
        assert(fresh.away == 1, "paired after the flip, the town counts once")
        assert(settle("c108-back" .. index, "yancheng", "gushan", "WIN", "HUMAN", fresh) == "SAVED", "counter-attack " .. index)
    end
    towns = read()
    assert(towns.gushan.owner == "BLUE" and towns.gushan.strength == 100 and war:EpochOf(towns, "gushan") == 2, "blue took Gushan back: same owner as at pairing, counted twice")
    local _, before = readRaw()
    local status, _, outcome = settle("c108-late", "zuoying", "gushan", "WIN", "HUMAN", early)
    local _, after = readRaw()
    assert(status == "EXEMPT" and outcome.flipped == false and outcome.amount == 20, "the early match is exempt although the owner looks unchanged, got " .. tostring(status))
    assert(before == after, "an exempt match writes nothing")
    assert(attack._T.outcomes["c108-late"].flipped == false, "the room remembers it as an outcome that changed no town")
    -- AC3: where the players of that match end up on the live board.
    assert(war:Landing("RED", "zuoying", towns) == "zuoying", "red stays where it fought: Zuoying is still its own")
    assert(war:Landing("BLUE", "gushan", towns) == "gushan", "blue stays in Gushan: it owns it again")
    log("[VRF][FactionWarContest] flip-and-retake ok epoch=" .. tostring(war:EpochOf(towns, "gushan")))

    -- The board where both towns of a match changed hands: the stamp keeps the wrong faction from taking a town.
    seed({ zuoying = "BLUE", gushan = "RED" }, {}, { zuoying = 1, gushan = 1 })
    local old = { home = 0, away = 0 }
    local _, swapped = readRaw()
    status, _, outcome = settle("c108-both", "zuoying", "gushan", "WIN", "HUMAN", old)
    local _, unchanged = readRaw()
    assert(status == "EXEMPT" and swapped == unchanged, "both towns changed hands: nothing is written")
    towns = read()
    assert(towns.gushan.owner == "RED" and towns.zuoying.owner == "BLUE", "neither town moved to the wrong faction")
    -- AC3 on this board: the old red home player (origin Zuoying, now blue) goes to its capital, the old blue player (Gushan, now red) to its capital.
    assert(war:Landing("RED", "zuoying", towns) == "nanzih" and war:Landing("BLUE", "gushan", towns) == "yancheng", "players of an exempt match whose town is now the enemy's go to their capital")

    -- AC4: a repeated result changes nothing and answers the same capture; the experience of a repeated result is credited once.
    seed({}, { gushan = 20 })
    local once = stamp("c108-once", "zuoying", "gushan")
    local firstStatus, _, firstOutcome = settle("c108-once", "zuoying", "gushan", "WIN", "HUMAN", once)
    assert(firstStatus == "SAVED" and firstOutcome.flipped == true, "first delivery flips")
    local _, afterFirst = readRaw()
    local repeatStatus, _, repeatOutcome = settle("c108-once", "zuoying", "gushan", "WIN", "HUMAN", once)
    local _, afterRepeat = readRaw()
    assert(repeatStatus == "DUPLICATE" and repeatOutcome.flipped == true and repeatOutcome.owner == "RED" and repeatOutcome.strength == 100, "the repeat is the same capture")
    assert(afterFirst == afterRepeat, "the repeat wrote nothing")
    assert(settle("c108-after", "yancheng", "gushan", "WIN", "HUMAN", stamp("c108-after", "yancheng", "gushan")) == "SAVED" and read().gushan.strength == 80, "the town moved on")
    local lateStatus, _, lateOutcome = settle("c108-once", "zuoying", "gushan", "WIN", "HUMAN", once)
    assert(lateStatus == "DUPLICATE" and lateOutcome.flipped == true and read().gushan.strength == 80, "a repeat after the world moved on still answers the capture and takes no further strength")
    -- A write that fails twice is retried until it lands once; one that never lands is reported and leaves the document alone.
    local fresh = stamp("c108-retry", "yancheng", "gushan")
    local settledBefore = #read().settled
    _FormationStorage:ConfigureMakerFaults(0, 2, 0)
    assert(settle("c108-retry", "yancheng", "gushan", "WIN", "HUMAN", fresh) == "SAVED", "two failed writes are retried")
    _FormationStorage:ConfigureMakerFaults(0, 0, 0)
    towns = read()
    assert(#towns.settled == settledBefore + 1 and towns.gushan.strength == 60, "and applied exactly once")
    local _, beforeFail = readRaw()
    _FormationStorage:ConfigureMakerFaults(0, 20, 0)
    assert(settle("c108-fail", "yancheng", "gushan", "WIN", "HUMAN", stamp("c108-fail", "yancheng", "gushan")) == "FAILED", "a write that never lands is reported failed")
    _FormationStorage:ConfigureMakerFaults(0, 0, 0)
    local _, afterFail = readRaw()
    assert(beforeFail == afterFail, "a failed settlement invents nothing")
    assert(settle("c108-fail", "yancheng", "gushan", "WIN", "HUMAN", fresh) == "SAVED" and read().gushan.strength == 40, "its redelivery applies once")
    -- Experience: the same match id credits a monster once.
    _MonsterLevelStorage.StorageKey = "Issue108Levels_" .. _UtilLogic:NewGuid()
    local profile = _UserService.UserEntities.Values[1].PlayerComponent.ProfileCode
    local function credit()
        local operation = _MonsterLevelStorage:Settle(profile, "c108-exp", { monster_tank = 2 })
        assert(await(function() return operation.status ~= "PENDING" end, 100), "experience settlement completed")
        return operation
    end
    local function experience()
        local code, document, done = nil, nil, false
        _MonsterLevelStorage:Read(profile, function(c, d) code, document, done = c, d, true end)
        assert(await(function() return done end) and code == 0, "levels read")
        return document.monsters.monster_tank.level * 1000 + document.monsters.monster_tank.experience
    end
    local creditFirst = credit()
    local progress = experience()
    local creditRepeat = credit()
    assert(creditFirst.status == "SAVED" and creditRepeat.status == "SAVED" and creditRepeat.duplicate == true and experience() == progress, "the repeated result credits no second experience")
    _DataStorageService:GetUserDataStorage(profile):DeleteAndWait(_MonsterLevelStorage.StorageKey)

    -- The document with its counts stays under one storage credit with a full history.
    local history = {}
    for index = 1, attack.SettledHistory do
        table.insert(history, { k = "c108-size" .. index .. "-" .. _UtilLogic:NewGuid(), w = "zuoying", l = "gushan", s = 60, o = index % 2 == 0 and "RED" or "" })
    end
    seed({ gushan = "BLUE", zuoying = "RED" }, { gushan = 60, zuoying = 60 }, { gushan = 12, zuoying = 12 }, history)
    local _, big = readRaw()
    assert(big ~= nil and #big < 4000, "the town document stays under 4000 bytes, bytes=" .. tostring(big ~= nil and #big or -1))
    log("[VRF][FactionWarContest] document bytes=" .. tostring(#big))
end)

_FormationStorage:ConfigureMakerFaults(0, 0, 0)
_FactionWar.TownStorageName = original
_MonsterLevelStorage.StorageKey = originalLevelKey
_DataStorageService:DeleteGlobalDataStorageAndWait(STORAGE)
if ok then log("[VRF][FactionWarContest] PROBE PASS") else log_error("[VRF][FactionWarContest] PROBE FAIL " .. tostring(reason)) end
