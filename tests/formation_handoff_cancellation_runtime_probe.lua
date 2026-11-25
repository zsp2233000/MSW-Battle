-- server_main with two dedicated virtual players and confirmed active formations.
-- #116: the success must be before pairing; an old delivery cannot mutate a new queue generation.
local ok, detail = pcall(function()
    local first, second
    for _, user in ipairs(_UserService.UserEntities.Values) do
        if user.PlayerComponent.ProfileCode == 'hf2601' then first = user end
        if user.PlayerComponent.ProfileCode == 'hf2602' then second = user end
    end
    assert(isvalid(first) and isvalid(second), 'dedicated players joined')
    local firstId = first.PlayerComponent.UserId
    _MatchFlow:QueueForUser(firstId)
    local old = _MatchFlow._T.records[firstId]
    assert(old ~= nil and old.data.state == 'QUEUED', 'first player queued without an opponent')
    local oldRequest = old.data.requestId
    _MatchFlow:CancelForUser(firstId)
    assert(_MatchFlow:StateForUser(firstId) == 'IDLE' and not _MatchFlow:IsFormationLocked(firstId), 'cancel confirmed')
    _MatchFlow:QueueForUser(firstId)
    local newer = _MatchFlow._T.records[firstId]
    assert(newer ~= nil and newer.id ~= old.id and newer.data.state == 'QUEUED', 'requeued with a new attempt')
    _MatchFlow:QueueResult(firstId, old, oldRequest, 'MATCHED', '')
    assert(_MatchFlow._T.records[firstId] == newer and newer.data.state == 'QUEUED', 'old delivery cannot advance the new attempt')
    assert(first.CurrentMapName == 'formationlobby' and second.CurrentMapName == 'formationlobby', 'stale delivery does not move either player')
    _MatchFlow:CancelForUser(firstId)
    log('[VRF][HandoffCancellation] PASS pre-pair cancel; requeue intact; stale match delivery ignored')
end)
if not ok then log('[VRF][HandoffCancellation] FAIL '..tostring(detail)) end
