-- Maker `client` context, in a fresh Play where the local player stands in Gushan (the authored start map).
-- Drives the NPC dialog and the queue bar through their production methods. Final line: [VRF][WarUI] CLIENT PASS.
local ok, reason = pcall(function()
    local ui = _FactionWarUI
    assert(_UserService.LocalPlayer.CurrentMapName == "gushan", "client stands in Gushan")
    local both = { { town = "zuoying", name = "左營", capital = false }, { town = "yancheng", name = "鹽埕", capital = true } }
    ui:ShowAttackOptions("gushan", both, "READY")
    local panel = ui:Ui("AttackPanel")
    assert(panel.Enable, "dialog open")
    assert(ui:Ui("AttackPanel/Window/Row1").Enable and ui:Ui("AttackPanel/Window/Row2").Enable, "two rows shown for two towns")
    assert(ui:Ui("AttackPanel/Window/Row1/Option").TextGUIRendererComponent.Text == "進攻 左營", "row 1 names Zuoying")
    assert(ui:Ui("AttackPanel/Window/Row1/Note").TextGUIRendererComponent.Text == "", "no capital note for a front town")
    assert(ui:Ui("AttackPanel/Window/Row2/Note").TextGUIRendererComponent.Text == "敵方主城不會被攻下，勝利也不會扣除主城兵力", "capital note beside the attack option")
    ui:ShowAttackOptions("gushan", { both[2] }, "READY")
    assert(ui:Ui("AttackPanel/Window/Row1").Enable and not ui:Ui("AttackPanel/Window/Row2").Enable, "one town shows one row")
    ui:ShowAttackOptions("gushan", { both[2] }, "ENGAGED")
    assert(not ui:Ui("AttackPanel/Window/Row1").Enable, "no option while already queued")
    ui:CloseAttack()
    assert(not panel.Enable, "dialog closes")
    local saved = _MatchFlowInput.Snapshot
    local value = { state = "QUEUED", reasonCode = "", started = DateTime.UtcNow.Elapsed - 8000, players = 0,
        busy = false, summary = "", attempt = "abc", origin = "gushan", target = "yancheng",
        guardAt = DateTime.UtcNow.Elapsed + 1800, sequenceKey = "war-client", sequence = 1 }
    _MatchFlowInput.Snapshot = value
    local bar = ui:Ui("QueueBar")
    local status = ui:Ui("QueueBar/Status").TextGUIRendererComponent
    local button = ui:Ui("QueueBar/Cancel")
    ui:RenderQueue("gushan")
    assert(bar.Enable and status.Text == "進攻 鹽埕\n配對中 · 倒數 2 秒", "queue bar uses the real deadline")
    assert(button.Enable and button.TextGUIRendererComponent.Text == "取消配對", "cancel button offered in place")
    ui._T.queueSequenceKey, ui._T.queueSequence, ui._T.queuePendingAction = value.sequenceKey, value.sequence, "CANCEL"
    ui:RenderQueue("gushan")
    assert(not button.Enable and status.Text == "進攻 鹽埕\n正在取消配對…", "hide action while cancellation is pending")
    value.sequence = 2
    ui:RenderQueue("gushan")
    assert(button.Enable, "another accepted sequence on the same phase clears pending")
    value.guardAt = DateTime.UtcNow.Elapsed
    ui:RenderQueue("gushan")
    assert(not button.Enable and status.Text == "進攻 鹽埕\n即將開戰…", "no button at zero")
    value.state = "SAVING"
    ui:RenderQueue("gushan")
    assert(not button.Enable and status.Text == "進攻 鹽埕\n配對成功，正在進入戰場", "no cancellation after pairing")
    value.reasonCode = "HANDOFF_SEAL_FAILED"
    ui:RenderQueue("gushan")
    assert(button.Enable and button.TextGUIRendererComponent.Text == "停止入場" and status.Text == "進攻 鹽埕\n入場失敗", "Stop Entry only after failure")
    _MatchFlowInput.Snapshot = { state = "IDLE", reasonCode = "CANCELLED", started = 0, players = 0, busy = false, summary = "", attempt = "", origin = "", target = "" }
    ui:RenderQueue("gushan")
    assert(not bar.Enable, "queue bar hides after cancel")
    _MatchFlowInput.Snapshot = saved
    log("[VRF][WarUI] CLIENT PASS")
end)
if not ok then log_error("[VRF][WarUI] CLIENT FAIL " .. tostring(reason)) end
