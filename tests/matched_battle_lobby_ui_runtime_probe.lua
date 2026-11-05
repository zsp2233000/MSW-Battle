-- client, after return. Exercises the actual connected queue/cancel button through its native event.
local ok, detail = pcall(function()
    -- Map transitions settle on a later frame than CurrentMapName; wait for the native UI to update.
    wait(0.2)
    for attempt = 1, 200 do
        if _UserService.LocalPlayer.CurrentMapName == "formationlobby" and _MatchFlowInput.Snapshot.state == "IDLE"
            and _MatchFlowInput.action.EnabledInHierarchy and _MatchFlowInput.action.ButtonComponent.Enable then break end
        wait(0.1)
    end
    assert(_UserService.LocalPlayer.CurrentMapName == "formationlobby" and _MatchFlowInput.Snapshot.state == "IDLE", "returned lobby is usable")
    assert(_MatchFlowInput.action.EnabledInHierarchy and _MatchFlowInput.action.ButtonComponent.Enable, "queue action is ready after map transition")
    assert(_MatchFlowInput.action.TextGUIRendererComponent.Text == "開始配對", "queue action visible")
    assert(not _BattleUIController.root.Enable and not _BattleUIController.result.Enable and _BattleUIController.OwnResult == "", "no battle or result layer remains")
    assert(not _MatchFlowInput.root:GetChildByName("BattleResult", false).Enable and not _MatchFlowInput.root:GetChildByName("BattleMatch", false).Enable, "no battle panel remains")
    _MatchFlowInput.action:SendEvent(ButtonClickEvent())
    for attempt = 1, 100 do if _MatchFlowInput.Snapshot.state == "QUEUED" then break end wait(0.1) end
    assert(_MatchFlowInput.Snapshot.state == "QUEUED" and _MatchFlowInput.Snapshot.started > 0, "visible queue has a start time")
    assert(_MatchFlowInput.action.TextGUIRendererComponent.Text == "取消配對", "cancel action visible")
    _MatchFlowInput.action:SendEvent(ButtonClickEvent())
    for attempt = 1, 100 do if _MatchFlowInput.Snapshot.state == "IDLE" then break end wait(0.1) end
    assert(_MatchFlowInput.Snapshot.state == "IDLE", "connected cancel restores queue action")
    log("[VRF][MatchedLobbyUI] PASS returned lobby; connected requeue/cancel; wait clock")
end)
if not ok then log("[VRF][MatchedLobbyUI] FAIL " .. tostring(detail)) end
