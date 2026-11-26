-- Maker end-to-end for #121 / ADR 0017: a side that arrives after the fight began is a participant, not a spectator. Two players, added in a fresh Play:
--   add_virtual_player -profile_code wp2601 -nickname LateA        (A, RED, Zuoying, 3 tanks, on time)
--   add_virtual_player -profile_code wp2602 -nickname LateB        (B, BLUE, Gushan, 1 tank, late)
-- Set B_PROFILE to the ProfileCode of the real Maker client to read the late player's screen (STEP 5, client); the real client then plays BLUE
-- with an isolated formation key, and "wp2602" is not needed.
-- Steps (server_main unless it says otherwise; wait for each terminal line before the next):
--   1 SETUP    prepares both players (about 40 s, "SETUP PASS").
--   2 LATE     arms B's absence, queues both, waits LATE_AFTER seconds (the fight is on), disarms and recovers B: B moves into the running room ("LATE PASS" with the room key).
--   3 ROOM     (server_instance_<matchKey>) B is a participant: present, ticket IN_ROOM, battle side, snapshot state BATTLE/RESULT_*, experience once; A and B then return.
--   4 ASSERT   (server_main) one result, Gushan 100 -> 80 once, B's experience once, both players home and unlocked.
--   5 CLIENT   (client, only with the real client as B) the late player's result page, experience and return button.
--   6 CLEANUP  disarms the fault and deletes the town storage.
-- BASE_* are B's tank level, experience and settled count that STEP 2 logged as "baseline"; substitute them before STEP 4.
local STEP = 1
local B_PROFILE = "wp2602"
local LATE_AFTER = 36
local BASE_LEVEL = 1
local BASE_EXP = 0
local BASE_SETTLED = 0
local ROOM_KEY = "SET_ME"
local function await(predicate, tries) for _ = 1, tries or 300 do if predicate() then return true end wait(0.1) end return false end
local function find()
    local found = {}
    for _, user in ipairs(_UserService.UserEntities.Values) do found[user.PlayerComponent.ProfileCode] = user end
    return found["wp2601"], found[B_PROFILE]
