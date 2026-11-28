-- Local fake I/O for production MatchFlow commands. No Maker or persistent data.
local flow = _MatchFlow
local id, profile, attempt = "requester", "a", "first"
local instance, battle, held, outcome, ticket
local cancels, closes, returns, moves, notices
local cases = 0
-- #122: where the player's record stands for the ticket's match (PENDING, CLEARED or nothing); a ticket whose match is in it is over.
local standing = ""
_AbsentResult = { Standing = function() return standing end }
local player = { PlayerComponent = { ProfileCode = profile } }
local match = { key = "room", home = profile, away = "b", homeAttempt = attempt }
DateTime = { UtcNow = { Elapsed = 1000 } }
log = function() end
-- Timers are recorded, never run, until a case fires one on purpose.
local timers = {}
_TimerService = {
    SetTimerOnce = function(_, fn, delay) table.insert(timers, { fn = fn, delay = delay }); return #timers end,
    ClearTimer = function(_, timerId) timers[timerId] = false end,
}
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
local realRecover = flow.Recover
function flow:Recover() end
function flow:MoveHome() moves = moves + 1; return true end
function flow:PublishState(_, code) table.insert(notices, code) end
local function reset(state)
    cases = cases + 1
    instance, battle, held, outcome = false, nil, nil, true
    DateTime.UtcNow.Elapsed = 1000
    ticket = { data = { state = state, attempt = attempt, profile = profile, matchKey = "room" } }
    flow._T = { records = { [id] = ticket }, busy = {}, failures = {}, guardTimers = {}, moving = {}, closedMatches = {}, settledHint = {}, absentChecked = {}, lateTimers = {}, lateRetries = {} }
    standing = ""
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

-- Stop Entry must also finish: the real Recover carries the RETURNING ticket to its restore. A claim that never committed has no
-- match key, and the live ticket still remembers the pairing it recognised (entryDeadline) or, for a guard, its claim (guarding).
local function stopEntry(code, guard)
    reset("SAVING")
    ticket.data.matchKey = ""
    ticket.entryDeadline = 31000
    if guard then ticket.guarding, ticket.guardPairing = true, match end
    local restores = 0
    flow.Recover, flow.RestoreReturning, flow.Settled, flow.IsGuard = realRecover, function() restores = restores + 1 end,
        function() return true end, function() return false end
    flow._T.pendingRecover, flow._T.arrival, flow._T.recoveryTimers = {}, {}, {}
    flow._T.queue.Reclaim = function() return nil end
    _FormationHandoff.OpenForUser = function() return ticket end
    if code ~= nil then flow:Report(id, { code = code }) else DateTime.UtcNow.Elapsed = 31000 end
    flow:RequestReturn(attempt)
    assert(returns == 1 and ticket.data.state == "RETURNING", "Stop Entry writes the return")
    assert(restores == 1, "Stop Entry on an unsealed claim reaches the restore (" .. tostring(code or "timeout") .. ", guard=" .. tostring(guard == true) .. ")")
    flow.Recover = function() end
end
for _, guard in ipairs({ false, true }) do
    stopEntry("HANDOFF_SEAL_FAILED", guard)
    stopEntry("HANDOFF_SAVE_FAILED", guard)
    stopEntry(nil, guard)
end

-- Stand-ins for the methods Recover calls are put on the flow for one case and taken off again, so no case leaks a stub into the next.
local function withStubs(stubs, run)
    local saved = {}
    for name in pairs(stubs) do saved[name] = rawget(flow, name) end
    for name, stub in pairs(stubs) do flow[name] = stub end
    local ok, failure = pcall(run)
    for name in pairs(stubs) do flow[name] = saved[name] end
    if not ok then error(failure, 0) end
end
local function openTicket(state)
    reset(state)
    timers = {}
    ticket.data.expires = 900000
    ticket.entryDeadline = 31000
    DateTime.UtcNow.Elapsed = 40000
    flow._T.pendingRecover, flow._T.arrival, flow._T.recoveryTimers, flow._T.lateTimers, flow._T.lateRetries = {}, {}, {}, {}, {}
    flow._T.queue.Reclaim = function() return nil end
    _FormationHandoff.OpenForUser = function() return ticket end
