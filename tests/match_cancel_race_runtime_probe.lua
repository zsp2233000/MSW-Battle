-- server_main, the real lobby player plus hf2602, both with isolated saved active formations.
-- Handoff must use its default key in every room. Formation saves remain isolated.
-- MODE ENTRY: fail cancellation while the peer queues; then fail the first native room movement.
-- MODE SUCCESS: cancellation wins while a match is already sealing; neither participant may enter.
-- MODE SEAL_FAILURE: cancellation fails during sealing; delayed storage leaves time to inspect resumed commit.
-- MODE RECONNECT_MATCH: disconnect cleanup's cancellation fails after a reconnect and a racing match reply.
local MODE = 'ENTRY'
local previousDelay = _MatchFlow.SaveDelaySeconds
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
    if MODE == 'ENTRY' then
        _MatchFlow:ConfigureMakerCancelFaults(1, 2)
        _MatchFlow:ConfigureMakerTransferFaults(10, 0)
        _TimerService:SetTimerOnce(function() _MatchFlow:QueueForUser(peerId) end, 0.2)
        _MatchFlow:CancelForUser(firstId)
        wait(2)
        local ticket = _FormationHandoff:Read(profile)
        assert(ticket ~= nil and ticket.data ~= nil and ticket.data.state == 'TRANSFER' and ticket.data.matchKey ~= '', 'match result during failed cancellation resumes through entry')
        assert(_MatchFlow:IsFormationLocked(firstId) and first.CurrentMapName == 'formationlobby', 'failed movement retains the handoff and formation lock')
        log('[VRF][Cancel52Race] PASS cancellation failed; racing match retained; entry movement failure retryable')
    elseif MODE == 'RECONNECT_MATCH' then
        _MatchFlow:ConfigureMakerCancelFaults(1, 2)
        _MatchFlow:ConfigureMakerTransferFaults(10, 0)
        _TimerService:SetTimerOnce(function() _MatchFlow:Depart(firstId) end, 0.1)
        wait(0.5)
        local event = UserReconnectEvent()
        event.UserId = firstId
        _UserService:SendEvent(event)
        -- A native callback survives Depart; the Maker FIFO needs this entry restored to deliver the same reply.
        table.insert(_MatchFlow._T.localQueue, firstId)
        _MatchFlow:QueueForUser(peerId)
        wait(3)
        local ticket = _FormationHandoff:Read(profile)
        assert(ticket ~= nil and ticket.data ~= nil and ticket.data.state == 'TRANSFER' and ticket.data.matchKey ~= '', 'match reply during failed cleanup resumes for the reconnected player')
        _MatchFlow:ReturnForUser(firstId)
        _MatchFlow:ReturnForUser(peerId)
        assert(not _MatchFlow:IsFormationLocked(peerId), 'peer can recover')
        log('[VRF][Cancel52Race] PASS reconnected player keeps the match reply when cleanup cancellation fails')
    else
        _MatchFlow.SaveDelaySeconds = 1
        _MatchFlow:ConfigureMakerCancelFaults(MODE == 'SEAL_FAILURE' and 1 or 0, 2)
        if MODE == 'SEAL_FAILURE' then _MatchFlow:ConfigureMakerTransferFaults(10, 0) end
        local done = false
        _TimerService:SetTimerOnce(function()
            for _ = 1, 150 do
                if _MatchFlow:StateForUser(firstId) == 'SAVING' then break end
                wait(0.1)
            end
            assert(_MatchFlow:StateForUser(firstId) == 'SAVING', 'matching reached the sealing phase')
            if MODE == 'SEAL_FAILURE' then _FormationStorage:ConfigureMakerFaults(0, 0, 1) end
            _MatchFlow:CancelForUser(firstId)
            done = true
        end, 0.2)
        _MatchFlow:QueueForUser(peerId)
        for _ = 1, 150 do if done then break end wait(0.1) end
        assert(done, 'cancellation completed')
        wait(MODE == 'SEAL_FAILURE' and 3 or 0.5)
        local ticket = _FormationHandoff:Read(profile)
        if MODE == 'SEAL_FAILURE' then
            assert(ticket ~= nil and ticket.data.state == 'TRANSFER' and ticket.data.matchKey ~= '', 'failed cancellation resumes the sealing match')
            _MatchFlow:ReturnForUser(firstId)
        else
            assert(ticket ~= nil and ticket.data.state == 'CANCELLED' and not _MatchFlow:IsFormationLocked(firstId), 'only confirmed cancellation closes the first ticket')
        end
        assert(first.CurrentMapName == 'formationlobby' and peer.CurrentMapName == 'formationlobby', 'sealing cannot commit while cancellation is pending')
        _MatchFlow:ReturnForUser(peerId)
        assert(not _MatchFlow:IsFormationLocked(peerId), 'peer can recover without entering a cancelled match')
        log(MODE == 'SEAL_FAILURE' and '[VRF][Cancel52Race] PASS cancellation fails during sealing; match resumes; both can return' or '[VRF][Cancel52Race] PASS cancellation wins during sealing; neither enters; peer returns')
    end
end)
_MatchFlow.SaveDelaySeconds = previousDelay
_MatchFlow:ConfigureMakerCancelFaults(0, 0)
_FormationStorage:ConfigureMakerFaults(0, 0, 0)
-- ENTRY keeps movement faults armed until the client exercises the visible abort-entry control.
if MODE ~= 'ENTRY' then _MatchFlow:ConfigureMakerTransferFaults(0, 0) end
if not ok then log('[VRF][Cancel52Race] FAIL ' .. MODE .. ' ' .. tostring(detail)) end
