-- Maker end-to-end for #109 (P6): a player really leaves in the middle of a guard fight and logs in again with a NEW user id (KickUser, then add_virtual_player
-- -profile_code wp2625). Two modes, set MODE below; each run is a fresh Play (stop, refresh, play) with one virtual player:
--   add_virtual_player -profile_code wp2625 -nickname Relogin109   (RED, Zuoying, 4 units; Gushan is seeded at 10, so a guard win captures it)
-- REJOIN  the room is still running when the player logs in again: the ticket still says IN_ROOM, the static room finds the room (InstanceRooms) and moves
--         the new entity back into it ("[VRF][MatchFlow] rejoin match=... moved=true", then the room's own "ARRIVED"); the fight ends there, the player
--         returns by the normal button and lands by the room's result
-- STALE   the match was settled and the room is gone (the fault adapter hides every room, as if the engine had reclaimed it): the login closes the stale ticket
--         ("STALE_ROOM_RECOVERY", "RETURN_COMPLETED"), the outcome is rebuilt from the stored record ("[VRF][FactionWarAttack] landing ... rebuilt=true",
--         the static room holds no outcome of its own) and the conqueror ends in Gushan with a town notice
-- Writes the REAL town storage (Gushan starts at 10); the last step deletes it. Keep the real player in formationlobby.
-- Steps are numbered; set MODE and STEP below, dispatch, wait for the line it announces. server_main unless it says room (the context is
-- server_instance_<matchKey>; the key is in the "QUEUED match=" line).
--   1 SETUP    ~30 s, wait "SETUP PASS"
--   2 QUEUE    AttackFor Gushan; the guard claims the ticket after 10 s and the player is moved into the room ("QUEUED match=<key>")
--   3 KICK     room. REJOIN: right after "[VRF][MatchedBattle] admission started=true" (mid-fight): KickUser. STALE: waits (up to 5 minutes) until the stored
--              record of this match exists, then KickUser. The player's entity lives in the room, so the kick is dispatched there; if it has no effect there,
--              dispatch the same step in server_main. Then (REJOIN) run the console command above at once, or (STALE) run STEP 4 first
--   4 PREPARE  server_main, STALE only: the fault adapter hides every room. Then run the console command above
--   5 CHECK    server_main, after the new virtual player appeared.
--              REJOIN: the new entity went back into the room (the room counts a user again) ("REJOIN PASS"); then wait for the result
--              STALE:  the new entity is in Gushan, holds no ticket, the town document is untouched, the match is in the history once ("STALE PASS");
--                      read the log for "login placement left to the ticket" and the town notice path ("landing after restore ... to=gushan")
--   6 RETURN   room, REJOIN only, after "[VRF][MatchedBattle] result published once": ReturnForUser for the player in the room
--   7 LANDING  server_main, REJOIN only: the player is in Gushan (Zuoying after a guard loss), unlocked, the match is in the history once ("LANDING PASS")
--   8 CLEANUP  puts the rooms back, deletes the war town storage
-- Expected [VRF] lines (read with logs): see tests/README.md, "Disconnect and reconnect (#109)".
local MODE = "REJOIN"
local STEP = 1
local PROFILE = "wp2625"
local function await(predicate, tries) for _ = 1, tries or 300 do if predicate() then return true end wait(0.1) end return false end
local function find()
    for _, user in ipairs(_UserService.UserEntities.Values) do
        if isvalid(user) and isvalid(user.PlayerComponent) and user.PlayerComponent.ProfileCode == PROFILE then return user end
    end
    return nil
end
local function readTowns()
    local towns, done = nil, false
    _FactionWar:ReadTowns(function(result) towns, done = result, true end)
    assert(await(function() return done end, 100), "towns read")
    return towns
end
local function recordsOf(towns, key)
    local n = 0
    for _, entry in ipairs(towns.settled or {}) do
        if (type(entry) == "table" and entry.k == key) or entry == key then n = n + 1 end
    end
    return n
end
local function creditedOnce(key)
    local document, code, done = nil, nil, false
    _MonsterLevelStorage:Read(PROFILE, function(c, d) code, document, done = c, d, true end)
    assert(await(function() return done end, 100) and code == 0, "monster levels read")
    local count = 0
    for _, matchId in ipairs(document.settled or {}) do if matchId == key then count = count + 1 end end
    return count
end
-- The match key of the player's ticket: the live record while it exists, else the ticket on storage (it keeps its match key after it is closed).
local function matchKey()
    local user = find()
    local ticket = isvalid(user) and _MatchFlow._T.records[user.PlayerComponent.UserId] or nil
    if ticket ~= nil and ticket.data ~= nil and ticket.data.matchKey ~= nil and ticket.data.matchKey ~= "" then return ticket.data.matchKey end
    if _RoomService:IsInstanceRoom() then return _RoomService.RoomKey end
    local stored = _FormationHandoff:Read(PROFILE)
    return stored ~= nil and stored.data ~= nil and stored.data.matchKey or ""
end
local ok, reason = pcall(function()
    local a = find()
    if STEP == 1 or STEP == 2 then assert(isvalid(a), "virtual player connected") end
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
        local towns = _FactionWar:InitialTowns()
        towns.gushan.strength = 10
        local written = false
        _FactionWar:WriteTowns(towns, function(ok) written = ok end)
        assert(await(function() return written end, 100), "Gushan seeded at 10")
        _FactionWarGuard.WaitSeconds = 10
        assert(_FactionWar:Move(a, "zuoying"), "move dispatched")
        assert(await(function() return a.CurrentMapName == "zuoying" end), "in Zuoying")
        log("[VRF][ReconnectRelogin] SETUP PASS")
    elseif STEP == 2 then
        _FactionWarAttack:AttackFor(userId, "gushan")
        assert(await(function() return _MatchFlow:StateForUser(userId) == "QUEUED" end, 100), "queued")
        local queuedAt = os.clock()
        assert(await(function() return _MatchFlow:StateForUser(userId) ~= "QUEUED" end, 200), "the guard claimed the ticket")
        local waited = os.clock() - queuedAt
        assert(waited > 8 and waited < 14, "the guard comes after about ten seconds, took " .. tostring(waited))
        local key = ""
        assert(await(function()
            key = matchKey()
            return key ~= ""
        end, 300), "the pairing is sealed")
        assert(await(function() return _MatchFlow:StateForUser(userId) == "IN_ROOM" end, 300), "the ticket is IN_ROOM")
        log("[VRF][ReconnectRelogin] QUEUED match=" .. key .. " " .. MODE .. "; wait for [VRF][MatchedBattle] admission started=true, then STEP 3 in the room")
    elseif STEP == 3 then
        local user = find()
        assert(isvalid(user), "the player is in this room")
        local key = _RoomService.RoomKey
        if MODE == "STALE" then
            local towns
            assert(await(function()
                towns = readTowns()
                return towns ~= nil and recordsOf(towns, key) == 1
            end, 3000), "the match settled and left its record")
            assert(towns.gushan.owner == "RED" and towns.gushan.strength == 100, "Gushan was captured (a guard win; run again after a loss)")
        end
        _UserService:KickUser(user.PlayerComponent.UserId, KickReason.ETC)
        assert(await(function() return find() == nil end, 100), "the entity left")
        log("[VRF][ReconnectRelogin] KICKED match=" .. key .. "; " .. (MODE == "STALE" and "run STEP 4, then" or "now") .. " add_virtual_player -profile_code " .. PROFILE .. " -nickname Relogin109, then STEP 5")
    elseif STEP == 4 then
        assert(MODE == "STALE", "only the STALE mode hides the rooms")
        _MatchFaults:ConfigureRooms(true)
        log("[VRF][ReconnectRelogin] rooms hidden; now add_virtual_player -profile_code " .. PROFILE .. " -nickname Relogin109, then STEP 5")
    elseif STEP == 5 then
        local key = matchKey()
        assert(key ~= "", "the ticket on storage knows its match")
        if MODE == "REJOIN" then
            local found, room = _RoomService.InstanceRooms:TryGetValue(key)
            assert(found and room ~= nil and room:IsValid(), "the room is still there")
            assert(await(function() return room:GetUserCount() >= 1 end, 150), "the new entity went back into the room")
            log("[VRF][ReconnectRelogin] REJOIN PASS match=" .. key .. "; wait for [VRF][MatchedBattle] result published once, run STEP 6 in the room, then STEP 7")
        else
            assert(await(function()
                a = find()
                return isvalid(a) and a.CurrentMapName == "gushan"
            end, 250), "the new entity was put in Gushan by the stored result")
            userId = a.PlayerComponent.UserId
            assert(await(function() return _MatchFlow._T.records[userId] == nil and not _FactionWarAttack:IsEngaged(userId) end, 100), "the stale ticket is closed and nothing is locked")
            assert(_FactionWarAttack._T.outcomes[key] == nil, "this room holds no outcome of its own: the landing came from the stored record")
            local towns = readTowns()
            assert(towns.gushan.owner == "RED" and towns.gushan.strength == 100 and recordsOf(towns, key) == 1 and #towns.settled == 1, "the town document was only read")
            assert(creditedOnce(key) == 1, "the match is in the history exactly once")
            log("[VRF][ReconnectRelogin] STALE PASS match=" .. key)
        end
    elseif STEP == 6 then
        local user = find()
        assert(isvalid(user), "the player is in the room")
        _MatchFlow:ReturnForUser(user.PlayerComponent.UserId)
        log("[VRF][ReconnectRelogin] RETURN issued")
    elseif STEP == 7 then
        local towns = readTowns()
        local captured = towns.gushan.owner == "RED"
        local expected = captured and "gushan" or "zuoying"
        assert(await(function()
            a = find()
            return isvalid(a) and a.CurrentMapName == expected
        end, 600), "landed in " .. expected)
        userId = a.PlayerComponent.UserId
        assert(await(function() return not _FactionWarAttack:IsEngaged(userId) end), "unlocked")
        local key = matchKey()
        assert(key ~= "" and creditedOnce(key) == 1, "the match is in the history exactly once")
        if captured then assert(recordsOf(towns, key) == 1 and #towns.settled == 1, "one settlement, one capture") end
        log("[VRF][ReconnectRelogin] LANDING PASS in " .. expected)
    elseif STEP == 8 then
        _FactionWarGuard.WaitSeconds = 10
        _MatchFaults:Remove()
        local code = _DataStorageService:DeleteGlobalDataStorageAndWait(_FactionWar.TownStorageName)
        log("[VRF][ReconnectRelogin] CLEANUP town storage deleted code=" .. tostring(code))
    end
end)
if not ok then log_error("[VRF][ReconnectRelogin] " .. MODE .. " STEP " .. tostring(STEP) .. " FAIL " .. tostring(reason)) end