end

-- ADR 0017 (#121): a side whose entry time ran out, or whose move failed, still walks into a room that lives; Stop Entry, a closed or gone room and a broken handoff are final.
local function lateEntry(label, expectWalksIn, arrange)
    openTicket("TRANSFER")
    local walkIns, room = 0, { alive = true }
    flow._T.transfer = { FindRoom = function() return room.alive and room or nil end }
    withStubs({ Recover = realRecover, Rendezvous = function() walkIns = walkIns + 1 end, Settled = function() return true end, IsGuard = function() return false end,
        Pairing = function() return match end, Belongs = function() return true end, NotifyReady = function() end }, function()
        arrange(room)
        flow:Recover(id)
    end)
    assert((walkIns == 1) == expectWalksIn, "late entry: " .. label .. " walkIns=" .. tostring(walkIns))
    if not expectWalksIn then assert(notices[#notices - 1] == "ENTRY_FAILED" or notices[#notices] == "ENTRY_FAILED", "late entry: " .. label .. " stays failed") end
end
lateEntry("entry time over", true, function() end)
lateEntry("move failed, room alive", true, function() flow:Report(id, { code = "ROOM_MOVE_FAILED" }) end)
lateEntry("Stop Entry pressed", false, function() ticket.entryFailed = true end)
lateEntry("closed room", false, function() flow._T.closedMatches["room"] = true end)
lateEntry("room gone", false, function(room) room.alive = false end)
lateEntry("sealed handoff failed", false, function() flow:Report(id, { code = "HANDOFF_SEAL_FAILED" }) end)
lateEntry("room could not be created", false, function() flow:Report(id, { code = "ROOM_CREATE_FAILED" }) end)
lateEntry("admission could not be saved", false, function() flow:Report(id, { code = "ADMISSION_SAVE_FAILED" }) end)

-- A walk-in whose move failed is tried again by itself a bounded number of times; Stop Entry, a gone room and a broken handoff end it.
local function lateRetry(label, arrange, run)
    openTicket("TRANSFER")
    local walkIns, room = 0, { alive = true }
    flow._T.transfer = { FindRoom = function() return room.alive and room or nil end }
    withStubs({ Recover = realRecover, Rendezvous = function() walkIns = walkIns + 1 end, Settled = function() return true end, IsGuard = function() return false end,
        Pairing = function() return match end, Belongs = function() return true end, NotifyReady = function() end }, function()
        flow:Report(id, { code = "ROOM_MOVE_FAILED" })
        arrange(room)
        flow:Recover(id)
        run(function() return walkIns end, function() local pending = {} for _, timer in pairs(timers) do if timer then table.insert(pending, timer) end end return pending end)
    end)
end
lateRetry("one retry is scheduled, spaced, and walks in again", function() end, function(walkIns, pending)
    assert(walkIns() == 1 and #pending() == 1 and pending()[1].delay == flow.LateEntryRetrySeconds, "a failed move schedules one retry")
    local timer = pending()[1]
    timers = {}
    timer.fn()
    assert(walkIns() == 2, "the retry walks in again")
    assert(#pending() == 1, "and the next retry is scheduled while the move keeps failing")
end)
lateRetry("retries are bounded", function() end, function(walkIns, pending)
    for _ = 1, flow.LateEntryRetries + 3 do
        local timer = pending()[1]
        if timer == nil then break end
        timers = {}
        timer.fn()
    end
    assert(walkIns() == 1 + flow.LateEntryRetries and #pending() == 0, "no more than LateEntryRetries tries: walkIns=" .. tostring(walkIns()))
end)
lateRetry("a ticket that ended before the retry fires is left alone", function() end, function(walkIns, pending)
    local timer = pending()[1]
    timers = {}
    flow._T.records[id] = nil
    timer.fn()
    assert(walkIns() == 1 and #pending() == 0, "a retry does not recover a ticket that is gone")
end)
lateRetry("Stop Entry pressed before the retry fires is final", function() end, function(walkIns, pending)
    local timer = pending()[1]
    timers = {}
    ticket.entryFailed = true
    timer.fn()
    assert(walkIns() == 1 and #pending() == 0, "a stopped entry is not retried")
end)
lateRetry("Stop Entry leaves no retry", function() ticket.entryFailed = true end, function(walkIns, pending)
    assert(walkIns() == 0 and #pending() == 0, "a stopped entry is not retried")
end)
lateRetry("a gone room leaves no retry", function(room) room.alive = false end, function(walkIns, pending)
    assert(walkIns() == 0 and #pending() == 0, "a gone room is not retried")
end)

-- #122: a ticket whose match is in the absent-result record (the room settled without the player) ends at once and restores;
-- a record that was already seen or confirmed ends a ticket that never entered too; a ticket that merely waits costs one record read per interval.
local function absentRecord(label, state, expectEnds, arrange)
    openTicket(state)
    local restores, reads = 0, 0
    _AbsentResult.Standing = function() reads = reads + 1; return standing end
    flow._T.transfer = { FindRoom = function() return nil end }
    withStubs({ Recover = realRecover, RestoreReturning = function() restores = restores + 1 end, Settled = function() return true end, IsGuard = function() return false end }, function()
        arrange()
        flow:Recover(id)
    end)
    assert((returns == 1 and restores == 1) == expectEnds, "absent result: " .. label .. " returns=" .. tostring(returns) .. " restores=" .. tostring(restores))
    return reads
end
assert(absentRecord("waiting record ends a TRANSFER ticket", "TRANSFER", true, function() standing = "PENDING" end) == 1)
assert(absentRecord("waiting record ends a COMMITTING ticket", "COMMITTING", true, function() standing = "PENDING" end) == 1)
assert(absentRecord("waiting record ends an IN_ROOM ticket the static room still holds", "IN_ROOM", true, function() standing = "PENDING" end) == 1)
assert(absentRecord("a confirmed record ends a TRANSFER ticket whose return had failed", "TRANSFER", true, function() standing = "CLEARED" end) == 1)
assert(absentRecord("a confirmed record leaves an IN_ROOM ticket to its room", "IN_ROOM", false, function() standing = "CLEARED" end) == 1)
assert(absentRecord("no record leaves the ticket alone", "TRANSFER", false, function() standing = "" end) == 1)
assert(absentRecord("a state that never entered is not touched", "QUEUED", false, function() standing = "PENDING" end) == 0)
assert(absentRecord("a recent check is not repeated", "TRANSFER", false, function() standing = "PENDING"; flow._T.absentChecked[id] = 39000 end) == 0)
assert(absentRecord("a fresh write hints the check past the interval", "TRANSFER", true, function() standing = "PENDING"; flow._T.absentChecked[id] = 39000; flow:HintSettled(id) end) == 1)
assert(absentRecord("an old check is repeated", "TRANSFER", true, function() standing = "PENDING"; flow._T.absentChecked[id] = 36000 end) == 1)
standing = ""

-- The shipped ParticipantSide: standing comes from the two sealed profiles of the match, never from the arrival.
do
    local sides = { MatchKey = "room", HomeProfile = "a", AwayProfile = "b", ParticipantSide = ParticipantSideOf }
    assert(sides:ParticipantSide("a") == "PLAYER" and sides:ParticipantSide("b") == "ENEMY", "the two sealed profiles")
    assert(sides:ParticipantSide("c") == "" and sides:ParticipantSide("") == "", "a stranger and an empty profile have no side")
    sides.MatchKey = ""
    assert(sides:ParticipantSide("a") == "", "no match, no side")
end

local function inRoom(phase)
    instance = true
    battle = { Phase = phase, MatchKey = "room", HomeProfile = profile, AwayProfile = "b",
        ParticipantSide = ParticipantSideOf,
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
