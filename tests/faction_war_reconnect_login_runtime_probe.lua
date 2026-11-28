-- Maker probe for #109 (P5): where a player lands when they log in. It needs real logins, so the virtual player is added AFTER STEP 1 has seeded its storage and
-- is kicked by STEP 3 (a true leave, then a true login with a NEW user id: _UserService:KickUser + add_virtual_player -profile_code wpNNNN).
-- Keep the real player in formationlobby (a real player who has a faction and a last town would be placed too). It uses an isolated town storage name
-- ("CountryWarProbe109V1": the static room is server_main, so the swap is effective for the login placement) and the profile codes wp2625 / wp2626;
-- STEP 4 restores the storage name and deletes what the probe wrote. Final line of each STEP 2: [VRF][ReconnectLogin] <CASE> PASS.
-- For every CASE in the table: STEP 1 (seed), then the console command in the table, then STEP 2 (check), then STEP 3 (kick). Set CASE and STEP below.
--   CASE            profile  seeded                                              expected
--   FRIENDLY        wp2625   A, last town Zuoying, Zuoying red                 lands in Zuoying
--   FALLEN          wp2625   A, last town Zuoying, Zuoying B (count 1)      lands in Nanzih (the capital), the last town is now Nanzih
--   RETAKEN         wp2625   A, last town Zuoying, Zuoying red (count 2)       lands in Zuoying (fell and was retaken: home)
--   NOFACTION       wp2626   no faction, last town Zuoying                       stays in formationlobby
--   NOTOWN          wp2625   A, no last town                                   stays in formationlobby
--   OFFLINE_FALL    wp2626   B, no last town; the probe moves it to Gushan     goes offline in Gushan; Gushan falls to red; the fall sweep skips it
--                                                                                 ("sweep skipped offline"); the reconnect sends it to Yancheng
--   OFFLINE_RETAKEN wp2626   as above                                            Gushan falls and is taken back while it is away; the sweep skips it;
--                                                                                 the reconnect keeps it in Gushan ("evict not needed")
-- Console: add_virtual_player -profile_code wp2625 -nickname Login109      (or wp2626 for NOFACTION / OFFLINE_*)
-- A profile that is already connected from an earlier case has to be kicked first (STEP 3), because only a login runs the placement.
-- Steps (server_main):
--   1 SEED     before the virtual player exists: writes the storage the CASE needs
--   2 CHECK    after add_virtual_player: waits for the placement (about 1 s, up to 8 s) and asserts the expected place; for OFFLINE_* it does the whole scene
--   3 KICK     KickUser for the profile of CASE; the next CASE can add it again
--   4 CLEANUP  restores the storage name and deletes the isolated storage and the keys written for wp2625 / wp2626
-- Expected [VRF] lines (read with logs): see tests/README.md, "Disconnect and reconnect (#109)".
local CASE = "FRIENDLY"
local STEP = 1
local STORAGE = "CountryWarProbe109V1"
local CASES = {
    FRIENDLY = { profile = "wp2625", faction = "A", town = "zuoying", expected = "zuoying" },
    FALLEN = { profile = "wp2625", faction = "A", town = "zuoying", owners = { zuoying = "B" }, counts = { zuoying = 1 }, expected = "nanzih", remembered = "nanzih" },
    RETAKEN = { profile = "wp2625", faction = "A", town = "zuoying", counts = { zuoying = 2 }, expected = "zuoying" },
    NOFACTION = { profile = "wp2626", town = "zuoying", expected = "formationlobby" },
    NOTOWN = { profile = "wp2625", faction = "A", expected = "formationlobby" },
    OFFLINE_FALL = { profile = "wp2626", faction = "B" },
    OFFLINE_RETAKEN = { profile = "wp2626", faction = "B" },
}
local function await(predicate, tries) for _ = 1, tries or 100 do if predicate() then return true end wait(0.1) end return false end
local function find(profile)
    for _, user in ipairs(_UserService.UserEntities.Values) do
        if isvalid(user) and isvalid(user.PlayerComponent) and user.PlayerComponent.ProfileCode == profile then return user end
    end
    return nil
end
local function put(profile, key, expected, value)
    local saved = false
    _FormationStorage:Write(profile, key, expected, value, function(code) saved = code == 0 end)
    assert(await(function() return saved end), "wrote " .. key .. " for " .. profile)
end
local function wipe(profile)
    local storage = _DataStorageService:GetUserDataStorage(profile)
    storage:DeleteAndWait(_FactionWar.FactionKey)
    storage:DeleteAndWait(_FactionWar.TownKey)
end
local function board(case)
    local towns = _FactionWarTownDocument:InitialTowns()
    for id, owner in pairs(case.owners or {}) do towns[id].owner = owner end
    for id, count in pairs(case.counts or {}) do towns[id].e = count end
    return towns
end
local function store(towns)
    local saved = false
    _FactionWarTownDocument:WriteTowns(towns, function(ok) saved = ok end)
    assert(await(function() return saved end), "board stored")
