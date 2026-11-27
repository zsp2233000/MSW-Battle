// Emit the production town-document script with its declaration syntax lowered to Lua 5.3.
// Run: node tests/faction_war_town_document_local.cjs | npm exec --yes --package=fengari-node-cli@0.1.0 -- fengari -
// This is not an MSW transpiler or a Maker runtime check. Only the type/declaration syntax of this module is lowered.
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const doc = readFileSync(join(__dirname, '../RootDesk/MyDesk/Formations/FactionWarTownDocument.mlua'), 'utf8')
  .replace(/\r\n/g, '\n')
  .replace(/^@Logic\nscript FactionWarTownDocument extends Logic\n/, 'local doc = { _T = {} }\n')
  .replace(/^    @ExecSpace\("ServerOnly"\)\n/gm, '')
  .replace(/^    property \w+ (\w+ = .+)$/gm, 'doc.$1')
  .replace(/^    method \w+ (\w+)\(([^)]*)\)$/gm, (_, name, params) =>
    `function doc:${name}(${params.replace(/\b\w+ (\w+)/g, '$1')})`)
  .replace(/\nend\s*$/, '\n_FactionWarTownDocument = doc');
const rules = readFileSync(join(__dirname, 'faction_war_town_document_rules.lua'), 'utf8');
const matchedBattle = readFileSync(join(__dirname, '../RootDesk/MyDesk/Matchmaking/MatchedBattle.mlua'), 'utf8')
  .replace(/\r\n/g, '\n')
  .replace(/^@Component\nscript MatchedBattle extends Component\n/, 'local matchedBattle = {}\n')
  .replace(/^    @\w+\([^\n]*\)\n/gm, '')
  .replace(/^    (?:@Sync )?property \w+ (\w+ = .+)$/gm, 'matchedBattle.$1')
  .replace(/^    (?:method \w+ |handler )(\w+)\(([^)]*)\)$/gm, (_, name, params) =>
    `function matchedBattle:${name}(${params.replace(/\b\w+ (\w+)/g, '$1')})`)
  .replace(/\nend\s*$/, '');
