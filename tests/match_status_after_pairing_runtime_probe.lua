-- #116 Maker, WRITTEN NOT RUN. In server_main use STAGE START/FINISH; in client use CHECK.
-- Run fresh Plays for GUARD (one player in Zuoying), HUMAN (real client Zuoying + peer Gushan),
-- and TIMEOUT (one player in Zuoying, guard pairing held in SAVING until the 30s deadline).
-- Use disposable profiles/storage and confirmed active formations; see tests/README.md.
local STAGE, CASE = "START", "GUARD"
local function await(predicate, tries)
    for _ = 1, tries or 450 do if predicate() then return true end wait(0.1) end
    return false
end
local function runStage()
    if STAGE == "CHECK" then
        local client = _MatchFlowInput
        local view = _FactionWarUI
        local bar = view:Ui("QueueBar")
        local status = view:Ui("QueueBar/Status")
        local button = view:Ui("QueueBar/Cancel")
        assert(_UserService.LocalPlayer.CurrentMapName == "zuoying", "real client must start in Zuoying")
        assert(await(function()
            return bar.Enable and client.Snapshot.opponentFound and client.Snapshot.state == "SAVING" and not button.Enable
        end, 250), "real pairing enters the pre-commit hold; no button")
        local paired = client.Snapshot
        local line = status.TextGUIRendererComponent.Text
        assert(line == "進攻 鼓山\n配對成功，正在進入戰場" and paired.guard == nil, "same visible text and no kind discriminator")
        log("[VRF][MatchStatus] " .. CASE .. " CLIENT MATCHED " .. line:gsub("\n", " / "))
        -- Bypass the hidden control to exercise the actual authenticated RPC with the current attempt.
        _MatchFlow:RequestCancel(paired.attempt)
        assert(await(function() return client.Snapshot.eventCode == "CANCEL_MATCH_FOUND" end, 60), "server rejected cancel after pairing")
        assert(client.Snapshot.attempt == paired.attempt and not button.Enable, "original attempt remains and has no cancel button")
        _MatchFlow:RequestReturn(paired.attempt)
        assert(await(function() return client.Snapshot.eventCode == "ENTRY_IN_PROGRESS" end, 60), "server rejected early entry return")
        log("[VRF][MatchStatus] " .. CASE .. " REJECTION PASS")
        assert(await(function()
            return button.Enable and button.ButtonComponent.Enable and button.TextGUIRendererComponent.Text == "停止入場"
        end), "failure/timeout offers Stop Entry")
        assert(status.TextGUIRendererComponent.Text == "進攻 鼓山\n入場失敗", "entry failure status")
        if CASE == "TIMEOUT" then
            assert(client.Snapshot.state == "SAVING" and DateTime.UtcNow.Elapsed >= paired.entryDeadline, "expiry measured from pairing, even before commit")
        else
            assert(client.Snapshot.reasonCode == "ROOM_MOVE_FAILED" and DateTime.UtcNow.Elapsed < paired.entryDeadline, "definite failure before deadline")
        end
        button:SendEvent(ButtonClickEvent())
        assert(await(function() return client.Snapshot.state == "IDLE" and not bar.Enable end, 200), "visible Stop Entry returns to idle")
        log("[VRF][MatchStatus] " .. CASE .. " CLIENT PASS")
        return
    end
    local flow = _MatchFlow
    local starter, peer
    for _, user in ipairs(_UserService.UserEntities.Values) do
        if user.CurrentMapName == "zuoying" then starter = user end
        if user.CurrentMapName == "gushan" then peer = user end
    end
    assert(isvalid(starter), "real client ready in Zuoying")
    local starterId = starter.PlayerComponent.UserId
    local peerId = isvalid(peer) and peer.PlayerComponent.UserId or ""
    if STAGE == "FINISH" then
        if CASE == "HUMAN" then
            assert(peerId ~= "", "peer stayed in Gushan")
            flow:ReturnForUser(peerId)
            assert(await(function() return not flow:IsFormationLocked(peerId) end, 200), "peer unlocked after its failure")
        end
        assert(not flow:IsFormationLocked(starterId), "starter unlocked")
        _MatchFaults:Remove()
        flow.SaveDelaySeconds = 0
        _FactionWarGuard.WaitSeconds = 10
        log("[VRF][MatchStatus] " .. CASE .. " CLEANUP PASS")
        return
    end
    assert(STAGE == "START" and (CASE == "HUMAN" or CASE == "GUARD" or CASE == "TIMEOUT"), "valid probe mode")
    assert(CASE ~= "HUMAN" or peerId ~= "", "human peer ready in Gushan")
    assert(not flow:IsFormationLocked(starterId), "start unlocked")
    -- FIFO invokes both human callbacks in sequence, so each hold must leave room for its peer.
    flow.SaveDelaySeconds = CASE == "TIMEOUT" and 35 or (CASE == "HUMAN" and 8 or 14)
    if CASE == "HUMAN" then _FactionWarGuard.WaitSeconds = 60 end
    _MatchFaults:ConfigureTransfer(10, 0)
    _TimerService:SetTimerOnce(function()
        local ok, detail = pcall(function()
            flow:QueueForWar(starterId, "zuoying", "gushan")
            if CASE == "HUMAN" then flow:QueueForWar(peerId, "gushan", "zuoying") end
        end)
        if not ok then log_error("[VRF][MatchStatus] QUEUE FAIL " .. tostring(detail)) end
    end, 2)
    assert(await(function()
        local snapshot = flow:StateSnapshot(starterId, "PROBE")
        return snapshot.state == "SAVING" and snapshot.opponentFound
    end, 250), "pair observed in SAVING")
    local ticket = flow._T.records[starterId]
    assert(flow:IsGuard(ticket) == (CASE ~= "HUMAN"), "actual server pairing kind matches fixture")
    log("[VRF][MatchStatus] " .. CASE .. " SERVER PAIRED")
end
local ok, detail = pcall(runStage)
if not ok then log_error("[VRF][MatchStatus] " .. STAGE .. " " .. CASE .. " FAIL " .. tostring(detail)) end