end
local function progressOf(profile)
    local result, done = nil, false
    _MonsterLevelStorage:Read(profile, function(code, document)
        result, done = code == 0 and document or {}, true
    end)
    await(function() return done end, 100)
    local progress = result ~= nil and result.monsters ~= nil and result.monsters["monster_tank"] or nil
    return { level = progress ~= nil and progress.level or 1, experience = progress ~= nil and progress.experience or 0, settled = #(result ~= nil and result.settled or {}) }
end
local ok, reason = pcall(function()
    local a, b = find()
    if STEP == 1 then
        assert(isvalid(a) and isvalid(b), "both players connected")
        if B_PROFILE ~= "wp2602" then _FormationService.StorageKey = "Late121_" .. _UtilLogic:NewGuid() end
        for _, user in ipairs({ a, b }) do
            local record = _FormationService:GetSession(user.PlayerComponent.UserId)
            if B_PROFILE ~= "wp2602" or not record.initialized then _FormationService:Load(record) end
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
        local written = false
        _FactionWarTownDocument:WriteTowns(_FactionWarTownDocument:InitialTowns(), function(saved) written = saved == true end)
        assert(await(function() return written end, 100), "the town table is reset")
        for user, value in pairs({ [a] = "RED", [b] = "BLUE" }) do
            local saved = false
            _FormationStorage:Write(user.PlayerComponent.ProfileCode, _FactionWar.FactionKey, "", value, function(code) saved = code == 0 end)
            await(function() return saved end, 100)
        end
        assert(_FactionWar:Move(a, "zuoying") and _FactionWar:Move(b, "gushan"), "moves dispatched")
        assert(await(function() return a.CurrentMapName == "zuoying" and b.CurrentMapName == "gushan" end), "players in their towns")
        log("[VRF][LateE2E] SETUP PASS")
    elseif STEP == 2 then
        assert(isvalid(a) and isvalid(b), "both players connected")
        local idA, idB = a.PlayerComponent.UserId, b.PlayerComponent.UserId
        local base = progressOf(b.PlayerComponent.ProfileCode)
        log("[VRF][LateE2E] baseline levelB=" .. tostring(base.level) .. " expB=" .. tostring(base.experience) .. " settledB=" .. tostring(base.settled))
        _MatchFaults:ConfigureAbsent(idB, true)
        _FactionWarAttack:AttackFor(idA, "gushan")
        assert(await(function() return _FactionWarAttack:IsEngaged(idA) end, 100), "A engaged")
        _FactionWarAttack:AttackFor(idB, "zuoying")
        local queuedAt = DateTime.UtcNow.Elapsed
        local key = nil
        assert(await(function()
            for matchKey, slot in pairs(_MatchFlow._T.rooms) do
                if not slot.creating and slot.room ~= nil then key = matchKey end
            end
            return key ~= nil
        end, 300), "the match room is created")
        log("[VRF][LateE2E] QUEUED room key=" .. key)
        -- Let the fight start without B, then let B arrive.
        wait(math.max(0, LATE_AFTER - (DateTime.UtcNow.Elapsed - queuedAt) / 1000))
        local room = _MatchTransfer:FindRoom(key)
        assert(room ~= nil, "the match room runs")
        _MatchFaults:ConfigureAbsent(idB, false)
        log("[VRF][LateE2E] B is released at +" .. tostring(math.floor((DateTime.UtcNow.Elapsed - queuedAt) / 1000)) .. " s")
        _MatchFlow:Recover(idB)
        assert(await(function()
            local _, now = find()
            return not isvalid(now) or now.CurrentMapName == "matchprobe"
        end, 150), "B moved into the match room")
        log("[VRF][LateE2E] LATE PASS room key=" .. key)
    elseif STEP == 3 then
        local map = _EntityService:GetEntityByPath("/maps/matchprobe")
        assert(isvalid(map) and _RoomService:IsInstanceRoom(), "dispatch in server_instance_<matchKey>")
        local battle = map:GetComponent("script.BattleSession")
        local present = {}
        for _, user in ipairs(_UserService.UserEntities.Values) do present[user.PlayerComponent.ProfileCode] = user end
        local late, onTime = present[B_PROFILE], present["wp2601"]
        assert(isvalid(late), "the late player is in the room")
        local idB = late.PlayerComponent.UserId
        log("[VRF][LateE2E] ROOM arrival phase=" .. battle.Phase .. " result=" .. battle.Result .. " both=" .. tostring(isvalid(onTime)))
        local snapshot = _MatchFlow:StateSnapshot(idB, "")
        log("[VRF][LateE2E] ROOM B state=" .. snapshot.state .. " reason=" .. tostring(snapshot.reasonCode))
        assert(snapshot.state ~= "ENTRY_FAILED" and snapshot.state ~= "ABORTED" and snapshot.state ~= "IDLE", "the late player is not turned away: " .. snapshot.state)
        assert(_MatchFlow:StateForUser(idB) == "IN_ROOM", "the late player's ticket is IN_ROOM")
        assert(battle.HomeProfile == "wp2601" or battle.AwayProfile == "wp2601", "A is a side")
        assert(battle:ParticipantSide(B_PROFILE) == "ENEMY", "B has the same standing as a side that came on time: the ENEMY side")
        assert(battle:ParticipantSide("wp2601") == "PLAYER", "A is the PLAYER side")
        assert(battle:ParticipantSide("wp9999") == "", "a stranger has no side")
        assert(await(function() return battle.Phase == "RESULT" end, 900), "the battle ended")
        assert(await(function() return _MatchFlow:StateSnapshot(idB, "").state == "RESULT_LOSE" end, 50), "B reads the result page (RESULT_LOSE)")
        assert(await(function() return battle.ExperienceResult ~= nil end, 20), "experience results exist")
        wait(2)
        for _, user in ipairs(_UserService.UserEntities.Values) do
            _MatchFlow:ReturnForUser(user.PlayerComponent.UserId)
        end
        log("[VRF][LateE2E] ROOM PASS the late player saw the same battle and result; both pressed Return")
    elseif STEP == 4 then
        local towns, done = nil, false
        _FactionWarTownDocument:Read(function(result) towns, done = result, true end)
        assert(await(function() return done end), "towns read")
        assert(towns.gushan.strength == 80 and towns.zuoying.strength == 100 and towns.gushan.owner == "BLUE", "Gushan 100 -> 80 once")
        assert(#(towns.settled or {}) == 1, "the result was written exactly once")
        local afterB = progressOf(b ~= nil and b.PlayerComponent.ProfileCode or B_PROFILE)
        assert(afterB.settled == BASE_SETTLED + 1 and (afterB.level > BASE_LEVEL or afterB.experience > BASE_EXP), "B's experience was settled exactly once")
        assert(await(function()
            local x, y = find()
            return isvalid(x) and isvalid(y) and x.CurrentMapName == "zuoying" and y.CurrentMapName == "gushan"
        end, 300), "both are back in their towns")
        local x, y = find()
        assert(await(function() return not _FormationHandoff:IsLockedForUser(y.PlayerComponent.UserId) and not _FormationHandoff:IsLockedForUser(x.PlayerComponent.UserId) end, 150), "both are unlocked")
        log("[VRF][LateE2E] ASSERT PASS settled once, B experience once, both home and unlocked")
    elseif STEP == 5 then
        local player = _UserService.LocalPlayer
        assert(player.CurrentMapName == "matchprobe", "the real client is in the match room")
        local map = _EntityService:GetEntityByPath("/maps/matchprobe")
        local battle = map:GetComponent("script.BattleSession")
        assert(await(function() return string.sub(_MatchFlowInput.Snapshot.state or "", 1, 7) == "RESULT_" end, 900), "the late player's result page is shown")
        assert(await(function() return battle.ExperienceResult ~= nil and battle.ExperienceResult.status == "SAVED" end, 100), "the late player's experience receipt arrived")
        local view = _MatchFlowInput:View()
        assert(view.action == "RETURN" and string.find(view.label, "返回", 1, true) ~= nil, "the late player has the same return button: " .. tostring(view.label))
        log("[VRF][LateE2E] CLIENT PASS state=" .. _MatchFlowInput.Snapshot.state .. " label=" .. view.label .. " exp=" .. tostring(#battle.ExperienceResult.monsters))
    elseif STEP == 6 then
        _MatchFaults:Remove()
        for _, user in ipairs({ a, b }) do
            if isvalid(user) then _MatchFlow:ReturnForUser(user.PlayerComponent.UserId) end
        end
        local code = _DataStorageService:DeleteGlobalDataStorageAndWait(_FactionWarTownDocument.TownStorageName)
        log("[VRF][LateE2E] CLEANUP town storage deleted code=" .. tostring(code))
        log("[VRF][LateE2E] CLEANUP PASS")
    end
end)
if not ok then log_error("[VRF][LateE2E] STEP " .. tostring(STEP) .. " FAIL " .. tostring(reason)) end
