-- server_main, hf2602 idle in the lobby with an isolated saved active formation; run last before Stop.
-- Calls the production disconnect handler's shared Depart command, without claiming a real network disconnect.
local ok, detail = pcall(function()
    local peer
    for _, player in ipairs(_UserService.UserEntities.Values) do
        if player.PlayerComponent.ProfileCode == 'hf2602' then peer = player end
    end
    assert(isvalid(peer) and peer.CurrentMapName == 'formationlobby', 'dedicated peer in lobby')
    local id, profile = peer.PlayerComponent.UserId, peer.PlayerComponent.ProfileCode
    _MatchProbe:QueueForUser(id)
    _MatchProbe:ConfigureMakerCancelFaults(1, 0)
    _MatchProbe:Depart(id)
    local ticket = _FormationHandoff:Read(profile)
    assert(ticket ~= nil and ticket.data.state == 'QUEUED', 'failed disconnect cancellation cannot persist a cancelled tombstone')
    assert(_MatchProbe:Player(id) == nil, 'departed participant is unavailable')
    -- Finish the isolated fixture only after a confirmed retry at the same cancellation boundary.
    assert(_MatchProbe:CancelMatching(profile), 'cleanup cancellation confirmed')
    assert(_FormationHandoff:Close(id, ticket, 'CANCELLED'), 'cleanup tombstone confirmed')
    log('[VRF][Cancel52Disconnect] PASS failed cancellation preserves durable queue; confirmed cleanup')
end)
_MatchProbe:ConfigureMakerCancelFaults(0, 0)
if not ok then log('[VRF][Cancel52Disconnect] FAIL ' .. tostring(detail)) end
