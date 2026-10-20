-- Run in server_main after both participants return. Queues and cancels each independently.
local ok, detail = pcall(function()
    for attempt = 1, 200 do if #_UserService.UserEntities.Values == 2 then break end wait(0.1) end
    assert(#_UserService.UserEntities.Values == 2, "both players returned")
    for _, user in ipairs(_UserService.UserEntities.Values) do
        assert(user.CurrentMapName == "formationlobby", "returned to the lobby")
        local userId = user.PlayerComponent.UserId
        local transfer
        for attempt = 1, 200 do
            transfer = _FormationService:ExportTransfer(userId)
            if transfer ~= nil then break end
            wait(0.1)
        end
        assert(transfer ~= nil, "saved active formation restored")
        assert(#_HttpService:JSONDecode(transfer.fixed) == 1, "latest confirmed save preserved")
        _MatchProbe:QueueForUser(userId)
        _MatchProbe:CancelForUser(userId)
    end
    log("[VRF][MatchedReturn] PASS both lobby; saved active formations retained; requeue/cancel")
end)
if not ok then log("[VRF][MatchedReturn] FAIL " .. tostring(detail)) end
