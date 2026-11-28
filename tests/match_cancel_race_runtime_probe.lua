-- server_main, the real lobby player plus hf2602, both with isolated saved active formations.
-- Handoff must use its default key in every room. Formation saves remain isolated.
-- ENTRY: fail the pre-pair cancellation as the peer queues, then fail native room movement.
-- SUCCESS: confirm a delayed cancellation before either player is paired.
-- SEAL_FAILURE (legacy name): refuse a post-pair cancel during SAVING; delay COMMITTING for client PROGRESS, fail movement.
-- RECONNECT_MATCH: disconnect cleanup's cancellation fails after a reconnect and a racing match reply.
local MODE = 'ENTRY'
local previousDelay = _MatchFlow.SaveDelaySeconds
local function await(predicate, tries)
    for _ = 1, tries or 180 do if predicate() then return true end wait(0.1) end
    return false
end
local ok, detail = pcall(function()
    local first, peer
    for _, player in ipairs(_UserService.UserEntities.Values) do
        if player.PlayerComponent.ProfileCode == 'hf2602' then peer = player else first = player end
    end
    assert(isvalid(first) and isvalid(peer), 'both dedicated participants are in the main room')
    local firstId, peerId = first.PlayerComponent.UserId, peer.PlayerComponent.UserId
    local profile = first.PlayerComponent.ProfileCode
    assert(first.CurrentMapName == 'formationlobby' and peer.CurrentMapName == 'formationlobby', 'both in lobby')
    _MatchFlow:QueueForUser(firstId)
    if MODE == 'SUCCESS' then
        _MatchFaults:ConfigureCancel(0, 1)
        _MatchFlow:CancelForUser(firstId)
        assert(_MatchFlow:StateForUser(firstId) == 'IDLE' and not _MatchFlow:IsFormationLocked(firstId), 'confirmed pre-pair cancel closes the ticket')
        log('[VRF][Cancel52Race] PASS pre-pair cancellation confirmed and unlocked')
        return
    end
    _MatchFaults:ConfigureTransfer(10, 0)
    if MODE == 'ENTRY' then
        _MatchFaults:ConfigureCancel(1, 2)
        _TimerService:SetTimerOnce(function() _MatchFlow:QueueForUser(peerId) end, 0.2)
        _MatchFlow:CancelForUser(firstId)
    elseif MODE == 'RECONNECT_MATCH' then
        _MatchFaults:ConfigureCancel(1, 2)
        -- A native registration survives Depart; keep the Maker FIFO entry so the same reply can still arrive.
        _MatchFaults:ConfigureWithdraw(true)
        _TimerService:SetTimerOnce(function() _MatchFlow:Depart(firstId) end, 0.1)
        wait(0.5)
        local event = UserReconnectEvent()
        event.UserId = firstId
        _UserService:SendEvent(event)
        _MatchFlow:QueueForUser(peerId)
    elseif MODE == 'SEAL_FAILURE' then
        _MatchFlow.SaveDelaySeconds = 3
        local rejected = false
        _TimerService:SetTimerOnce(function()
            if not await(function() return _MatchFlow:StateForUser(firstId) == 'SAVING' end) then return end
            _FormationStorage:ConfigureMakerFaults(0, 0, 1)
            local ticket = _MatchFlow._T.records[firstId]
            _MatchFlow:CancelForUser(firstId)
            rejected = _MatchFlow._T.records[firstId] == ticket and _MatchFlow:IsFormationLocked(firstId)
        end, 0.2)
        _MatchFlow:QueueForUser(peerId)
        assert(await(function() return rejected end), 'post-pair cancellation cannot displace the matching ticket')
    else
        error('unknown mode')
    end
    local function failed(userId)
        local snapshot = _MatchFlow:StateSnapshot(userId, 'PROBE')
        return snapshot.reasonCode == 'ROOM_MOVE_FAILED' and not snapshot.busy
    end
    assert(await(function() return failed(firstId) end, 300), 'first failed to move after keeping the match')
    -- Both players share this instance and the local queue sends no readiness hint, so a peer without a client is advanced the way an arrival or a status request would.
    _MatchFlow:Recover(peerId)
    assert(await(function() return failed(peerId) end, 300), 'peer failed to move after keeping the match')
    local ticket = _FormationHandoff:Read(profile)
    assert(ticket ~= nil and ticket.data ~= nil and ticket.data.state == 'TRANSFER' and ticket.data.matchKey ~= '', 'failed movement kept the same paired handoff')
    assert(_MatchFlow:IsFormationLocked(firstId) and first.CurrentMapName == 'formationlobby' and peer.CurrentMapName == 'formationlobby', 'failed movement retains the lock in the lobby')
    if MODE ~= 'ENTRY' then _MatchFlow:ReturnForUser(firstId) end
    _MatchFlow:ReturnForUser(peerId)
    assert(await(function() return not _MatchFlow:IsFormationLocked(peerId) end, 100), 'peer can leave after its own definite failure')
    log('[VRF][Cancel52Race] ' .. MODE .. ' PASS pairing retained; movement failed; allowed failure exit')
end)
_MatchFlow.SaveDelaySeconds = previousDelay
_MatchFaults:ConfigureCancel(0, 0)
_MatchFaults:ConfigureWithdraw(false)
_FormationStorage:ConfigureMakerFaults(0, 0, 0)
-- ENTRY keeps movement faults armed until the client exercises the visible Stop Entry control.
if MODE ~= 'ENTRY' then _MatchFaults:ConfigureTransfer(0, 0) end
if not ok then log('[VRF][Cancel52Race] FAIL ' .. MODE .. ' ' .. tostring(detail)) end
