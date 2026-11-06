-- server_main with the two dedicated virtual players and confirmed active formations.
local previousDelay = _MatchFlow.SaveDelaySeconds
local ok, detail = pcall(function()
    local first, second
    for _, user in ipairs(_UserService.UserEntities.Values) do
        if user.PlayerComponent.ProfileCode == 'hf2601' then first = user end
        if user.PlayerComponent.ProfileCode == 'hf2602' then second = user end
    end
    assert(isvalid(first) and isvalid(second), 'dedicated players joined')
    local firstId, secondId = first.PlayerComponent.UserId, second.PlayerComponent.UserId
    _MatchFlow:QueueForUser(firstId)
    local original = _FormationHandoff:Read(first.PlayerComponent.ProfileCode)
    assert(original ~= nil and original.data.state == 'QUEUED', 'first player queued')
    _MatchFlow.SaveDelaySeconds = 3
    local done, cancelled, reason = false, false, nil
    _TimerService:SetTimerOnce(function()
        cancelled, reason = pcall(function()
            _MatchFlow:CancelForUser(firstId)
            _MatchFlow:CancelForUser(secondId)
            -- Arrival recovery may still own a read after cancellation; retry the same public command once idle.
            for retry = 1, 100 do
                _MatchFlow:QueueForUser(firstId)
                if _MatchFlow:StateForUser(firstId) == 'QUEUED' then break end
                wait(0.1)
            end
        end)
        done = true
    end, 0.5)
    _MatchFlow:QueueForUser(secondId)
    for attempt = 1, 100 do if done then break end wait(0.1) end
    assert(done and cancelled, tostring(reason))
    wait(1)
    local newer = _FormationHandoff:Read(first.PlayerComponent.ProfileCode)
    assert(newer ~= nil and newer.id ~= original.id and newer.data.state == 'QUEUED', 'cancel during SAVING leaves the new queue intact')
    assert(first.CurrentMapName ~= 'matchprobe' and second.CurrentMapName ~= 'matchprobe', 'old match cannot move cancelled participants')
    _MatchFlow:CancelForUser(firstId)
    log('[VRF][HandoffCancellation] PASS cancel during SAVING; requeue intact; old matched callback cannot enter')
end)
_MatchFlow.SaveDelaySeconds = previousDelay
if not ok then log('[VRF][HandoffCancellation] FAIL '..tostring(detail)) end
