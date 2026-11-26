-- Maker end-to-end for #122 / ADR 0017: the side that was not in the room when the result settled gets the 上一場戰果 / 上一場對戰結果 window.
-- Two virtual players, added in a fresh Play (one Play per MODE):
--   add_virtual_player -profile_code wp2601 -nickname AbsentRA     (A, RED, Zuoying, 3 tanks, on time; in LOBBY mode both are in the lobby)
--   add_virtual_player -profile_code wp2602 -nickname AbsentRB     (B, BLUE, Gushan, 1 tank, never enters the room)
-- Set B_PROFILE to the ProfileCode of the real Maker client to read the window on a real screen (STEP 5 and 6, client); the real client then plays B
-- with an isolated formation key and "wp2602" is not needed. MODE is edited by substitution before dispatch:
--   ONLINE   B stays online in Gushan: when the room settles B's ticket ends at once (not at expiry), B lands in his own town and the window is pushed.
--   RELOGIN  B leaves before the fight is over (KickUser) and logs in again with a NEW user id (add_virtual_player again after STEP 3, then STEP 4):
--            the window is delivered at that login and the old ticket is ended by it.
--   LOBBY    a lobby match (no towns): the record has no war block and the title is 上一場對戰結果.
-- Steps (server_main unless it says otherwise):
--   1 SETUP    prepares both players (about 40 s, "SETUP PASS").
--   2 QUEUE    arms B's absence, queues both ("QUEUED room key="). RELOGIN: kicks B right after the fight began ("KICKED").
--   3 SETTLED  waits (up to 4 minutes) for the settled match, then checks the record, the delivery (ONLINE / LOBBY) and A's missing record ("SETTLED PASS").
--   4 LOGIN    RELOGIN only, after the new virtual player appeared: the ticket ended at login, the window delivered ("LOGIN PASS").
--   5 CLIENT   (client, real client as B) the visible window: title, result, rows, button ("CLIENT PASS").
--   6 CONFIRM  (client) presses 確定 through the production handler; the window closes ("CONFIRM PASS").
--   7 CLEARED  the record is cleared and stays cleared ("CLEARED PASS").
--   8 CLEANUP  disarms the fault, clears the records, returns anybody who still holds a ticket and deletes the town storage.
local STEP = 1
local MODE = "ONLINE"
local B_PROFILE = "wp2602"
local ROOM_KEY = "SET_ME"
local function await(predicate, tries) for _ = 1, tries or 300 do if predicate() then return true end wait(0.1) end return false end
local function find()
    local found = {}
    for _, user in ipairs(_UserService.UserEntities.Values) do found[user.PlayerComponent.ProfileCode] = user end
    return found["wp2601"], found[B_PROFILE]
