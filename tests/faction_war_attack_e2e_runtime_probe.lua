-- Maker end-to-end for #105. Needs two virtual players, added in Play before running this in server_main:
--   add_virtual_player -profile_code wp2601 -nickname WarA
--   add_virtual_player -profile_code wp2602 -nickname WarB
-- STEP 1 prepares them (3-unit vs 1-unit formation, RED vs BLUE, in Zuoying and Gushan) and takes ~40 s; wait for "SETUP PASS".
-- STEP 2 queues both through the NPC's server entry (AttackFor), so the human match forms on mutual targets; wait for RESULT.
-- STEP 3 (run inside server_instance_<matchKey>): _MatchFlow:ReturnForUser for each user in the room.
-- STEP 4 asserts the return, the unlock and the stored strength. CLEANUP deletes the war town storage that the room wrote.
-- Expected: Gushan 100 -> 80 after the RED (home, 3 tanks) win; Zuoying 100; both players back in their own town and unlocked.
local STEP = 1
local function await(predicate, tries) for _ = 1, tries or 300 do if predicate() then return true end wait(0.1) end return false end
local function find()
    local found = {}
    for _, user in ipairs(_UserService.UserEntities.Values) do found[user.PlayerComponent.ProfileCode] = user end
    return found["wp2601"], found["wp2602"]
end
local ok, reason = pcall(function()
    local a, b = find()
    assert(isvalid(a) and isvalid(b), "both virtual players connected")
    if STEP == 1 then
        for _, user in ipairs({ a, b }) do
            local record = _FormationService:GetSession(user.PlayerComponent.UserId)
            if not record.initialized then _FormationService:Load(record) end
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
        for user, value in pairs({ [a] = "RED", [b] = "BLUE" }) do
            local saved = false
            _FormationStorage:Write(user.PlayerComponent.ProfileCode, _FactionWar.FactionKey, "", value, function(code) saved = code == 0 end)
            await(function() return saved end, 100)
        end
        assert(_FactionWar:Move(a, "zuoying") and _FactionWar:Move(b, "gushan"), "moves dispatched")
        assert(await(function() return a.CurrentMapName == "zuoying" and b.CurrentMapName == "gushan" end), "players in their towns")
        log("[VRF][WarE2E] SETUP PASS")
    elseif STEP == 2 then
        _FactionWarAttack:AttackFor(a.PlayerComponent.UserId, "gushan")
        assert(await(function() return _FactionWarAttack:IsEngaged(a.PlayerComponent.UserId) end, 100), "A engaged")
        -- A blue player cannot attack the town they stand in; the answer is INVALID and no ticket appears.
        _FactionWarAttack:AttackFor(b.PlayerComponent.UserId, "gushan")
        assert(await(function() return not _FactionWarAttack._T.reading[b.PlayerComponent.UserId] end, 100), "B refused")
        assert(not _FactionWarAttack:IsEngaged(b.PlayerComponent.UserId), "B has no ticket after a self-target")
        _FactionWarAttack:AttackFor(b.PlayerComponent.UserId, "zuoying")
        log("[VRF][WarE2E] ATTACKS ISSUED; wait for [M1][BattleSession] RESULT then run STEP 3")
    elseif STEP == 4 then
        assert(await(function()
            a, b = find()
            return isvalid(a) and isvalid(b) and a.CurrentMapName == "zuoying" and b.CurrentMapName == "gushan"
        end), "both returned to their departure towns")
        for _, user in ipairs({ a, b }) do
            assert(await(function() return not _FactionWarAttack:IsEngaged(user.PlayerComponent.UserId) end), "unlocked")
        end
        local towns, done = nil, false
        _FactionWar:ReadTowns(function(result) towns, done = result, true end)
        assert(await(function() return done end), "towns read")
        assert(towns.gushan.strength == 80 and towns.zuoying.strength == 100 and towns.gushan.owner == "BLUE", "Gushan 100 -> 80 only")
        assert(towns.nanzih.strength == 100 and towns.yancheng.strength == 100, "capitals untouched")
        log("[VRF][WarE2E] E2E PASS")
    elseif STEP == 5 then
        local code = _DataStorageService:DeleteGlobalDataStorageAndWait(_FactionWar.TownStorageName)
        log("[VRF][WarE2E] CLEANUP town storage deleted code=" .. tostring(code))
    end
end)
if not ok then log_error("[VRF][WarE2E] STEP " .. tostring(STEP) .. " FAIL " .. tostring(reason)) end
