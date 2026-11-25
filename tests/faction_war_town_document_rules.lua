-- Pure rules probe: run in Maker server_main or through faction_war_town_document_local.cjs.
local doc = _FactionWarTownDocument
local board = doc:InitialTowns()
local function battle(key, kind, result, away, home)
    return { matchKey = key, kind = kind or "HUMAN", result = result or "WIN", home = home or "zuoying", away = away or "gushan" }
end

assert(doc:IsCapital("nanzih") and doc:IsCapital("yancheng"))
assert(not doc:IsCapital("zuoying") and not doc:IsCapital("gushan"))
assert(doc:CanPass("RED", "nanzih", "zuoying", board))
assert(not doc:CanPass("RED", "zuoying", "gushan", board))
assert(doc:Landing("RED", "zuoying", board) == "zuoying" and doc:Landing("BLUE", "zuoying", board) == "yancheng")
assert(doc:EpochOf(board, "gushan") == 0)

local hit = doc:Apply(board, battle("human-hit"))
assert(hit.outcome.status == "SAVED" and hit.detail == 80 and not hit.outcome.flipped)
assert(hit.document.gushan.owner == "BLUE" and hit.document.gushan.strength == 80 and hit.document.gushan.e == nil)
assert(board.gushan.strength == 100 and board.settled == nil, "Apply must not change its input")
local loss = doc:Apply(board, battle("human-loss", "HUMAN", "LOSE"))
assert(loss.outcome.loser == "zuoying" and loss.document.zuoying.strength == 80)

board.gushan.strength = 10
board.settled = { "legacy-key", { k = "old-hit", s = 90 } }
local capture = battle("capture", "GUARD")
capture.snapshot = { home = 0, away = 0 }
local flip = doc:Apply(board, capture)
assert(flip.outcome.status == "SAVED" and flip.outcome.flipped and flip.outcome.amount == 10 and flip.detail == 100)
assert(flip.document.gushan.owner == "RED" and flip.document.gushan.strength == 100 and flip.document.gushan.e == 1)
assert(flip.document.zuoying.e == nil and flip.document.zuoying.strength == 100 and board.gushan.strength == 10)
assert(#board.settled == 2 and #flip.document.settled == 3 and flip.document.settled[2] ~= board.settled[2])
local stored = doc:OutcomeFrom(flip.document, "capture")
assert(stored.flipped and stored.owner == "RED" and stored.winner == "zuoying" and stored.loser == "gushan" and stored.strength == 100)
local duplicate = doc:Apply(flip.document, capture)
assert(duplicate.outcome.status == "DUPLICATE" and duplicate.outcome.flipped and duplicate.document == nil and duplicate.detail == nil,
    "a capture's own epoch change must not turn its replay into an exemption")
local legacy = doc:Apply(flip.document, battle("legacy-key"))
assert(legacy.outcome.status == "DUPLICATE" and not legacy.outcome.flipped and legacy.document == nil)

local delayed = battle("delayed")
delayed.snapshot = { home = 0, away = 0 }
for _, changed in ipairs({ "zuoying", "gushan" }) do
    local retaken = doc:InitialTowns()
    retaken[changed].e = 2
    local stale = doc:Apply(retaken, delayed)
    assert(stale.outcome.status == "EXEMPT" and not stale.outcome.flipped and stale.document == nil)
end
assert(doc:Apply(flip.document, battle("unstamped")).outcome.status == "SKIPPED")
assert(doc:Apply(board, battle("same-town", "HUMAN", "WIN", "zuoying")).outcome.status == "SKIPPED")
assert(doc:Apply(board, battle("capital", "HUMAN", "WIN", "yancheng")).outcome.status == "NO_CHANGE")
assert(doc:Apply(board, battle("guard-loss", "GUARD", "LOSE")).outcome.status == "NO_CHANGE")
assert(doc:Apply(board, battle("guard-draw", "GUARD", "DRAW")).outcome.status == "NO_CHANGE")

board = doc:InitialTowns()
board.settled = {}
for i = 1, 20 do board.settled[i] = "old-" .. tostring(i) end
local capped = doc:Apply(board, battle("new")).document
assert(#capped.settled == 20 and capped.settled[1] == "old-2" and doc:OutcomeFrom(capped, "old-1") == nil)
assert(doc:OutcomeFrom(capped, "new").strength == 80 and #board.settled == 20)
log("[VRF][FactionWarTownDocument] pure rules PASS")
