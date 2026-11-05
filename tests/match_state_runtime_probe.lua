-- Client, fresh Play. Synthetic public observations only; no queue or storage commands.
local ok, detail = pcall(function()
    local rules = _MatchFlowState
    local context = { now = 65000, pending = false, formation = {}, ready = true,
        editBusy = false, unconfirmed = false, confirming = false, hasActive = true, inLobby = true }
    local function snapshot(state, reason)
        return { state = state, eventCode = "STATUS", reasonCode = reason or "STATUS", started = 1000,
            players = 2, busy = false, summary = "fixture", attempt = "new",
            sourceRoom = _RoomService.RoomKey, sequenceKey = "state-probe", sequence = 1 }
    end
    local groups = {
        CANCEL = { "QUEUED", "RENEWING", "QUEUE_ERROR", "CANCELLING", "CANCELLED", "SAVING" },
        RETURN = { "COMMITTING", "TRANSFER", "IN_ROOM", "WAITING", "ENTRY_FAILED", "ABORTED", "ROOM_MISMATCH", "RETURNING", "RESULT_WIN", "RESULT_LOSE", "RESULT_DRAW" },
        QUEUE = { "IDLE" },
    }
    for action, states in pairs(groups) do
        for _, state in ipairs(states) do
            local value = snapshot(state)
            local view = rules:Present(value, context)
            assert(view.action == action and view.enabled, state .. " action")
            assert(view.allowsFormationActions == (state == "IDLE"), state .. " editing lock")
            value.busy = true
            assert(not rules:Present(value, context).enabled, state .. " busy")
        end
    end
    assert(not rules:Present(snapshot("BATTLE"), context).enabled, "battle cannot leave")
    assert(not rules:Present(snapshot("UNKNOWN"), context).enabled, "unknown state cannot queue")
    assert(rules:Present(snapshot("TRANSFER", "READINESS_FAILED"), context).action == "STATUS", "readiness retry queries status")
    assert(rules:Present(snapshot("QUEUED"), context).text == "正在尋找對手 · 已等候 64 秒", "elapsed is not a countdown")
    assert(rules:Failure(nil, { code = "QUEUE_SERVICE_FAILED", details = { serviceCode = "anything" } }, "new").code == "QUEUE_SERVICE_FAILED", "native service failures remain sticky")
    local failure = rules:Failure(nil, { code = "RETURN_MOVE_FAILED", details = { text = "anything" } }, "new")
    assert(failure.code == "RETURN_MOVE_FAILED", "explicit failed movement")
    assert(rules:Failure(failure, { code = "STATUS", details = { text = "FAILED ok=false" } }, "new") == failure, "logs cannot change failure")
    local function project(attempt, phase)
        local value = snapshot("IN_ROOM")
        value.attempt = attempt
        return rules:Resolve({ state = "IN_ROOM", inMatchRoom = true, instanceRoom = true,
            admissionFailed = false, battlePhase = phase, battleAuthorized = true, result = "WIN",
            failure = failure, snapshot = value })
    end
    local returned = project("new", "RESULT")
    assert(returned.state == "RESULT_WIN" and returned.reasonCode == "RETURN_MOVE_FAILED", "result cannot hide return failure")
    local view = rules:Present(returned, context)
    assert(view.label == "重試返回" and view.action == "RETURN", "return retry stays usable")
    context.pending = true
    assert(not rules:Present(returned, context).enabled and rules:Present(returned, context).label == "返回中…", "pending return outranks old failure")
    context.pending = false
    assert(project("other", "RESULT").reasonCode == "STATUS", "old attempt failure isolated")
    assert(project("new", "BATTLE").reasonCode == "STATUS", "battle hides obsolete failure")
    assert(rules:Failure(failure, { code = "RETURN_MOVE_OK" }, "new") == nil, "explicit success clears failure")
    context.hasActive = false
    assert(rules:Present(snapshot("IDLE"), context).action == "PREPARE", "empty active team prepares")
    local input = _MatchFlowInput
    local original = input.Snapshot
    local first = snapshot("QUEUED")
    first.sequence = 1000000
    _MatchFlow:ReceiveState(first)
    assert(input.Snapshot.state == "QUEUED", "public receiver accepts current room")
    local stale = snapshot("IDLE")
    stale.sequence = 999999
    _MatchFlow:ReceiveState(stale)
    assert(input.Snapshot.state == "QUEUED", "stale sequence cannot unlock")
    stale.sourceRoom = "foreign"
    stale.sequence = 1000001
    _MatchFlow:ReceiveState(stale)
    assert(input.Snapshot.state == "QUEUED", "foreign room cannot unlock")
    original.sequenceKey = "state-probe"
    original.sequence = 1000002
    _MatchFlow:ReceiveState(original)
end)
log(ok and "[VRF][MatchState] PASS" or "[VRF][MatchState] FAIL " .. tostring(detail))
