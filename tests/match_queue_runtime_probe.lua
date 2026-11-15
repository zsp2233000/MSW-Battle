-- server_main of a fresh Maker Play, no queued match. Checks the match queue seam without the match flow:
-- the in-process adapter, the pure parts of the native adapter, and the MatchFaults test adapter.
-- Expect [VRF][MatchQueue] PASS. Nothing is saved; the probe leaves the adapters as it found them.
local checks = 0
local function check(condition, label)
    checks = checks + 1
    assert(condition, label)
end

local local_queue, native_queue = _MatchQueueLocal, _MatchQueueNative
local profiles, userIds = {}, {}
local function request(userId, profile, requestId, live)
    table.insert(userIds, userId)
    table.insert(profiles, profile)
    return { userId = userId, profile = profile, requestId = requestId, attempt = 'attempt-' .. requestId,
        source = 'instance-' .. userId, leaderboardId = 'lb', queueName = 'q', live = live or function() return true end }
end
local function recorder()
    local log_ = {}
    return log_, function(name) return function(outcome, code) table.insert(log_, name .. ':' .. outcome .. ':' .. tostring(code)) end end
end

local ok, detail = pcall(function()
    -- Local adapter: oldest two live entries pair, home first, and each side hears MATCHED once, in order.
    check(local_queue:Kind() == 'local' and native_queue:Kind() == 'native', 'adapters say what they are')
    check(local_queue:Configured('') == true and native_queue:Configured('') == false and native_queue:Configured('lb') == true, 'only the native adapter needs a leaderboard')
    local heard, deliverTo = recorder()
    check(local_queue:Poll() == false, 'an empty FIFO pairs nothing')
    local a = local_queue:Enqueue(request('probeA', 'profA', 'ra'), deliverTo('A'))
    check(a.accepted == true and a.report == 'QUEUED_LOCAL', 'enqueue is accepted and reports the local queue')
    check(local_queue:Poll() == false and #heard == 0, 'one entry waits')
    local_queue:Enqueue(request('probeB', 'profB', 'rb'), deliverTo('B'))
    check(local_queue:Poll() == true, 'two entries pair')
    check(heard[1] == 'A:MATCHED:' and heard[2] == 'B:MATCHED:' and #heard == 2, 'both sides are told MATCHED in queue order')
    local pair = local_queue:Lookup('profA')
    check(pair ~= nil and pair == local_queue:Lookup('profB'), 'both profiles resolve to one match')
    check(pair.home == 'profA' and pair.away == 'profB' and pair.homeAttempt == 'ra' and pair.awayAttempt == 'rb', 'match carries both attempt generations')
    check(string.sub(pair.key, 1, 6) == 'local-' and pair.differentSources == false, 'a local match key says so and never crosses instances')
    check(#local_queue:Destinations(pair) == 0, 'nobody else needs a readiness hint')
    check(local_queue:Poll() == false, 'a paired entry does not pair again')

    -- Release forgets the match; Withdraw forgets the queue entry but never a match already made.
    local_queue:Withdraw('probeA')
    check(local_queue:Lookup('profA') ~= nil, 'withdrawing a player keeps the match they are in')
    local_queue:Release('profA')
    local_queue:Release('profB')
    check(local_queue:Lookup('profA') == nil and local_queue:Lookup('profB') == nil, 'release forgets the match')

    -- Same profile twice is refused for the later entry; the earlier one keeps waiting.
    local dupHeard, dupTo = recorder()
    local_queue:Enqueue(request('probeC', 'profC', 'rc'), dupTo('C'))
    local_queue:Enqueue(request('probeC2', 'profC', 'rc2'), dupTo('C2'))
    check(local_queue:Poll() == false, 'a profile cannot match itself')
    check(dupHeard[1] == 'C2:REJECTED:DUPLICATE_PROFILE' and #dupHeard == 1, 'the later duplicate is rejected with a reason')
    check(local_queue:Reclaim('probeC', { adapter = 'local', state = 'QUEUED', profile = 'profC', matchKey = '' }, true) == 'HELD', 'the earlier duplicate still holds its place')
    local_queue:Withdraw('probeC')

    -- Entries that stopped being live drop out instead of pairing.
    local staleHeard, staleTo = recorder()
    local alive = true
    local_queue:Enqueue(request('probeD', 'profD', 'rd', function() return alive end), staleTo('D'))
    local_queue:Enqueue(request('probeE', 'profE', 're'), staleTo('E'))
    alive = false
    check(local_queue:Poll() == false and #staleHeard == 0, 'a stale entry cannot pair')
    check(local_queue:Reclaim('probeD', { adapter = 'local', state = 'QUEUED', profile = 'profD', matchKey = '' }, true) == nil, 'a dropped entry is no longer held')
    local_queue:Withdraw('probeE')

    -- Reclaim: what a live or restored reservation means to each adapter.
    local queued = { adapter = 'local', state = 'QUEUED', profile = 'profR', matchKey = '' }
    check(local_queue:Reclaim('probeR', queued, false) == 'CANCEL', 'a stored local queue reservation is cancelled after a restart')
    check(local_queue:Reclaim('probeR', { adapter = nil, state = 'SAVING', profile = 'profR', matchKey = '' }, false) == 'CANCEL', 'a ticket from before adapters were recorded counts as local')
    check(local_queue:Reclaim('probeR', { adapter = 'native', state = 'QUEUED', profile = 'profR', matchKey = '' }, false) == nil, 'a native reservation is not the local adapter business')
    check(local_queue:Reclaim('probeR', { adapter = 'native', state = 'QUEUED', profile = 'profR', matchKey = '' }, true) == 'HELD', 'a live native reservation is left alone')
    check(local_queue:Reclaim('probeR', { adapter = 'local', state = 'TRANSFER', profile = 'profR', matchKey = 'local-x' }, false) == 'RETURN', 'a local match lost with its session returns the player')
    check(local_queue:Reclaim('probeR', { adapter = 'local', state = 'TRANSFER', profile = 'profR', matchKey = 'm30-x' }, false) == 'RETURN', 'an explicitly local ticket returns even with a native-looking key')
    check(local_queue:Reclaim('probeR', { adapter = 'native', state = 'TRANSFER', profile = 'profR', matchKey = 'm30-x' }, false) == nil, 'a native transfer is never cancelled by the local adapter')
    check(local_queue:Reclaim('probeR', { adapter = 'local', state = 'IN_ROOM', profile = 'profR', matchKey = 'local-x' }, false) == nil, 'only queue and pre-room states are judged')

    -- Native adapter: the parts that need no service.
    check(native_queue:Classify(tostring(MatchmakingResultCode.Ok)) == 'MATCHED' and native_queue:Classify(tostring(MatchmakingResultCode.AlreadyMatched)) == 'MATCHED', 'Ok and AlreadyMatched are a match')
    for _, code in ipairs({ MatchmakingResultCode.MatchingExpired, MatchmakingResultCode.NotMatched, MatchmakingResultCode.NotMatching, MatchmakingResultCode.RequestNotFound }) do
        check(native_queue:Classify(tostring(code)) == 'EXPIRED', 'expiry-like result ' .. tostring(code))
    end
    check(native_queue:Classify(tostring(MatchmakingResultCode.InternalError)) == 'FAILED' and native_queue:Classify('MISSING') == 'FAILED', 'anything else fails')
    check(native_queue:Reclaim('u', { state = 'QUEUED' }, true) == 'HELD', 'a live native reservation has its callback')
    check(native_queue:Reclaim('u', { state = 'RENEWING' }, false) == 'RENEW', 'a stored renewal resumes')
    for _, state in ipairs({ 'QUEUED', 'SAVING', 'QUEUE_ERROR' }) do
        check(native_queue:Reclaim('u', { state = state }, false) == 'FAIL', 'a stored ' .. state .. ' reservation lost its callback owner')
    end
    check(native_queue:Reclaim('u', { state = 'TRANSFER' }, false) == nil and native_queue:Reclaim('u', { state = 'IN_ROOM' }, false) == nil, 'committed tickets are recovered by the flow')
    local guid = string.rep('a', 32)
    local good = native_queue:ParseExtras(_HttpService:JSONEncode({ schema = 1, attempt = guid, source = 'inst' }))
    check(good ~= nil and good.attempt == guid and good.source == 'inst', 'valid extras parse')
    check(native_queue:ParseExtras('not json') == nil and native_queue:ParseExtras(_HttpService:JSONEncode({ schema = 2, attempt = guid, source = 'inst' })) == nil, 'garbage and wrong schema are rejected')
    check(native_queue:ParseExtras(_HttpService:JSONEncode({ schema = 1, attempt = 'short', source = 'inst' })) == nil and native_queue:ParseExtras(_HttpService:JSONEncode({ schema = 1, attempt = guid, source = '' })) == nil, 'bad attempt and empty source are rejected')
    local same = native_queue:Destinations({ homeSource = 's1', awaySource = 's1' })
    local different = native_queue:Destinations({ homeSource = 's1', awaySource = 's2' })
    check(#same == 1 and same[1] == 's1' and #different == 2 and different[2] == 's2', 'each distinct source instance is hinted once')

    -- MatchFaults wraps whatever the flow runs on, misbehaves only when armed, and hands the originals back.
    local realQueue, realTransfer = _MatchFlow:QueueAdapter(), _MatchFlow:TransferAdapter()
    check(realQueue == local_queue and realTransfer == _MatchTransfer, 'a Maker flow runs on the local adapter')
    _MatchFaults:ConfigureCancel(2, 0)
    check(_MatchFlow:QueueAdapter() == _MatchFaults and _MatchFlow:TransferAdapter() == _MatchFaults, 'arming installs the test adapter')
    check(_MatchFlow:QueueAdapter():Kind() == 'local', 'the wrapper forwards what it does not fault')
    check(_MatchFlow:CancelMatching('profZ') == false and _MatchFlow:CancelMatching('profZ') == false, 'armed cancellations fail')
    check(_MatchFlow:CancelMatching('profZ') == true, 'the next cancellation reaches the real adapter')
    _MatchFaults:ConfigureTransfer(1, 1)
    check(_MatchFaults:MoveToMatch(nil, 'probeZ') == false and _MatchFaults:MoveToLobby('probeZ') == false, 'armed movements fail without touching a room')
    _MatchFaults:ConfigureWithdraw(true)
    local_queue:Enqueue(request('probeF', 'profF', 'rf'), function() end)
    _MatchFlow:QueueAdapter():Withdraw('probeF')
    check(local_queue:Reclaim('probeF', { adapter = 'local', state = 'QUEUED', profile = 'profF', matchKey = '' }, true) == 'HELD', 'a kept registration survives withdrawal')
    _MatchFaults:ConfigureWithdraw(false)
    _MatchFlow:QueueAdapter():Withdraw('probeF')
    check(local_queue:Reclaim('probeF', { adapter = 'local', state = 'QUEUED', profile = 'profF', matchKey = '' }, true) == nil, 'withdrawal works again once disarmed')
    _MatchFaults:Remove()
    check(_MatchFlow:QueueAdapter() == realQueue and _MatchFlow:TransferAdapter() == realTransfer, 'removing the test adapter restores the originals')
end)
for _, userId in ipairs(userIds) do _MatchQueueLocal:Withdraw(userId) end
for _, profile in ipairs(profiles) do _MatchQueueLocal:Release(profile) end
_MatchFaults:Remove()
if ok then
    log('[VRF][MatchQueue] PASS checks=' .. checks)
else
    log('[VRF][MatchQueue] FAIL after ' .. checks .. ' checks: ' .. tostring(detail))
end