end
local function readTown(profile)
    local result, done = nil, false
    _FactionWar:ReadTown(profile, function(town) result, done = town, true end)
    assert(await(function() return done end), "last town read")
    return result
end
local function reconnect(userId)
    local event = UserReconnectEvent()
    event.UserId = userId
    _UserService:SendEvent(event)
end
local ok, reason = pcall(function()
    local case = CASES[CASE]
    assert(case ~= nil, "unknown CASE " .. tostring(CASE))
    if STEP == 1 then
        assert(find(case.profile) == nil, case.profile .. " must not be connected yet: kick it (STEP 3) before seeding")
        _FactionWarTownDocument.TownStorageName = STORAGE
        wipe(case.profile)
        if case.faction ~= nil then put(case.profile, _FactionWar.FactionKey, "", case.faction) end
        if case.town ~= nil then put(case.profile, _FactionWar.TownKey, "", case.town) end
        store(board(case))
        log("[VRF][ReconnectLogin] " .. CASE .. " SEEDED; now: add_virtual_player -profile_code " .. case.profile .. " -nickname Login109, then STEP 2")
    elseif STEP == 2 then
        assert(_FactionWarTownDocument.TownStorageName == STORAGE, "STEP 1 swapped the storage name")
        local user = find(case.profile)
        assert(isvalid(user), case.profile .. " is connected")
        local userId = user.PlayerComponent.UserId
        if CASE == "OFFLINE_FALL" or CASE == "OFFLINE_RETAKEN" then
            -- The login itself must leave a player without a last town in the lobby; then the scene starts from Gushan.
            wait(6)
            assert(user.CurrentMapName == "formationlobby", "no last town: the login leaves them in the lobby")
            assert(_FactionWar:Move(user, "gushan") and await(function() return user.CurrentMapName == "gushan" end), "moved to Gushan")
            assert(await(function() return readTown(case.profile) == "gushan" end, 50), "Gushan is the last town")
            _MatchFlow:Depart(userId, "Probe")
            assert(_MatchFlow:IsOffline(userId), "offline, the entity stays in Gushan")
            local fallen = _FactionWarTownDocument:InitialTowns()
            fallen.gushan.owner = "A"
            fallen.gushan.e = 1
            store(fallen)
            _FactionWar:SweepFallen("gushan")
            wait(2)
            assert(user.CurrentMapName == "gushan", "the sweep leaves the disconnected player where they are")
            if CASE == "OFFLINE_RETAKEN" then
                local retaken = _FactionWarTownDocument:InitialTowns()
                retaken.gushan.e = 2
                store(retaken)
            end
            reconnect(userId)
            if CASE == "OFFLINE_FALL" then
                assert(await(function() return user.CurrentMapName == "yancheng" end, 150), "the reconnect judged Gushan fallen and sent the player to Yancheng")
            else
                wait(5)
                assert(user.CurrentMapName == "gushan", "Gushan was taken back: the reconnect keeps the player there")
            end
            log("[VRF][ReconnectLogin] " .. CASE .. " PASS")
            return
        end
        if case.expected == "formationlobby" then
            wait(8)
            assert(user.CurrentMapName == "formationlobby", "no faction or no last town: the player stays in the lobby, is in " .. user.CurrentMapName)
        else
            assert(await(function() return user.CurrentMapName == case.expected end, 120), "the login placed the player in " .. case.expected .. ", they are in " .. user.CurrentMapName)
            wait(2)
            assert(user.CurrentMapName == case.expected, "and the player stays there (one placement per login)")
        end
        assert(not _FactionWarAttack:IsEngaged(userId), "no ticket is held")
        assert(await(function() return not _FactionWarLanding:IsJudging(userId) end, 50), "the placement slot is free")
        if case.expected ~= "formationlobby" then
            assert(await(function() return readTown(case.profile) == (case.remembered or case.expected) end, 80), "the last town now is " .. (case.remembered or case.expected))
        end
        log("[VRF][ReconnectLogin] " .. CASE .. " PASS")
    elseif STEP == 3 then
        local user = find(case.profile)
        assert(isvalid(user), case.profile .. " is connected")
        _UserService:KickUser(user.PlayerComponent.UserId, KickReason.ETC)
        assert(await(function() return find(case.profile) == nil end, 100), "the entity left")
        log("[VRF][ReconnectLogin] kicked " .. case.profile)
    elseif STEP == 4 then
        _FactionWarTownDocument.TownStorageName = "CountryWarV1"
        _DataStorageService:DeleteGlobalDataStorageAndWait(STORAGE)
        wipe("wp2625")
        wipe("wp2626")
        log("[VRF][ReconnectLogin] CLEANUP storage name restored, isolated board and keys deleted")
    end
end)
if not ok then log_error("[VRF][ReconnectLogin] " .. tostring(CASE) .. " STEP " .. tostring(STEP) .. " FAIL " .. tostring(reason)) end
