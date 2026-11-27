-- Run from faction_id_legacy_local.cjs. ADR 0018 / #125.
-- This is the only test file that may contain the retired ids "RED" / "BLUE" (faction_id_contract.test.cjs enforces it): it feeds them to
-- every place that reads a stored faction value, where they must come back as "A" / "B", and checks that nothing new is ever written with them.
local town, war, absent = _FactionWarTownDocument, _FactionWar, _AbsentResult
local checks = 0
local function check(condition, label) checks = checks + 1; assert(condition, label) end

-- Storage stand-in: values are opaque bytes; a swap succeeds only against the exact bytes that are stored.
local store, snapshots, swaps = {}, {}, {}
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = copy(v) end
    return result
end
local function bytesOf(value) table.insert(snapshots, copy(value)); return "bytes" .. tostring(#snapshots) end
local function valueOf(raw) return copy(assert(snapshots[tonumber(string.sub(raw, 6))], "invalid bytes")) end
_HttpService = {
    JSONEncode = function(_, value) return bytesOf(value) end,
    JSONDecode = function(_, raw) return valueOf(raw) end,
}
local failReads = false
_FormationStorage = {
    GlobalPrefix = "global:",
    Read = function(_, owner, key, complete)
        if failReads then complete(1000004, key, nil) return end
        local raw = store[owner .. "/" .. key]
        if raw == nil then complete(1000002, key, nil) else complete(0, key, raw) end
    end,
    Swap = function(_, owner, key, expected, replacement, complete)
        local slot = owner .. "/" .. key
        table.insert(swaps, { expected = expected, replacement = replacement })
        if store[slot] ~= expected then complete(2000000) return end
        store[slot] = replacement
        complete(0)
    end,
}
DateTime = { UtcNow = { Elapsed = 0 } }
_UtilLogic = { RandomDouble = function() return 0 end }
_TimerService = { SetTimerOnce = function() return 1 end, ClearTimer = function() end }
town:OnBeginPlay()

-- 1. The one converter: the retired colour ids become A / B, A / B pass through, anything else is no faction.
check(town:NormalizeFaction("RED") == "A" and town:NormalizeFaction("BLUE") == "B", "the retired ids convert")
check(town:NormalizeFaction("A") == "A" and town:NormalizeFaction("B") == "B", "the new ids pass through")
for _, other in ipairs({ "", "red", "Blue", "C", "A ", "AB", "GREEN" }) do check(town:NormalizeFaction(other) == nil, "invalid: " .. other) end
check(town:NormalizeFaction(nil) == nil and town:NormalizeFaction(1) == nil and town:NormalizeFaction({}) == nil, "not a string")

-- 2. The player's own faction (CountryWarFactionV1).
local function readFaction(raw)
    store["profile/" .. war.FactionKey] = raw
    local answered, answer = false, nil
    war:ReadFaction("profile", function(value) answered, answer = true, value end)
    assert(answered, "ReadFaction must answer")
    return answer
end
check(readFaction("RED") == "A" and readFaction("BLUE") == "B", "a stored retired id reads as the new id")
check(readFaction("A") == "A" and readFaction("B") == "B", "a stored new id reads as itself")
check(readFaction(nil) == "", "nothing stored yet is the empty faction")
check(readFaction("GREEN") == nil and readFaction("") == nil, "a stored value that is no faction is unreadable")
failReads = true
check(readFaction("RED") == nil, "a failed storage read is unreadable, not a faction")
failReads = false

-- 3. The town document (CountryWarV1 / Towns).
local TOWNS = "global:CountryWarV1/Towns"
local function legacyBoard()
    return {
        nanzih = { owner = "RED", strength = 100 }, zuoying = { owner = "RED", strength = 100, e = 1 },
        gushan = { owner = "BLUE", strength = 10, e = 2 }, yancheng = { owner = "BLUE", strength = 100 },
    }
end
local function readBoard(raw)
    store[TOWNS] = raw
    local answered, board = false, nil
    town:Read(function(value) answered, board = true, value end)
    assert(answered, "Read must answer")
    return board
end
local board = readBoard(bytesOf(legacyBoard()))
check(board ~= nil and board.nanzih.owner == "A" and board.zuoying.owner == "A" and board.gushan.owner == "B" and board.yancheng.owner == "B", "a legacy document reads with the new owners")
check(board.zuoying.e == 1 and board.gushan.e == 2 and board.gushan.strength == 10, "everything but the owner is kept")
local mixed = legacyBoard()
mixed.zuoying.owner, mixed.yancheng.owner = "A", "B"
board = readBoard(bytesOf(mixed))
check(board ~= nil and board.zuoying.owner == "A" and board.nanzih.owner == "A" and board.yancheng.owner == "B", "old and new owners may be mixed in one document")
local fresh = legacyBoard()
for _, id in ipairs(town.TownOrder) do fresh[id].owner = (id == "nanzih" or id == "zuoying") and "A" or "B" end
check(readBoard(bytesOf(fresh)).gushan.owner == "B", "a new-format document reads as itself")
local invalid = legacyBoard()
invalid.gushan.owner = "GREEN"
check(readBoard(bytesOf(invalid)) == nil, "an owner that is no faction makes the document unreadable")
invalid = legacyBoard()
invalid.nanzih.owner = "BLUE"
check(readBoard(bytesOf(invalid)) == nil, "a capital owned by the other faction is still unreadable")
check(readBoard(nil).gushan.owner == "B" and readBoard(nil).nanzih.owner == "A", "a world without a document starts with the new ids")

-- 4. The settled outcome record inside the document.
local function outcomeOf(owner)
    local source = legacyBoard()
    source.settled = { { k = "m", w = "zuoying", l = "gushan", s = 100, o = owner } }
    return town:OutcomeFrom(readBoard(bytesOf(source)), "m")
end
local outcome = outcomeOf("RED")
check(outcome.owner == "A" and outcome.flipped == true and outcome.loser == "gushan", "a settled capture by the retired id reads as the new id")
check(outcomeOf("BLUE").owner == "B" and outcomeOf("A").owner == "A" and outcomeOf("B").owner == "B", "BLUE reads as B, A and B as themselves")
outcome = outcomeOf("")
check(outcome.owner == "" and outcome.flipped == false, "a settlement without a capture has no owner")
outcome = outcomeOf("GREEN")
check(outcome.owner == "" and outcome.flipped == false, "an owner that is no faction claims no capture")
local summary = town:Summarize("zuoying", "gushan", "A", outcomeOf("RED"), nil)
check(summary.newOwner == "A" and summary.conclusion == "奪城：鼓山 改為 A 方", "the capture text names the faction as A / B")

-- 5. Settling over a legacy document: the swap is made against the bytes that were read, and what is written has the new ids only.
local legacyRaw
do
    local source = legacyBoard()
    source.settled = { { k = "old-capture", w = "zuoying", l = "gushan", s = 100, o = "RED", wb = 100, wa = 100, lb = 20 }, { k = "old-hit", w = "gushan", l = "zuoying", s = 90, o = "" } }
    legacyRaw = bytesOf(source)
end
store[TOWNS] = legacyRaw
local settled
town:Settle({ matchKey = "new-capture", home = "zuoying", away = "gushan", result = "WIN", kind = "HUMAN", snapshot = { home = 1, away = 2 } },
    function(status, detail, result) settled = { status = status, outcome = result } end)
check(settled ~= nil and settled.status == "SAVED" and settled.outcome.flipped == true, "the legacy document is settled")
check(#swaps == 1 and swaps[1].expected == legacyRaw, "the swap expects the exact bytes that were read, not a re-encoding")
local written = valueOf(store[TOWNS])
for _, id in ipairs(town.TownOrder) do check(written[id].owner == "A" or written[id].owner == "B", "written owner of " .. id .. " is A or B") end
check(written.gushan.owner == "A" and written.gushan.strength == 100 and written.gushan.e == 3, "the captured town is the winner's, written as A")
check(written.nanzih.owner == "A" and written.yancheng.owner == "B", "untouched towns are rewritten with the new ids")
check(#written.settled == 3 and written.settled[1].o == "A" and written.settled[2].o == "" and written.settled[3].o == "A", "the history is rewritten with the new ids too")
check(valueOf(legacyRaw).gushan.owner == "BLUE", "the stored legacy bytes themselves were never changed in place")
check(town:OutcomeFrom(written, "old-capture").owner == "A" and town:OutcomeFrom(written, "new-capture").owner == "A", "both captures still read back")

-- 6. The absent result record (AbsentResultV1).
local function absentWar(newOwner)
    local record = { v = 1, id = "m1", kind = "WAR", result = "WIN",
        war = { origin = "zuoying", target = "gushan", status = "SAVED", conclusion = "奪城：鼓山 改為 紅方", capturedTown = "gushan", newOwner = newOwner } }
    store["profile/" .. absent.StorageKey] = bytesOf(record)
    local answered, found, readable = false, nil, nil
    absent:Read("profile", function(value, _, ok) answered, found, readable = true, value, ok end)
    assert(answered, "Read must answer")
    return found, readable
end
local record = absentWar("RED")
check(record ~= nil and record.war.newOwner == "A", "an absent result stored with the retired id reads as the new id")
check(absentWar("BLUE").war.newOwner == "B" and absentWar("A").war.newOwner == "A" and absentWar("B").war.newOwner == "B", "BLUE reads as B, A and B as themselves")
record = absentWar(nil)
check(record ~= nil and record.war.newOwner == nil, "a result without a capture has no new owner")
record = absentWar("GREEN")
check(record ~= nil and record.war.newOwner == nil and record.war.capturedTown == "gushan", "a new owner that is no faction is dropped, the rest of the result stays readable")
check(absentWar("RED").war.conclusion == "奪城：鼓山 改為 紅方", "an already composed conclusion is shown as it was stored (known gap, ADR 0018)")

log("[VRF][FactionId] legacy values at every read point PASS checks=" .. tostring(checks))
print("[VRF][FactionId] legacy values at every read point PASS checks=" .. tostring(checks))
