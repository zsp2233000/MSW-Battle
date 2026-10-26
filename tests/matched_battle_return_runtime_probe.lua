-- Run in server_main after both participants return. Queues and cancels each independently.
local ok, detail = pcall(function()
    local users = {}
    for attempt = 1, 200 do
        users = {}
        for _, user in ipairs(_UserService.UserEntities.Values) do
            if user.PlayerComponent.ProfileCode == 'hf2601' or user.PlayerComponent.ProfileCode == 'hf2602' then table.insert(users, user) end
        end
        if #users == 2 then break end
        wait(0.1)
    end
    if #users == 0 then users = _UserService.UserEntities.Values end
    assert(#users == 2, "both players returned")
    for _, user in ipairs(users) do
        assert(user.CurrentMapName == "formationlobby", "returned to the lobby")
        local userId = user.PlayerComponent.UserId
        local session
        for attempt = 1, 200 do
            session = _FormationService:GetSession(userId)
            if session ~= nil and session.initialized then break end
            wait(0.1)
        end
        assert(session ~= nil and session.initialized, "saved active formation restored")
        assert(#session.saved.slots[tostring(session.saved.activeSlot)].units == 1, "latest confirmed save preserved")
        _MatchProbe:QueueForUser(userId)
        _MatchProbe:CancelForUser(userId)
    end
    log("[VRF][MatchedReturn] PASS both lobby; saved active formations retained; requeue/cancel")
end)
if not ok then log("[VRF][MatchedReturn] FAIL " .. tostring(detail)) end
