-- client, after return. Exercises the actual connected queue/cancel button through its native event.
local ok, detail = pcall(function()
    for attempt = 1, 200 do
        if _UserService.LocalPlayer.CurrentMapName == "formationlobby" and _MatchProbeInput.State == "IDLE" then break end
        wait(0.1)
    end
    assert(_UserService.LocalPlayer.CurrentMapName == "formationlobby" and _MatchProbeInput.State == "IDLE", "returned lobby is usable")
    assert(_MatchProbeInput.action.TextGUIRendererComponent.Text == "開始配對", "queue action visible")
    _MatchProbeInput.action:SendEvent(ButtonClickEvent())
    for attempt = 1, 100 do if _MatchProbeInput.State == "QUEUED" then break end wait(0.1) end
    assert(_MatchProbeInput.State == "QUEUED" and _MatchProbeInput.Started > 0, "visible queue has a start time")
    assert(_MatchProbeInput.action.TextGUIRendererComponent.Text == "取消配對", "cancel action visible")
    _MatchProbeInput.action:SendEvent(ButtonClickEvent())
    for attempt = 1, 100 do if _MatchProbeInput.State == "IDLE" then break end wait(0.1) end
    assert(_MatchProbeInput.State == "IDLE", "connected cancel restores queue action")
    log("[VRF][MatchedLobbyUI] PASS returned lobby; connected requeue/cancel; wait clock")
end)
if not ok then log("[VRF][MatchedLobbyUI] FAIL " .. tostring(detail)) end
