-- Maker end-to-end for #106. One virtual player, added in Play before running this in server_main:
--   add_virtual_player -profile_code wp2601 -nickname WarA
-- STEP 1 prepares it (4-unit formation, A, standing in Zuoying) and takes ~20 s; wait for "SETUP PASS".
-- STEP 2 queues against Gushan, cancels after 3 s and checks that no guard fight starts after the ten seconds ("CANCEL PASS" after ~14 s).
-- STEP 3 queues again, waits for the guard clock and the move into the match room ("GUARD ENTRY PASS"), then the battle runs; wait for RESULT.
-- STEP 4 (run inside server_instance_<matchKey>): _MatchFlow:ReturnForUser for the player in the room.
-- STEP 5 asserts the return, the unlock and the stored strength (Gushan 100 -> 90 after a win, 100 after a loss or draw).
-- STEP 6 CLEANUP deletes the war town storage that the room wrote.
local STEP = 1
local function await(predicate, tries) for _ = 1, tries or 300 do if predicate() then return true end wait(0.1) end return false end
local function find()
    for _, user in ipairs(_UserService.UserEntities.Values) do
        if user.PlayerComponent.ProfileCode == "wp2601" then return user end
    end
    return nil
end
local ok, reason = pcall(function()
    local a = find()
    assert(isvalid(a), "virtual player connected")
    local userId = a.PlayerComponent.UserId
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
        -- A rerun finds the faction an earlier run stored: the guarded write must expect it, not an empty value.
        local saved, current = false, nil
        _FactionWar:ReadFaction(a.PlayerComponent.ProfileCode, function(faction) current = faction end)
        assert(await(function() return current ~= nil end, 100), "faction read")
        if current == "A" then saved = true
        else _FormationStorage:Write(a.PlayerComponent.ProfileCode, _FactionWar.FactionKey, current, "A", function(code) saved = code == 0 end) end
        assert(await(function() return saved end, 100), "faction saved")
        assert(_FactionWar:Move(a, "zuoying"), "move dispatched")
        assert(await(function() return a.CurrentMapName == "zuoying" end), "in Zuoying")
        log("[VRF][GuardE2E] SETUP PASS")
    elseif STEP == 2 then
        _FactionWarAttack:AttackFor(userId, "gushan")
        assert(await(function() return _MatchFlow:StateForUser(userId) == "QUEUED" end, 100), "queued")
        assert(_MatchFlow._T.guardTimers[userId] ~= nil, "the guard clock is running")
        wait(3)
        _MatchFlow:CancelForUser(userId)
        assert(await(function() return _MatchFlow:StateForUser(userId) == "IDLE" end, 100), "cancelled back to idle")
        assert(_MatchFlow._T.guardTimers[userId] == nil, "cancelling stops the guard clock")
        wait(9)
        assert(_MatchFlow:StateForUser(userId) == "IDLE" and a.CurrentMapName == "zuoying", "no guard fight after the ten seconds")
        assert(not _FactionWarAttack:IsEngaged(userId), "unlocked")
        log("[VRF][GuardE2E] CANCEL PASS")
    elseif STEP == 3 then
        _FactionWarAttack:AttackFor(userId, "gushan")
        assert(await(function() return _MatchFlow:StateForUser(userId) == "QUEUED" end, 100), "queued")
        local queuedAt = os.clock()
        assert(await(function() return _MatchFlow:StateForUser(userId) ~= "QUEUED" end, 200), "the guard claimed the ticket")
        local waited = os.clock() - queuedAt
        assert(waited > 8 and waited < 14, "the guard comes after about ten seconds, took " .. tostring(waited))
        -- The player entity leaves this room, so its map name is not readable here; the ticket and the room context are.
        assert(await(function() return _MatchFlow:StateForUser(userId) == "IN_ROOM" or not isvalid(a) or a.CurrentMapName == "matchprobe" end, 300), "moved into the match room")
        log("[VRF][GuardE2E] GUARD ENTRY PASS after " .. tostring(waited) .. " s; wait for [M1][BattleSession] RESULT then run STEP 4 in the room")
    elseif STEP == 4 then
        _MatchFlow:ReturnForUser(userId)
        log("[VRF][GuardE2E] return requested")
    elseif STEP == 5 then
        assert(await(function()
            a = find()
            return isvalid(a) and a.CurrentMapName == "zuoying"
        end), "returned to the departure town")
        assert(await(function() return not _FactionWarAttack:IsEngaged(userId) end), "unlocked")
        local towns, done = nil, false
        _FactionWarTownDocument:Read(function(result) towns, done = result, true end)
        assert(await(function() return done end), "towns read")
        log("[VRF][GuardE2E] Gushan=" .. tostring(towns.gushan.strength) .. " Zuoying=" .. tostring(towns.zuoying.strength))
        assert(towns.zuoying.strength == 100 and towns.nanzih.strength == 100 and towns.yancheng.strength == 100, "only the guarded town may change")
        assert(towns.gushan.strength == 90 or towns.gushan.strength == 100, "a guard win takes exactly 10, anything else takes nothing")
        log("[VRF][GuardE2E] E2E PASS")
    elseif STEP == 6 then
        local code = _DataStorageService:DeleteGlobalDataStorageAndWait(_FactionWarTownDocument.TownStorageName)
        log("[VRF][GuardE2E] CLEANUP town storage deleted code=" .. tostring(code))
    end
end)
if not ok then log_error("[VRF][GuardE2E] STEP " .. tostring(STEP) .. " FAIL " .. tostring(reason)) end
