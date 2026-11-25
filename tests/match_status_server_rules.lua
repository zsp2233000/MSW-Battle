-- Local fake I/O for production MatchFlow commands. No Maker or persistent data.
local flow = _MatchFlow
local id, profile, attempt = "requester", "a", "first"
local instance, battle, held, outcome, ticket
local cancels, closes, returns, moves, notices
local cases = 0
local player = { PlayerComponent = { ProfileCode = profile } }
local match = { key = "room", home = profile, away = "b", homeAttempt = attempt }
DateTime = { UtcNow = { Elapsed = 1000 } }
log = function() end
isvalid = function(value) return value ~= nil end
_RoomService = { RoomKey = "room", IsInstanceRoom = function() return instance end }
_UserService = { UserEntities = { Values = {} } }
_HttpService = { JSONEncode = function() return "{}" end }
_FormationHandoff = {
    CanCancel = function() return true end,
    Close = function() closes = closes + 1; return true end,
    BeginReturn = function(_, _, current) returns = returns + 1; current.data.state = "RETURNING"; return true end,
}
function flow:Player(user) assert(user == id); return player end
function flow:Battle() return battle end
function flow:MatchMap() return nil end
function flow:Finish(_, _, _, operation) return operation() end
function flow:Recover() end
function flow:MoveHome() moves = moves + 1; return true end
function flow:PublishState(_, code) table.insert(notices, code) end
local function reset(state)
    cases = cases + 1
    instance, battle, held, outcome = false, nil, nil, true
    DateTime.UtcNow.Elapsed = 1000
    ticket = { data = { state = state, attempt = attempt, profile = profile, matchKey = "room" } }
    flow._T = { records = { [id] = ticket }, busy = {}, failures = {}, guardTimers = {}, moving = {}, closedMatches = {} }
    flow._T.queue = { Lookup = function() return held end, Cancel = function() cancels = cancels + 1; return outcome end }
    cancels, closes, returns, moves, notices = 0, 0, 0, 0, {}
    senderUserId = id
end
local function deniedCancel(expectedAdapterCalls)
    flow:RequestCancel(attempt)
    assert(notices[#notices] == "CANCEL_MATCH_FOUND", "paired cancellation was not rejected")
    assert(cancels == expectedAdapterCalls and closes == 0 and flow._T.records[id] == ticket, "paired ticket was cancelled")
end
reset("QUEUED")
flow:RequestCancel("stale")
assert(cancels == 0)
flow:RequestCancel(attempt)
assert(cancels == 1 and closes == 1 and flow._T.records[id] == nil, "pre-pair cancellation must still close")
reset("SAVING")
deniedCancel(0)
reset("QUEUED")
ticket.guardPairing = match
deniedCancel(0)
reset("QUEUED")
held = match
deniedCancel(0)
reset("QUEUED")
MatchmakingResultCode = { AlreadyMatched = "already paired", Ok = "ok" }
_MatchmakingService = { CancelMatchingAndWait = function() return MatchmakingResultCode.AlreadyMatched end }
outcome = _MatchQueueNative:Cancel(profile)
deniedCancel(1)
reset("QUEUED")
-- Both sides exist in the FIFO's lookup before the other callback can publish its observation.
flow._T.queue.Cancel = function() cancels = cancels + 1; held = match; return true end
deniedCancel(1)
reset("QUEUED")
held = { key = "old-room", home = profile, away = "b", homeAttempt = "old" }
flow:RequestCancel(attempt)
assert(cancels == 1 and closes == 1, "stale lookup must not block the current cancellation")

reset("TRANSFER")
ticket.data.match = { entryDeadline = 31000 }
DateTime.UtcNow.Elapsed = 30999
flow:RequestReturn(attempt)
assert(returns == 0 and notices[#notices] == "ENTRY_IN_PROGRESS", "healthy entry cannot be aborted")
DateTime.UtcNow.Elapsed = 31000
flow:RequestReturn(attempt)
assert(returns == 1, "entry timeout opens the exit")
reset("TRANSFER")
flow:Report(id, { code = "ROOM_MOVE_FAILED" })
flow:RequestReturn(attempt)
assert(returns == 1, "definite movement failure opens the exit")
reset("TRANSFER")
flow._T.closedMatches[ticket.data.matchKey] = true
flow:RequestReturn(attempt)
assert(returns == 1, "a known closed room is a definite failure")
reset("TRANSFER")
flow:Report(id, { code = "ROOM_MOVE_FAILED" })
local beginReturn = _FormationHandoff.BeginReturn
_FormationHandoff.BeginReturn = function() return false end
flow:RequestReturn(attempt)
assert(returns == 0 and notices[#notices] == "RETURN_SAVE_FAILED")
_FormationHandoff.BeginReturn = beginReturn
flow:RequestReturn(attempt)
assert(returns == 1, "a failed return write does not re-lock the entry exit")
reset("SAVING")
ticket.entryDeadline = 31000
flow:Report(id, { code = "HANDOFF_SEAL_FAILED" })
flow:RequestReturn(attempt)
assert(returns == 1, "even an unsealed failed pairing can be left")

local function inRoom(phase)
    instance = true
    battle = { Phase = phase, MatchKey = "room", HomeProfile = profile, AwayProfile = "b",
        IsBattleActive = function(self) return self.Phase == "BATTLE" end,
        ResultForProfile = function() return "WIN" end }
end
reset("IN_ROOM"); inRoom("WAITING")
flow:RequestReturn(attempt)
assert(returns == 0 and moves == 0 and notices[#notices] == "ENTRY_IN_PROGRESS")
reset("IN_ROOM"); inRoom("CONFIG_ERROR")
flow:RequestReturn(attempt)
assert(returns == 1 and moves == 1, "room configuration failure must allow return")
reset("IN_ROOM"); inRoom("BATTLE"); ticket.data.match = { entryDeadline = 1 }
flow:RequestReturn(attempt)
assert(returns == 0 and moves == 0, "even a timed-out ticket cannot abort an active battle")
battle.Phase = "RESULT"
flow:RequestReturn(attempt)
assert(returns == 1 and moves == 1, "result return is unchanged")
print("[VRF][MatchStatus] server command scenarios PASS fixtures=" .. tostring(cases))
