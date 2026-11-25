-- Client, fresh Play. Synthetic public observations only; no queue or storage commands.
-- ROOM mode: client in a disposable matchprobe instance, after BattleMatch is selected and before any battle.
local MODE = "LOBBY"
local ok, detail = pcall(function()
    local rules = _MatchFlowState
    local context = { now = 65000, pending = false, formation = {}, ready = true,
        editBusy = false, unconfirmed = false, confirming = false, hasActive = true, inLobby = true }
    local function snapshot(state, reason)
        return { state = state, eventCode = "STATUS", reasonCode = reason or "STATUS", started = 1000,
            players = 2, busy = false, summary = "fixture", attempt = "new",
            sourceRoom = _RoomService.RoomKey, sequenceKey = "state-probe", sequence = 1 }
    end
    if MODE == "ROOM" then
        local input = _MatchFlowInput
        assert(input._T.screen == "BattleMatch", "fixture shows the pre-battle panel")
        local waiting = snapshot("WAITING")
        waiting.origin = "zuoying"
        local function observe(value, seq)
            value.sequence = seq
            _MatchFlow:ReceiveState(value)
        end
        observe(waiting, 1000000)
        assert(not input.action.Enable, "valid WAITING is not allowed to leave")
        local failed = snapshot("ENTRY_FAILED")
        failed.origin = "zuoying"
        observe(failed, 1000001)
        assert(input.action.Enable and input.action.TextGUIRendererComponent.Text == "返回 左營", "war return names departure town")
        failed.origin = ""
        observe(failed, 1000002)
        assert(input.action.Enable and input.action.TextGUIRendererComponent.Text == "返回大廳", "lobby return names the lobby")
        return
    end
    local groups = {
        [""] = { "CANCELLING", "SAVING", "COMMITTING", "TRANSFER", "IN_ROOM", "WAITING" },
        CANCEL = { "QUEUED", "RENEWING", "QUEUE_ERROR", "CANCELLED" },
        RETURN = { "ENTRY_FAILED", "ABORTED", "ROOM_MISMATCH", "RETURNING", "RESULT_WIN", "RESULT_LOSE", "RESULT_DRAW" },
        QUEUE = { "IDLE" },
    }
    for action, states in pairs(groups) do
        for _, state in ipairs(states) do
            local value = snapshot(state)
            local view = rules:Present(value, context)
            assert(view.action == action and view.enabled == (action ~= ""), state .. " action")
            assert(view.allowsFormationActions == (state == "IDLE"), state .. " editing lock")
            for _, blocker in ipairs({ "editBusy", "unconfirmed", "confirming" }) do
                context[blocker] = true
                assert(not rules:Present(value, context).enabled, state .. " blocked by " .. blocker)
                context[blocker] = false
            end
            context.pending = true
            context.pendingAction = action
            local pending = rules:Present(value, context)
            assert(not pending.enabled, state .. " pending disables the action")
            if action == "CANCEL" then assert(pending.text == "正在取消配對…" and pending.action == "", "cancel in flight has no button") end
            context.pending = false
            context.pendingAction = ""
            value.busy = true
            assert(not rules:Present(value, context).enabled, state .. " busy")
        end
    end
    assert(not rules:Present(snapshot("BATTLE"), context).enabled, "battle cannot leave")
    assert(not rules:Present(snapshot("UNKNOWN"), context).enabled, "unknown state cannot queue")
    assert(rules:Present(snapshot("TRANSFER", "READINESS_FAILED"), context).action == "", "recoverable readiness still hides entry actions")
    assert(rules:Present(snapshot("QUEUED"), context).text == "配對中 · 已等候 64 秒", "lobby has no countdown")
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
    local editor = _FormationEditSession
    local originalFormation = editor.Snapshot
    local editSequence = 10000000
    for _, state in ipairs({ "QUEUED", "COMMITTING", "RETURNING", "RESULT_WIN" }) do
        for _, blocker in ipairs({ "busy", "unconfirmed", "confirming" }) do
            local formation = {}
            for key, value in pairs(originalFormation) do formation[key] = value end
            formation.pending = blocker == "busy"
            if blocker == "unconfirmed" then formation.uncertain = true formation.loadState = "CONFLICT" end
            editSequence = editSequence + 1
            editor:Observe(formation, editSequence)
            if blocker == "confirming" then editor:OpenConfirmation("RETURN", 0) end
            local blocked = snapshot(state)
            blocked.sequence = editSequence
            _MatchFlow:ReceiveState(blocked)
            local before = input:View()
            assert(not before.enabled and not input.action.ButtonComponent.Enable, state .. " renders disabled for " .. blocker)
            input:Click()
            assert(input:View().label == before.label, state .. " blocked click never enters pending")
            editor:CloseConfirmation()
        end
    end
    editor:Observe(originalFormation, editSequence + 1)
    first.sequence = editSequence + 1
    _MatchFlow:ReceiveState(first)
    local stale = snapshot("IDLE")
    stale.sequence = 999999
    _MatchFlow:ReceiveState(stale)
    assert(input.Snapshot.state == "QUEUED", "stale sequence cannot unlock")
    stale.sourceRoom = "foreign"
    stale.sequence = editSequence + 2
    _MatchFlow:ReceiveState(stale)
    assert(input.Snapshot.state == "QUEUED", "foreign room cannot unlock")
    original.sequenceKey = "state-probe"
    original.sequence = editSequence + 2
    _MatchFlow:ReceiveState(original)
end)
log(ok and "[VRF][MatchState] PASS" or "[VRF][MatchState] FAIL " .. tostring(detail))
