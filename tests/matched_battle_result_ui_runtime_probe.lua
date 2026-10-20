-- client, while in the matched room. The client context ends on return, so log before dispatch.
local ok, detail = pcall(function()
    local player = _UserService.LocalPlayer
    assert(isvalid(player) and player.CurrentMapName == "matchprobe", "client is in the match")
    local battle = player.CurrentMap:GetComponent("script.BattleSession")
    for attempt = 1, 900 do
        if string.sub(_MatchProbeInput.State, 1, 7) == "RESULT_" then break end
        wait(0.1)
    end
    local expected = battle:ResultForProfile(player.PlayerComponent.ProfileCode)
    assert(expected ~= "" and _MatchProbeInput.State == "RESULT_" .. expected, "result belongs to this player's actual battle side")
    assert(_MatchProbeInput.action.TextGUIRendererComponent.Text == "返回大廳", "result return action visible")
    assert(_MatchProbeInput.action.ButtonComponent.Enable, "return button enabled")
    log("[VRF][MatchedResultUI] PASS own " .. expected .. " displayed; dispatching connected return button")
    _MatchProbeInput.action:SendEvent(ButtonClickEvent())
end)
if not ok then log("[VRF][MatchedResultUI] FAIL " .. tostring(detail)) end
