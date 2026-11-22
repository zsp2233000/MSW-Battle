-- Maker end-to-end for #109 (a player who disconnects while queued at second 8). One virtual player, added in Play before running this in server_main:
--   add_virtual_player -profile_code wp2621 -nickname Queue109
-- Keep the real player in formationlobby. Uses the REAL town storage: STEP 1 deletes it so the board starts clean (Gushan 100), the guard fight of STEP 5
-- writes it (Gushan 100 -> 90 on a win), STEP 8 deletes it again.
-- The disconnect is the production Depart (the same call the leave and disconnect handlers make) plus a synthetic UserReconnectEvent: the entity stays in
-- the world, like a retained disconnected entity. The real leave (KickUser + add_virtual_player) is covered by faction_war_reconnect_login_runtime_probe.lua.
-- Steps are numbered; set STEP below, dispatch, wait for the line it announces.
--   1 SETUP     server_main, ~25 s, wait "SETUP PASS" (the guard clock is the normal 10 s here)
--   2 EIGHT     server_main, ~15 s: AttackFor, Depart at 8 s. The clock is cleared, the ticket is cancelled and the lock released at once; at 13 s nothing was
--               claimed and no room was made ("EIGHT PASS")
--   3 RECONNECT server_main: a synthetic reconnect. The ticket stays cancelled (IDLE), the player is judged where they stand and keeps Zuoying
--               ("RECONNECT PASS"; [VRF][FactionWar] login judged ... then evict not needed)
--   4 RECANCEL  server_main, ~12 s: the leave cleanup fails (the queue keeps its registration, the first cancel answers an error). The ticket survives,
--               marked, with no guard clock; the reconnect cancels it again instead of resuming it: IDLE, not QUEUED ("RECANCEL PASS";
--               [VRF][MatchFlow] war ticket whose leave cleanup failed is cancelled again, not resumed)
--   5 AGAIN     server_main: AttackFor again. The clock is fresh (the 10 s count from THIS choice, not from step 2) and the guard claims the ticket
--               8 to 14 s later ("AGAIN PASS"); wait for [VRF][MatchedBattle] result published once
--   6 RETURN    server_instance_<matchKey>: ReturnForUser for the player in the room
--   7 ASSERT    server_main: back in Zuoying, unlocked, only Gushan may have changed ("E2E PASS")
--   8 CLEANUP   deletes the war town storage, puts the guard clock and the adapters back
-- Expected [VRF] lines (read with logs): see tests/README.md, "Disconnect and reconnect (#109)".
local STEP = 1
local PROFILE = "wp2621"
local function await(predicate, tries) for _ = 1, tries or 300 do if predicate() then return true end wait(0.1) end return false end
local function find()
    for _, user in ipairs(_UserService.UserEntities.Values) do
        if isvalid(user) and isvalid(user.PlayerComponent) and user.PlayerComponent.ProfileCode == PROFILE then return user end
    end
    return nil
end
local function count(map) local n = 0 for _ in pairs(map) do n = n + 1 end return n end
local function reconnect(userId)
    local event = UserReconnectEvent()
    event.UserId = userId
    _UserService:SendEvent(event)