end
local war = MODE ~= "LOBBY"
local ok, reason = pcall(function()
    local a, b = find()
    if STEP == 1 then
        assert(isvalid(a) and isvalid(b), "both players connected")
        if B_PROFILE ~= "wp2602" then _FormationService.StorageKey = "Absent122_" .. _UtilLogic:NewGuid() end
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
        -- A record left by an earlier run would be mistaken for this match's.
        for _, user in ipairs({ a, b }) do
            local profile = user.PlayerComponent.ProfileCode
            local old = _AbsentResult:PendingFor(profile)
            if old ~= nil then
                local cleared = false
                _AbsentResult:Clear(profile, old.id, function() cleared = true end)
                await(function() return cleared end, 100)
            end
        end
        if war then
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
        else
            for _, user in ipairs({ a, b }) do
                if user.CurrentMapName ~= "formationlobby" then _TeleportService:TeleportToMapPosition(user, Vector3(0, 0, 0), "formationlobby") end
            end
            assert(await(function()
                a, b = find()
                return isvalid(a) and isvalid(b) and a.CurrentMapName == "formationlobby" and b.CurrentMapName == "formationlobby"
            end, 300), "players in the lobby")
        end
        log("[VRF][AbsentResultE2E] SETUP PASS mode=" .. MODE)
    elseif STEP == 2 then
        assert(isvalid(a) and isvalid(b), "both players connected")
        local idA, idB = a.PlayerComponent.UserId, b.PlayerComponent.UserId
        _MatchFaults:ConfigureAbsent(idB, true)
        if war then
            _FactionWarAttack:AttackFor(idA, "gushan")
            assert(await(function() return _FactionWarAttack:IsEngaged(idA) end, 100), "A engaged")
            _FactionWarAttack:AttackFor(idB, "zuoying")
        else
            _MatchFlow:QueueForUser(idA)
            _MatchFlow:QueueForUser(idB)
        end
        local key = nil
        assert(await(function()
            for matchKey, slot in pairs(_MatchFlow._T.rooms) do
                if not slot.creating and slot.room ~= nil then key = matchKey end
            end
            return key ~= nil
        end, 300), "the match room is created")
        log("[VRF][AbsentResultE2E] QUEUED room key=" .. key .. " mode=" .. MODE)
        if MODE == "RELOGIN" then
            -- The fight is on (the absent side's roster is fielded after the entry time); B leaves for good before it ends.
            wait(36)
            _UserService:KickUser(idB, KickReason.ETC)
            assert(await(function() local _, now = find() return not isvalid(now) end, 100), "B left")
            log("[VRF][AbsentResultE2E] KICKED room key=" .. key .. "; now add_virtual_player -profile_code " .. B_PROFILE .. " -nickname AbsentRB after STEP 3")
        end
    elseif STEP == 3 then
        local towns = nil
        local function settled()
            local read = false
            _FactionWarTownDocument:Read(function(result) towns, read = result, true end)
            await(function() return read end, 50)
            return war and towns ~= nil and #(towns.settled or {}) >= 1
        end
        local profileA, profileB = "wp2601", B_PROFILE
        if war then
            assert(await(settled, 2400), "the match settled")
        else
            -- A lobby match leaves no town record: the absent side's record itself is the sign that the room settled.
            assert(await(function() return _AbsentResult:PendingFor(profileB) ~= nil end, 2400), "the lobby match settled")
        end
        assert(await(function() return _AbsentResult:PendingFor(profileB) ~= nil end, 100), "B's absent result is written")
        local record = _AbsentResult:PendingFor(profileB)
        assert(record.result == "LOSE" and record.kind == (war and "WAR" or "LOBBY"), "B lost; kind " .. tostring(record.kind))
        if war then
            assert(record.war.origin == "gushan" and record.war.target == "zuoying" and record.war.status == "SAVED", "the war block is B's own: Gushan attacked Zuoying")
            assert(record.war.originBefore == 100 and record.war.originAfter == 80 and record.war.targetBefore == 100 and record.war.targetAfter == 100, "Gushan 100 -> 80, Zuoying unchanged")
            assert(towns.gushan.strength == 80 and #(towns.settled or {}) == 1, "settled once")
        else
            assert(record.war == nil, "a lobby result has no war block")
        end
        assert(_AbsentResult:PendingFor(profileA) == nil, "A saw the result page: nothing is owed to A")
        local view = _AbsentResult:Present(record)
        log("[VRF][AbsentResultE2E] window title=" .. view.title .. " result=" .. view.resultText .. " rows=" .. tostring(#view.rows) .. " conclusion=" .. view.conclusion)
        assert(view.title == (war and "上一場戰果" or "上一場對戰結果"), "the window title")
        if MODE == "RELOGIN" then
            local _, now = find()
            assert(not isvalid(now), "B is still offline")
            log("[VRF][AbsentResultE2E] SETTLED PASS record waits for B's next login match=" .. record.id)
        else
            assert(isvalid(b), "B is online")
            local idB = b.PlayerComponent.UserId
            assert(await(function() return _AbsentResult._T.delivered[idB] == record.id end, 150), "the window was delivered to the online player")
            assert(await(function() return _MatchFlow:StateForUser(idB) == "IDLE" and not _FormationHandoff:IsLockedForUser(idB) end, 150), "B's ticket ended at once and is unlocked")
            assert(await(function()
                local _, now = find()
                return isvalid(now) and now.CurrentMapName == (war and "gushan" or "formationlobby")
            end, 150), "B stands in his own town / the lobby")
            log("[VRF][AbsentResultE2E] SETTLED PASS delivered to the online player and the ticket ended match=" .. record.id)
        end
    elseif STEP == 4 then
        assert(MODE == "RELOGIN", "only RELOGIN logs in again")
        assert(isvalid(b), "the new virtual player appeared")
        local idB = b.PlayerComponent.UserId
        local record = _AbsentResult:PendingFor(B_PROFILE)
        assert(record ~= nil, "the record is still waiting")
        assert(await(function() return _AbsentResult._T.delivered[idB] == record.id end, 300), "the window was delivered at the login")
        assert(await(function() return _MatchFlow:StateForUser(idB) == "IDLE" and not _FormationHandoff:IsLockedForUser(idB) end, 300), "the old ticket ended at the login and is unlocked")
        assert(await(function() return b.CurrentMapName == "gushan" end, 300), "B stands in Gushan")
        log("[VRF][AbsentResultE2E] LOGIN PASS the login ended the ticket and delivered the window match=" .. record.id)
    elseif STEP == 5 then
        local player = _UserService.LocalPlayer
        assert(player.PlayerComponent.ProfileCode == B_PROFILE, "the real client is B")
        local popup = _EntityService:GetEntityByPath("/ui/AbsentResultGroup/Popup")
        assert(await(function() return isvalid(popup) and popup.Enable end, 600), "the window is shown")
        local function text(path) return _EntityService:GetEntityByPath("/ui/AbsentResultGroup/Popup/Window/" .. path).TextGUIRendererComponent.Text end
        local title, result = text("Title"), text("Result")
        assert(title == (war and "上一場戰果" or "上一場對戰結果") and result == "失敗", "title and result: " .. title .. " / " .. result)
        local origin = _EntityService:GetEntityByPath("/ui/AbsentResultGroup/Popup/Window/War")
        assert(origin.Enable == war, "the war block shows for a war result only")
        if war then
            assert(string.find(text("War/Origin"), "鼓山", 1, true) and string.find(text("War/Origin"), "100 → 80", 1, true), "origin row: " .. text("War/Origin"))
            assert(string.find(text("War/Target"), "左營", 1, true) and string.find(text("War/Conclusion"), "未易主", 1, true), "target row and conclusion")
            assert(string.find(text("War/Origin"), _FactionWarUI.TownNameHighlightHex, 1, true), "the town name is highlighted")
        end
        for _, word in ipairs({ "經驗", "exp" }) do assert(not string.find(title .. result .. text("War/Conclusion"), word, 1, true), "no experience in the window") end
        log("[VRF][AbsentResultE2E] CLIENT PASS title=" .. title .. " result=" .. result)
    elseif STEP == 6 then
        local popup = _EntityService:GetEntityByPath("/ui/AbsentResultGroup/Popup")
        assert(isvalid(popup) and popup.Enable, "the window is shown")
        -- maker_mouse_input cannot press engine UI buttons, so the production click handler runs directly.
        _AbsentResultUI:Confirm()
        assert(await(function() return not popup.Enable end, 50), "the window closed")
        log("[VRF][AbsentResultE2E] CONFIRM PASS")
    elseif STEP == 7 then
        assert(await(function() return _AbsentResult:PendingFor(B_PROFILE) == nil end, 100), "the record is cleared")
        local _, now = find()
        if isvalid(now) then
            _AbsentResult:Deliver(now.PlayerComponent.UserId, false)
            wait(1)
            assert(_AbsentResult:PendingFor(B_PROFILE) == nil, "and is not shown again")
        end
        log("[VRF][AbsentResultE2E] CLEARED PASS")
    elseif STEP == 8 then
        _MatchFaults:Remove()
        for _, profile in ipairs({ "wp2601", B_PROFILE }) do
            local cleared = false
            local record = _AbsentResult:PendingFor(profile)
            if record ~= nil then _AbsentResult:Clear(profile, record.id, function() cleared = true end) await(function() return cleared end, 100) end
        end
        for _, user in ipairs({ a, b }) do
            if isvalid(user) then _MatchFlow:ReturnForUser(user.PlayerComponent.UserId) end
        end
        if war then
            local code = _DataStorageService:DeleteGlobalDataStorageAndWait(_FactionWarTownDocument.TownStorageName)
            log("[VRF][AbsentResultE2E] CLEANUP town storage deleted code=" .. tostring(code))
        end
        log("[VRF][AbsentResultE2E] CLEANUP PASS")
    end
end)
if not ok then log_error("[VRF][AbsentResultE2E] STEP " .. tostring(STEP) .. " FAIL " .. tostring(reason)) end
