-- server_main with the two dedicated virtual players and confirmed active formations.
local previousDelay = _MatchProbe.SaveDelaySeconds
local ok, detail = pcall(function()
    local first, second
    for _, user in ipairs(_UserService.UserEntities.Values) do
        if user.PlayerComponent.ProfileCode == 'hf2601' then first = user end
        if user.PlayerComponent.ProfileCode == 'hf2602' then second = user end
    end
    assert(isvalid(first) and isvalid(second), 'dedicated players joined')
    local firstId, secondId = first.PlayerComponent.UserId, second.PlayerComponent.UserId
    _MatchProbe:QueueForUser(firstId)
    local original = _FormationHandoff:Read(first.PlayerComponent.ProfileCode)
    assert(original ~= nil and original.data.state == 'QUEUED', 'first player queued')
    _MatchProbe.SaveDelaySeconds = 3
    local done, cancelled, reason = false, false, nil
    _TimerService:SetTimerOnce(function()
        cancelled, reason = pcall(function()
            _MatchProbe:CancelForUser(firstId)
            _MatchProbe:CancelForUser(secondId)
            _MatchProbe:QueueForUser(firstId)
        end)
        done = true
    end, 0.5)
    _MatchProbe:QueueForUser(secondId)
    for attempt = 1, 100 do if done then break end wait(0.1) end
    assert(done and cancelled, tostring(reason))
    wait(1)
    local newer = _FormationHandoff:Read(first.PlayerComponent.ProfileCode)
    assert(newer ~= nil and newer.id ~= original.id and newer.data.state == 'QUEUED', 'cancel during SAVING leaves the new queue intact')
    assert(first.CurrentMapName ~= 'matchprobe' and second.CurrentMapName ~= 'matchprobe', 'old match cannot move cancelled participants')
    _MatchProbe:CancelForUser(firstId)
    log('[VRF][HandoffCancellation] PASS cancel during SAVING; requeue intact; old matched callback cannot enter')
end)
_MatchProbe.SaveDelaySeconds = previousDelay
if not ok then log('[VRF][HandoffCancellation] FAIL '..tostring(detail)) end