end
local ok, reason = pcall(function()
    local a = find()
    if STEP ~= 6 then assert(isvalid(a), "virtual player connected") end
    local userId = isvalid(a) and a.PlayerComponent.UserId or nil
    if STEP == 1 then
        local record = _FormationService:GetSession(userId)
        if not record.initialized then _FormationService:Load(record) end
        assert(await(function() return record.initialized and not record.pending end), "formation loaded")
        local units = {}
        for index = 1, 4 do units[index] = { monsterId = index <= 2 and "monster_dark_centaur" or "monster_shooter", x = -3.25 - (index - 1) * 0.75, y = -1.25 } end
        local slotId = record.editSlot
        _FormationService:SaveForUser(userId, units, slotId, record.saved.slots[tostring(slotId)].revision, _UtilLogic:NewGuid())
        assert(await(function() return not record.pending and #record.saved.slots[tostring(slotId)].units == #units end), "save confirmed")
        _FormationService:ActivateForUser(userId, slotId, record.saved.slots[tostring(slotId)].revision)
        assert(await(function() return not record.pending and record.saved.activeSlot == slotId end), "activate confirmed")
        local saved = false
        _FormationStorage:Write(PROFILE, _FactionWar.FactionKey, "", "RED", function(code) saved = code == 0 end)
        await(function() return saved end, 100)
        -- A clean board: the real storage starts empty, so Gushan reads 100.
        _DataStorageService:DeleteGlobalDataStorageAndWait(_FactionWar.TownStorageName)
        -- The e2e probes of #107 and #108 park the guard at 600 s; this one needs the real 10 s.
        _FactionWarGuard.WaitSeconds = 10
        assert(_FactionWar:Move(a, "zuoying"), "move dispatched")
        assert(await(function() return a.CurrentMapName == "zuoying" end), "in Zuoying")
        log("[VRF][ReconnectQueue] SETUP PASS")
    elseif STEP == 2 then
        local roomsBefore = count(_MatchFlow._T.rooms)
        _FactionWarAttack:AttackFor(userId, "gushan")
        assert(await(function() return _MatchFlow:StateForUser(userId) == "QUEUED" end, 100), "queued")
        local queuedAt = os.clock()
        assert(_MatchFlow._T.guardTimers[userId] ~= nil, "the guard clock is running")
        wait(math.max(0, 8 - (os.clock() - queuedAt)))
        _MatchFlow:Depart(userId, "Probe")
        assert(_MatchFlow:IsOffline(userId), "marked offline")
        assert(_MatchFlow._T.guardTimers[userId] == nil, "the guard clock is cleared at once")
        assert(await(function() return _MatchFlow._T.records[userId] == nil end, 50), "the live record is gone")
        local ticket = nil
        assert(await(function()
            ticket = _FormationHandoff:Read(PROFILE)
            return ticket ~= nil and ticket.data ~= nil
        end, 50), "the durable ticket reads")
        assert(ticket.data.state == "CANCELLED", "the durable ticket is cancelled, got " .. tostring(ticket.data.state))
        assert(not _FormationHandoff:IsLockedForUser(userId), "the formation lock is released")
        -- Past the ten seconds: the guard must not have come for a player who is not there.
        wait(math.max(0, 13 - (os.clock() - queuedAt)))
        assert(_MatchFlow:StateForUser(userId) == "IDLE" and a.CurrentMapName == "zuoying", "nothing happened to the disconnected player")
        assert(count(_MatchFlow._T.rooms) == roomsBefore, "no match room was made for them")
        log("[VRF][ReconnectQueue] EIGHT PASS")
    elseif STEP == 3 then
        assert(_MatchFlow:IsOffline(userId), "still offline from step 2")
        reconnect(userId)
        assert(await(function() return not _MatchFlow:IsOffline(userId) end, 30), "online again")
        assert(await(function() return _MatchFlow:StateForUser(userId) == "IDLE" end, 50), "no ticket comes back: the player chooses again")
        assert(not _FactionWarAttack:IsEngaged(userId), "unlocked")
        -- The reconnect judges the player where they stand; Zuoying is still red, so they stay.
        wait(2)
        assert(await(function() return _FactionWar._T.placing[userId] == nil end, 100), "the login placement ended")
        assert(a.CurrentMapName == "zuoying", "a friendly town keeps its player")
        log("[VRF][ReconnectQueue] RECONNECT PASS")
    elseif STEP == 4 then
        -- The native queue keeps a departed player's registration, and the first cancellation after the leave answers an error.
        _MatchFaults:ConfigureWithdraw(true)
        _MatchFaults:ConfigureCancel(1, 0)
        _FactionWarAttack:AttackFor(userId, "gushan")
        assert(await(function() return _MatchFlow:StateForUser(userId) == "QUEUED" end, 100), "queued")
        wait(2)
        _MatchFlow:Depart(userId, "Probe")
        local ticket = _MatchFlow._T.records[userId]
        assert(ticket ~= nil and ticket.departFailed == true, "the cleanup could not finish: the ticket survives, marked")
        assert(_MatchFlow._T.guardTimers[userId] == nil, "the clock is cleared anyway")
        reconnect(userId)
        assert(await(function() return _MatchFlow._T.records[userId] == nil and _MatchFlow:StateForUser(userId) == "IDLE" end, 120), "the war ticket was cancelled again, not resumed")
        assert(not _FactionWarAttack:IsEngaged(userId), "unlocked")
        wait(1)
        assert(_MatchFlow._T.guardTimers[userId] == nil, "no guard clock came back")
        _MatchFaults:Remove()
        log("[VRF][ReconnectQueue] RECANCEL PASS")
    elseif STEP == 5 then
        _FactionWarAttack:AttackFor(userId, "gushan")
        assert(await(function() return _MatchFlow:StateForUser(userId) == "QUEUED" end, 100), "queued")
        local queuedAt = os.clock()
        local ticket = _MatchFlow._T.records[userId]
        assert(_MatchFlow._T.guardTimers[userId] ~= nil and ticket.guardStarted ~= nil and DateTime.UtcNow.Elapsed - ticket.guardStarted < 3000, "a fresh guard clock for this choice")
        assert(await(function() return _MatchFlow:StateForUser(userId) ~= "QUEUED" end, 200), "the guard claimed the ticket")
        local waited = os.clock() - queuedAt
        assert(waited > 8 and waited < 14, "the guard comes about ten seconds after THIS queue, took " .. tostring(waited))
        assert(await(function() return _MatchFlow:StateForUser(userId) == "IN_ROOM" or not isvalid(a) or a.CurrentMapName == "matchprobe" end, 300), "moved into the match room")
        log("[VRF][ReconnectQueue] AGAIN PASS after " .. tostring(waited) .. " s; wait for [VRF][MatchedBattle] result published once, run STEP 6 in the room, then STEP 7")
    elseif STEP == 6 then
        for _, user in ipairs(_UserService.UserEntities.Values) do
            if isvalid(user) and isvalid(user.PlayerComponent) then _MatchFlow:ReturnForUser(user.PlayerComponent.UserId) end
        end
        log("[VRF][ReconnectQueue] RETURN issued")
    elseif STEP == 7 then
        assert(await(function()
            a = find()
            return isvalid(a) and a.CurrentMapName == "zuoying"
        end, 400), "returned to the departure town")
        userId = a.PlayerComponent.UserId
        assert(await(function() return not _FactionWarAttack:IsEngaged(userId) end), "unlocked")
        local towns, done = nil, false
        _FactionWar:ReadTowns(function(result) towns, done = result, true end)
        assert(await(function() return done end), "towns read")
        log("[VRF][ReconnectQueue] Gushan=" .. tostring(towns.gushan.strength))
        assert(towns.zuoying.strength == 100 and towns.nanzih.strength == 100 and towns.yancheng.strength == 100, "only the guarded town may change")
        assert(towns.gushan.strength == 90 or towns.gushan.strength == 100, "a guard win takes exactly 10, anything else takes nothing")
        log("[VRF][ReconnectQueue] E2E PASS")
    elseif STEP == 8 then
        _FactionWarGuard.WaitSeconds = 10
        _MatchFaults:Remove()
        local code = _DataStorageService:DeleteGlobalDataStorageAndWait(_FactionWar.TownStorageName)
        log("[VRF][ReconnectQueue] CLEANUP town storage deleted code=" .. tostring(code))
    end
end)
if not ok then log_error("[VRF][ReconnectQueue] STEP " .. tostring(STEP) .. " FAIL " .. tostring(reason)) end
