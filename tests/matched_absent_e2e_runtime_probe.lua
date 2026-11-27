-- Maker end-to-end for #120 / ADR 0017: a match room starts without the side that never enters. Needs two virtual players, added in a fresh Play:
--   add_virtual_player -profile_code wp2601 -nickname AbsentA
--   add_virtual_player -profile_code wp2602 -nickname AbsentB
-- Run every step in server_main unless it says otherwise. MODE is edited by substitution before dispatch:
--   WAR   A (A, Zuoying, 3 tanks) attacks Gushan, B (B, Gushan, 1 tank) attacks Zuoying but never enters the room.
--   STOP  as WAR, and B presses Stop Entry while the room waits (STEP 3): the battle still fields B's frozen roster.
--   EMPTY nobody enters the room: no battle, nothing deducted, no experience.
--   LOBBY lobby match (no towns): B never enters, the battle still runs and both experiences are settled.
-- STEP 1 prepares both players (about 40 s, wait for "SETUP PASS"). STEP 2 arms the fault and queues both ("QUEUED").
-- STEP 3 (STOP only, 8-25 s after STEP 2, before the room starts): B stops entry. STEP 4 asserts, 60 s after STEP 2 (waiting 30 s + battle).
-- STEP 5 (inside server_instance_<matchKey>, the match room): A returns. STEP 6 disarms the fault, returns B and deletes the town storage.
-- BASE_LEVEL, BASE_EXP and BASE_SETTLED are B's tank level, experience and settled-match count that STEP 2 logged as "baseline"; substitute them before STEP 4.
local STEP = 1
local MODE = "WAR"
local BASE_LEVEL = 1
local BASE_EXP = 0
local BASE_SETTLED = 0
-- "wp2601" is the second virtual player. Set the ProfileCode of the real Maker client to see the waiting text on a real screen (STEP 7);
-- an isolated formation key keeps that profile's saved teams untouched.
local A_PROFILE = "wp2601"
local function await(predicate, tries) for _ = 1, tries or 300 do if predicate() then return true end wait(0.1) end return false end
local function find()
    local found = {}
    for _, user in ipairs(_UserService.UserEntities.Values) do found[user.PlayerComponent.ProfileCode] = user end
    return found[A_PROFILE], found["wp2602"]