const receiptRules = readFileSync(join(__dirname, 'faction_war_result_receipt_rules.lua'), 'utf8');
const { participantSideLua } = require('./participant_side_source.cjs');
process.stdout.write(`local ok, failure = xpcall(function()\nlog = print\n${doc}\ndo\n${rules}\nend\n`);
process.stdout.write(String.raw`
-- Storage stand-in: encoded values are opaque bytes. A fresh serialization of the same table
-- has different bytes, so using re-encoded data as CAS's expectation fails this test.
local bytes, snapshots = nil, {}
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = copy(v) end
    return result
end
_HttpService = {
    JSONEncode = function(_, value)
        table.insert(snapshots, copy(value))
        return tostring(#snapshots)
    end,
    JSONDecode = function(_, value) return copy(assert(snapshots[tonumber(value)], "invalid fixture bytes")) end
}
DateTime = { UtcNow = { Elapsed = 0 } }
_UtilLogic = { RandomDouble = function() return 0 end }
local timers, timerId = {}, 0
_TimerService = {
    SetTimerOnce = function(_, fn, delay)
        timerId = timerId + 1
        timers[timerId] = { fn = fn, delay = delay }
        return timerId
    end,
    ClearTimer = function(_, id) timers[id] = nil end
}
local function tick(delay)
    local id, job = next(timers)
    assert(job and math.abs(job.delay - delay) < 0.000001, "unexpected retry delay")
    timers[id] = nil
    DateTime.UtcNow.Elapsed = DateTime.UtcNow.Elapsed + job.delay * 1000
    job.fn()
end
local reads, commits, timeouts, lostReply = 0, 0, 0, false
local hold, pending = false, {}
_FormationStorage = {
    GlobalPrefix = "global:",
    Read = function(_, owner, key, complete)
        assert(owner == "global:CountryWarV1" and key == "Towns")
        reads = reads + 1
        complete(bytes and 0 or 1000002, key, bytes)
    end,
    Swap = function(_, owner, key, expected, replacement, complete)
        assert(owner == "global:CountryWarV1" and key == "Towns")
        local function write()
            if timeouts > 0 then timeouts = timeouts - 1; complete(1000004); return end
            if expected ~= (bytes or "") then complete(expected == "" and 1000007 or 2000000); return end
            bytes, commits = replacement, commits + 1
            complete(lostReply and 1000004 or 0)
        end
        if hold then table.insert(pending, write) else write() end
    end
}
local function seed(strength)
    local board = doc:InitialTowns()
    board.gushan.strength = strength
    bytes = _HttpService:JSONEncode(board)
end
local function read()
    local board
    doc:Read(function(value, raw) assert(raw == nil, "public read leaked stored bytes"); board = value end)
    return board
end
local function settle(key, options)
    options = options or {}
    local result = {}
    doc:Settle({ matchKey = key, home = "zuoying", away = options.away or "gushan", result = "WIN", kind = "HUMAN",
        snapshot = options.snapshot or { home = 0, away = 0 } }, function(status, detail, outcome)
        assert(result.status == nil, "completion ran twice")
        result.status, result.detail, result.outcome = status, detail, outcome
    end)
    return result
end
local function race(first, second)
    hold = true
    local a, b = settle(first), settle(second)
    assert(doc:IsSettling(first) and doc:IsSettling(second))
    assert(#pending == 2 and a.status == nil and b.status == nil)
    hold = false
    for _, commit in ipairs(pending) do commit() end
    pending = {}
    assert(not doc:IsSettling(first) and doc:IsSettling(second))
    tick(0.15)
    assert(not doc:IsSettling(second))
    return a, b
end

doc:OnBeginPlay()
assert(read().gushan.strength == 100 and commits == 0, "missing reads must not seed storage")
local before = reads
assert(settle("capital", { away = "yancheng" }).status == "NO_CHANGE" and reads == before)
local a, b = race("create-a", "create-b")
assert(a.status == "SAVED" and b.status == "SAVED" and b.outcome.conflicts == 1)
assert(read().gushan.strength == 60 and commits == 2, "both first-creation deductions must survive")
assert(a.outcome.winnerBefore == 100 and a.outcome.winnerAfter == 100 and a.outcome.loserBefore == 100 and a.outcome.loserAfter == 80)
assert(b.outcome.loserBefore == 80 and b.outcome.loserAfter == 60, "retry must use the committed CAS input, not its first read")
local replay = settle("create-a").outcome
assert(replay.status == "DUPLICATE" and replay.loserBefore == 100 and replay.loserAfter == 80, "later writes cannot change saved history")

seed(20)
a, b = race("capture-a", "capture-b")
assert(a.status == "SAVED" and a.outcome.flipped and a.detail == 100)
assert(b.status == "EXEMPT" and b.outcome.conflicts == 1 and not b.outcome.flipped)
local board = read()
assert(board.gushan.owner == "A" and board.gushan.e == 1 and #board.settled == 1 and commits == 3)
assert(a.outcome.loserBefore == 20 and a.outcome.loserAfter == 100 and b.outcome.loserBefore == nil)
local captured = doc:OutcomeFrom(board, "capture-a")
assert(captured.loserBefore == 20 and captured.loserAfter == 100 and captured.winnerBefore == 100 and captured.winnerAfter == 100)
assert(settle("capture-a").status == "DUPLICATE" and commits == 3)

seed(20)
lostReply = true
local lost = settle("lost-reply")
assert(lost.status == nil and commits == 4)
lostReply = false
tick(1)
assert(lost.status == "DUPLICATE" and lost.outcome.flipped and commits == 4)

seed(100)
timeouts = 4
local failed = settle("unavailable")
for _ = 1, 3 do tick(1) end
assert(failed.status == "FAILED" and not doc:IsSettling("unavailable") and read().gushan.strength == 100)
assert(next(timers) == nil and commits == 4 and failed.outcome.loserBefore == nil and failed.outcome.loserAfter == nil)

seed(100)
hold = true
local crowded = settle("crowded")
local delay = 0.15
for _ = 1, 12 do
    seed(100) -- Different bytes even while the record is semantically unchanged.
    table.remove(pending, 1)()
    tick(delay)
    delay = math.min(1, delay * 2)
end
hold = false
table.remove(pending, 1)()
assert(crowded.status == "SAVED" and crowded.outcome.conflicts == 12 and commits == 5)

seed(100)
hold = true
local budget = settle("conflict-budget")
DateTime.UtcNow.Elapsed = DateTime.UtcNow.Elapsed + 20000
seed(100)
table.remove(pending, 1)()
hold = false
assert(budget.status == "FAILED" and budget.outcome.conflicts == 1 and next(timers) == nil and commits == 5)

local invalid = doc:InitialTowns()
invalid.gushan.strength = 0
bytes = _HttpService:JSONEncode(invalid)
assert(read() == nil)
invalid.gushan.strength, invalid.gushan.e = 100, -1
bytes = _HttpService:JSONEncode(invalid)
assert(read() == nil)
invalid.gushan.e, invalid.nanzih.owner = nil, "B"
bytes = _HttpService:JSONEncode(invalid)
assert(read() == nil)
bytes = "undecodable"
assert(read() == nil)

seed(100)
timeouts = 1
local abandoned = settle("shutdown")
assert(doc:IsSettling("shutdown"))
doc:OnEndPlay()
assert(abandoned.status == nil and next(timers) == nil and not doc:IsSettling("shutdown"))
log("[VRF][FactionWarTownDocument] local storage seam PASS")

-- The full history, using native m30 match-key lengths, must still fit a compact storage value.
local function compactSize(value)
    if type(value) == "string" then return #value + 2 end -- all strings in this fixture are plain ASCII
    if type(value) ~= "table" then return #tostring(value) end
    local size, fields = 2, 0
    for key, field in pairs(value) do
        size = size + compactSize(field) + (type(key) == "string" and compactSize(key) + 1 or 0)
        fields = fields + 1
    end
    return size + math.max(0, fields - 1)
end
local full = doc:InitialTowns()
for index = 1, 21 do
    full.gushan = { owner = "B", strength = 20, e = 99999 + index }
    local key = "m30-" .. string.format("%032x", index) .. "-" .. string.rep("b", 32)
    full = assert(doc:Apply(full, { matchKey = key, home = "zuoying", away = "gushan", result = "WIN", kind = "HUMAN" }).document)
end
assert(#full.settled == 20 and compactSize(full) < 4000, "full strength snapshot history fits the storage limit")
log("[VRF][FactionWarTownDocument] strength record budget PASS bytes=" .. tostring(compactSize(full)))
`);
process.stdout.write(`do\n${matchedBattle}\n${participantSideLua()}\n${receiptRules}\nend\n`);
process.stdout.write(String.raw`
end, debug.traceback)
if not ok then
    io.stderr:write(failure, "\n")
    os.exit(1)
end
`);
