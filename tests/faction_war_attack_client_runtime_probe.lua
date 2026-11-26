-- Maker `client` context, in a fresh Play where the local player stands in one of the four towns (login lands a player in their own faction's town; an enemy town evicts).
-- Drives the NPC dialog and the queue bar through their production methods. Final line: [VRF][WarUI] CLIENT PASS.
local ok, reason = pcall(function()
    local ui = _FactionWarUI
    local town = _UserService.LocalPlayer.CurrentMapName
    assert(_FactionWar:IsTown(town), "client stands in a town")
    local highlight = "<color=" .. ui.TownNameHighlightHex .. ">"
    local both = { { town = "zuoying", name = "左營", capital = false, strength = 80, owner = "BLUE" },
        { town = "yancheng", name = "鹽埕", capital = true, strength = 100, owner = "BLUE" } }
    local header = { town = town, name = _FactionWarTownDocument.TownNames[town], capital = _FactionWarTownDocument:IsCapital(town), strength = 60, owner = "RED", faction = "RED" }
    local function text(path) return ui:Ui(path).TextGUIRendererComponent.Text end
    ui:ShowAttackOptions(town, both, "READY", header)
    local panel = ui:Ui("AttackPanel")
    assert(panel.Enable, "panel open")
    -- #117: the departure town and its strength on top.
    assert(ui:Ui("AttackPanel/Window/Origin").Enable, "departure town card shown")
    assert(text("AttackPanel/Window/Origin/Name") == highlight .. _FactionWarTownDocument.TownNames[town] .. "</color>", "departure town name highlighted")
    assert(text("AttackPanel/Window/Origin/Value") == "兵力 60 / 100", "departure strength")
    local originFill = ui:Ui("AttackPanel/Window/Origin/Bar/Fill")
    assert(math.abs(originFill.UITransformComponent.RectSize.x - ui.OriginBarWidth * 0.6) < 0.01, "origin bar is 60 percent wide")
    -- One card per target: name, number, bar, capital mark.
    assert(ui:Ui("AttackPanel/Window/Row1").Enable and ui:Ui("AttackPanel/Window/Row2").Enable, "two rows shown for two towns")
    assert(text("AttackPanel/Window/Row1/Name") == highlight .. "左營</color>" and text("AttackPanel/Window/Row2/Name") == highlight .. "鹽埕</color>", "target names highlighted")
    assert(text("AttackPanel/Window/Row1/Value") == "兵力 80 / 100" and text("AttackPanel/Window/Row2/Value") == "兵力 100 / 100", "target strengths")
    assert(math.abs(ui:Ui("AttackPanel/Window/Row1/Bar/Fill").UITransformComponent.RectSize.x - ui.AttackBarWidth * 0.8) < 0.01, "row 1 bar is 80 percent wide")
    assert(not ui:Ui("AttackPanel/Window/Row1/Capital").Enable and ui:Ui("AttackPanel/Window/Row2/Capital").Enable, "only the capital is marked")
    assert(text("AttackPanel/Window/Row1/Note") == "" and text("AttackPanel/Window/Row2/Note") ~= "", "capital note beside the capital")
    assert(text("AttackPanel/Window/Row1/Option") == "進攻" and ui:Ui("AttackPanel/Window/Row1/Option").ButtonComponent.Enable, "attack button offered")
    -- A pushed board updates the numbers in place, without a new request.
    ui:ShowAttackBoard({ { id = town, owner = "RED", strength = 40 }, { id = "zuoying", owner = "BLUE", strength = 30 }, { id = "yancheng", owner = "BLUE", strength = 100 } })
    assert(text("AttackPanel/Window/Origin/Value") == "兵力 40 / 100" and text("AttackPanel/Window/Row1/Value") == "兵力 30 / 100", "pushed strengths drawn live")
    assert(math.abs(originFill.UITransformComponent.RectSize.x - ui.OriginBarWidth * 0.4) < 0.01, "the bar follows")
    ui:ShowAttackOptions(town, { both[2] }, "READY", header)
    assert(ui:Ui("AttackPanel/Window/Row1").Enable and not ui:Ui("AttackPanel/Window/Row2").Enable, "one town shows one row")
    -- Already queued: the panel names the target and offers nothing.
    ui:ShowAttackOptions(town, { both[2] }, "ENGAGED", { town = town, strength = 60, owner = "RED", faction = "RED", target = "yancheng" })
    assert(ui:Ui("AttackPanel/Window/Row1").Enable and text("AttackPanel/Window/Row1/Option") == "進攻中" and not ui:Ui("AttackPanel/Window/Row1/Option").ButtonComponent.Enable, "the attacked town is marked and cannot be picked again")
    assert(text("AttackPanel/Window/Status") == "目前正在進攻 " .. highlight .. "鹽埕</color>，要改變目標請先取消配對", "the line says which town is being attacked")
    ui:ShowAttackOptions(town, {}, "NOT_OWNED", {})
    assert(not ui:Ui("AttackPanel/Window/Origin").Enable and not ui:Ui("AttackPanel/Window/Row1").Enable, "a lost town shows no cards")
    ui:CloseAttack()
    assert(not panel.Enable, "panel closes")
    local saved = _MatchFlowInput.Snapshot
    local value = { state = "QUEUED", reasonCode = "", started = DateTime.UtcNow.Elapsed - 8000, players = 0,
        busy = false, summary = "", attempt = "abc", origin = town, target = "yancheng",
        guardAt = DateTime.UtcNow.Elapsed + 1800, sequenceKey = "war-client", sequence = 1 }
    _MatchFlowInput.Snapshot = value
    local bar = ui:Ui("QueueBar")
    local status = ui:Ui("QueueBar/Status").TextGUIRendererComponent
    local button = ui:Ui("QueueBar/Cancel")
    ui:RenderQueue(town)
    assert(bar.Enable and status.Text == "進攻 鹽埕\n配對中 · 倒數 2 秒", "queue bar uses the real deadline")
    assert(button.Enable and button.TextGUIRendererComponent.Text == "取消配對", "cancel button offered in place")
    ui._T.queueSequenceKey, ui._T.queueSequence, ui._T.queuePendingAction = value.sequenceKey, value.sequence, "CANCEL"
    ui:RenderQueue(town)
    assert(not button.Enable and status.Text == "進攻 鹽埕\n正在取消配對…", "hide action while cancellation is pending")
    value.sequence = 2
    ui:RenderQueue(town)
    assert(button.Enable, "another accepted sequence on the same phase clears pending")
    value.guardAt = DateTime.UtcNow.Elapsed
    ui:RenderQueue(town)
    assert(not button.Enable and status.Text == "進攻 鹽埕\n即將開戰…", "no button at zero")
    value.state = "SAVING"
    ui:RenderQueue(town)
    assert(not button.Enable and status.Text == "進攻 鹽埕\n配對成功，正在進入戰場", "no cancellation after pairing")
    value.reasonCode = "HANDOFF_SEAL_FAILED"
    ui:RenderQueue(town)
    assert(button.Enable and button.TextGUIRendererComponent.Text == "停止入場" and status.Text == "進攻 鹽埕\n入場失敗", "Stop Entry only after failure")
    _MatchFlowInput.Snapshot = { state = "IDLE", reasonCode = "CANCELLED", started = 0, players = 0, busy = false, summary = "", attempt = "", origin = "", target = "" }
    ui:RenderQueue(town)
    assert(not bar.Enable, "queue bar hides after cancel")
    _MatchFlowInput.Snapshot = saved
    log("[VRF][WarUI] CLIENT PASS")
end)
if not ok then log_error("[VRF][WarUI] CLIENT FAIL " .. tostring(reason)) end