end
local function progressOf(profile)
    -- B's tank level and experience, and how many settled matches the profile's level document lists.
    local result, done = nil, false
    _MonsterLevelStorage:Read(profile, function(code, document)
        result, done = code == 0 and document or {}, true
    end)
    await(function() return done end, 100)
    local progress = result ~= nil and result.monsters ~= nil and result.monsters["monster_tank"] or nil
    return { level = progress ~= nil and progress.level or 1, experience = progress ~= nil and progress.experience or 0, settled = #(result ~= nil and result.settled or {}) }
end
local function advanced(progress) return progress.level > BASE_LEVEL or progress.experience > BASE_EXP end
local war = MODE ~= "LOBBY"
local ok, reason = pcall(function()
    local a, b = find()
    -- Once A is in the match room only B is left in this room's user list.
    if STEP == 1 or STEP == 2 then assert(isvalid(a) and isvalid(b), "both virtual players connected") end
    if STEP == 3 or STEP == 4 or STEP == 6 then assert(isvalid(b), "B is connected") end
    if STEP == 1 then
        if A_PROFILE ~= "wp2601" then _FormationService.StorageKey = "Absent120_" .. _UtilLogic:NewGuid() end
        for _, user in ipairs({ a, b }) do
            local record = _FormationService:GetSession(user.PlayerComponent.UserId)
            -- An isolated formation key (the real client) must be read again; the virtual players load once.
            if A_PROFILE ~= "wp2601" or not record.initialized then _FormationService:Load(record) end
            assert(await(function() return record.initialized and not record.pending end), "formation loaded")
        end
        local function setup(user, units)
            local userId = user.PlayerComponent.UserId
            local record = _FormationService:GetSession(userId)
            local slotId = record.editSlot
            _FormationService:SaveForUser(userId, units, slotId, record.saved.slots[tostring(slotId)].revision, _UtilLogic:NewGuid())
            assert(await(function() return not record.pending and #record.saved.slots[tostring(slotId)].units == #units end), "save confirmed")
            _FormationService:ActivateForUser(userId, slotId, record.saved.slots[tostring(slotId)].revision)
            assert(await(function() return not record.pending and record.saved.activeSlot == slotId end), "activate confirmed")
        end
        local three = {}
        for index = 1, 3 do three[index] = { monsterId = "monster_tank", x = -3.25 - (index - 1) * 0.75, y = -1.25 } end
        setup(a, three)
        setup(b, {{ monsterId = "monster_tank", x = -3.25, y = -1.25 }})
        if war then
            local written = false
            _FactionWarTownDocument:WriteTowns(_FactionWarTownDocument:InitialTowns(), function(saved) written = saved == true end)
            assert(await(function() return written end, 100), "the town table is reset")
            for user, value in pairs({ [a] = "A", [b] = "B" }) do
                local saved = false
                _FormationStorage:Write(user.PlayerComponent.ProfileCode, _FactionWar.FactionKey, "", value, function(code) saved = code == 0 end)
                await(function() return saved end, 100)
            end
            assert(_FactionWar:Move(a, "zuoying") and _FactionWar:Move(b, "gushan"), "moves dispatched")
            assert(await(function() return a.CurrentMapName == "zuoying" and b.CurrentMapName == "gushan" end), "players in their towns")
        else
            for _, user in ipairs({ a, b }) do
                -- A previous mode may have left them in a town.
                if user.CurrentMapName ~= "formationlobby" then _TeleportService:TeleportToMapPosition(user, Vector3(0, 0, 0), "formationlobby") end
            end
            -- Moving to another static room replaces the entity, so look the players up again.
            assert(await(function()
                a, b = find()
                return isvalid(a) and isvalid(b) and a.CurrentMapName == "formationlobby" and b.CurrentMapName == "formationlobby"
            end, 300), "players in the lobby")
        end
        log("[VRF][AbsentE2E] SETUP PASS mode=" .. MODE)
    elseif STEP == 2 then
        local idA, idB = a.PlayerComponent.UserId, b.PlayerComponent.UserId
        local base = progressOf(b.PlayerComponent.ProfileCode)
        log("[VRF][AbsentE2E] baseline levelB=" .. tostring(base.level) .. " expB=" .. tostring(base.experience) .. " settledB=" .. tostring(base.settled))
        _MatchFaults:ConfigureAbsent(idB, true)
        if MODE == "EMPTY" then _MatchFaults:ConfigureAbsent(idA, true) end
        if war then
            _FactionWarAttack:AttackFor(idA, "gushan")
            assert(await(function() return _FactionWarAttack:IsEngaged(idA) end, 100), "A engaged")
            _FactionWarAttack:AttackFor(idB, "zuoying")
        else
            _MatchFlow:QueueForUser(idA)
            _MatchFlow:QueueForUser(idB)
        end
        log("[VRF][AbsentE2E] QUEUED mode=" .. MODE .. " at=" .. tostring(DateTime.UtcNow.Elapsed))
    elseif STEP == 3 then
        local idB = b.PlayerComponent.UserId
        local snapshot = _MatchFlow:StateSnapshot(idB, "")
        log("[VRF][AbsentE2E] B before stop state=" .. snapshot.state .. " reason=" .. tostring(snapshot.reasonCode) .. " found=" .. tostring(snapshot.opponentFound))
        assert(_MatchFlowState:EntryFailed(snapshot, DateTime.UtcNow.Elapsed), "B sees the entry failure and may stop entry")
        _MatchFlow:ReturnForUser(idB)
        assert(await(function() return not _FormationHandoff:IsLockedForUser(idB) end, 150), "B's ticket is closed and unlocked")
        log("[VRF][AbsentE2E] STOP PASS B stopped entry while the room was waiting")
    elseif STEP == 4 then
        local idB = b.PlayerComponent.UserId
        local towns, done = nil, false
        _FactionWarTownDocument:Read(function(result) towns, done = result, true end)
        assert(await(function() return done end), "towns read")
        local afterB = progressOf(b.PlayerComponent.ProfileCode)
        if MODE == "EMPTY" then
            for _, id in ipairs(_FactionWarTownDocument.TownOrder) do assert(towns[id].strength == 100, "nothing deducted from " .. id) end
            assert(not advanced(afterB) and afterB.settled == BASE_SETTLED, "no experience without a battle")
            assert(#(towns.settled or {}) == 0, "no result was written")
            log("[VRF][AbsentE2E] EMPTY PASS no battle, no deduction, no experience")
        elseif war then
            assert(towns.gushan.strength == 80 and towns.zuoying.strength == 100 and towns.gushan.owner == "B", "Gushan 100 -> 80 once, by the absent side's loss")
            assert(#(towns.settled or {}) == 1, "the result was written exactly once")
            assert(advanced(afterB) and afterB.settled == BASE_SETTLED + 1, "B's frozen tank died once: its progress advanced and the match settled exactly once; now level " .. tostring(afterB.level) .. " exp " .. tostring(afterB.experience) .. " settled " .. tostring(afterB.settled))
            log("[VRF][AbsentE2E] " .. MODE .. " PASS the absent side fought, settled once, experience saved")
        else
            assert(advanced(afterB) and afterB.settled == BASE_SETTLED + 1, "lobby match: B's tank progress advanced and the match settled exactly once")
            log("[VRF][AbsentE2E] LOBBY PASS the absent side fought and earned experience")
        end
        log("[VRF][AbsentE2E] ticket B=" .. _MatchFlow:StateForUser(idB))
    elseif STEP == 5 then
        for _, user in ipairs(_UserService.UserEntities.Values) do
            _MatchFlow:ReturnForUser(user.PlayerComponent.UserId)
        end
        log("[VRF][AbsentE2E] ROOM return dispatched")
    elseif STEP == 7 then
        -- client context, while the room waits: the on-time human reads the countdown on the real screen.
        local player = _UserService.LocalPlayer
        assert(player.CurrentMapName == "matchprobe", "the real client is in the match room")
        assert(await(function() return string.find(_MatchFlowInput:View().text, "等待對手進入戰場", 1, true) ~= nil end, 150), "the waiting text is shown")
        local view = _MatchFlowInput:View()
        assert(view.action == "" and view.label == "" and not view.enabled, "no button while waiting")
        assert(await(function()
            local status = _MatchFlowInput.status
            return isvalid(status) and string.find(status.TextGUIRendererComponent.Text, view.text, 1, true) ~= nil
        end, 50), "the visible status line shows it")
        log("[VRF][AbsentE2E] CLIENT_WAIT PASS text=" .. view.text)
    elseif STEP == 6 then
        _MatchFaults:Remove()
        -- The result of this run may have written an absent record (#122); leave none behind for the next probe.
        for _, profile in ipairs({ A_PROFILE, "wp2602" }) do
            local record = _AbsentResult:PendingFor(profile)
            if record ~= nil then
                local cleared = false
                _AbsentResult:Clear(profile, record.id, function() cleared = true end)
                await(function() return cleared end, 100)
            end
        end
        for _, user in ipairs({ a, b }) do
            -- Whoever still holds a ticket in this room (the absent side, or both in EMPTY) stops entry.
            if isvalid(user) then _MatchFlow:ReturnForUser(user.PlayerComponent.UserId) end
        end
        if war then
            local code = _DataStorageService:DeleteGlobalDataStorageAndWait(_FactionWarTownDocument.TownStorageName)
            log("[VRF][AbsentE2E] CLEANUP town storage deleted code=" .. tostring(code))
        end
        log("[VRF][AbsentE2E] CLEANUP PASS")
    end
end)
if not ok then log_error("[VRF][AbsentE2E] STEP " .. tostring(STEP) .. " FAIL " .. tostring(reason)) end
