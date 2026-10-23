-- Maker server_main, with two connected players. Uses the same server commands as the real RPCs.
local ok, detail = pcall(function()
    local users = _UserService.UserEntities.Values
    assert(#users == 2, "requires two connected Maker players")
    local first, second = users[1], users[2]
    local firstId, secondId = first.PlayerComponent.UserId, second.PlayerComponent.UserId
    local firstProfile, secondProfile = first.PlayerComponent.ProfileCode, second.PlayerComponent.ProfileCode
    for _, userId in ipairs({firstId, secondId}) do
        local record = _FormationService:GetSession(userId)
        if not record.initialized then _FormationService:Load(record) end
        for attempt = 1, 200 do
            if record.initialized and not record.pending then break end
            wait(0.1)
        end
        assert(record.initialized and not record.pending, "formation data loaded")
    end
    local setup = function(userId, units)
        local record = _FormationService:GetSession(userId)
        local slotId = record.editSlot
        _FormationService:UpdateDraftForUser(userId, units, record.drafts[tostring(slotId)].version, slotId)
        _FormationService:SaveForUser(userId, record.drafts[tostring(slotId)].version, slotId)
        for attempt = 1, 200 do if not record.pending then break end wait(0.1) end
        assert(record.drafts[tostring(slotId)].saveState == "SAVED", "save confirmed")
        _FormationService:ActivateForUser(userId, slotId, record.saved.slots[tostring(slotId)].revision)
        for attempt = 1, 200 do if not record.pending then break end wait(0.1) end
        assert(record.saved.activeSlot == slotId, "saved slot activated")
    end
    local six = {}
    for index = 1, 6 do six[index] = {monsterId = "monster_tank", x = -3.25 - (index - 1) * 0.75, y = -1.25} end
    local one = {{monsterId = "monster_tank", x = -3.25, y = -1.25}}
    setup(firstId, six)
    setup(secondId, one)
    _MatchProbe:QueueForUser(firstId)
    _MatchProbe:CancelForUser(firstId)
    _MatchProbe:QueueForUser(firstId)
    -- Change and save the active formation AFTER queuing. This must affect only a future match.
    setup(firstId, one)
    local nextMatch = _HttpService:JSONDecode(_FormationService:ExportTransfer(firstId).fixed)
    assert(#nextMatch == 1, "later saved formation has one unit")
    local expected = {}
    for _, userId in ipairs({firstId, secondId}) do
        expected[userId] = _FormationService:ExportTransfer(userId)
    end
    log("[VRF][MatchedQueue] queued six; later confirmed save one; cancel/requeue passed")
    _MatchProbe:QueueForUser(secondId)
    log("[VRF][MatchedQueue] PASS firstProfile=" .. firstProfile .. " secondProfile=" .. secondProfile)
    -- Keep detached expectations in this coroutine while the room probe drives battle and return.
    wait(0.2)
    for _, userId in ipairs({firstId, secondId}) do
        local restored
        for attempt = 1, 900 do
            local player = _UserService:GetUserEntityByUserId(userId)
            if isvalid(player) and player.CurrentMapName == "formationlobby" then
                restored = _FormationService:ExportTransfer(userId)
                if restored ~= nil then break end
            end
            wait(0.1)
        end
        assert(restored ~= nil, "returned formation data available")
        local before = _HttpService:JSONDecode(expected[userId].saved)
        local after = _HttpService:JSONDecode(restored.saved)
        assert(before.activeSlot == after.activeSlot and before.revision == after.revision, "active selection and save revision retained")
        for index = 1, 5 do
            local key = tostring(index)
            assert(before.slots[key].revision == after.slots[key].revision, "slot revision retained")
            assert(_FormationSchema:SameUnits(before.slots[key].units, after.slots[key].units), "all five saved formations retained")
        end
        assert(restored.editSlot == expected[userId].editSlot, "editor selection retained")
        local beforeDrafts = _HttpService:JSONDecode(expected[userId].drafts)
        local afterDrafts = _HttpService:JSONDecode(restored.drafts)
        for index = 1, 5 do
            local key = tostring(index)
            assert(_FormationSchema:SameUnits(_HttpService:JSONDecode(beforeDrafts[key].units), _HttpService:JSONDecode(afterDrafts[key].units)), "all five login drafts retained")
        end
    end
    log("[VRF][MatchedPreservation] PASS five saved slots, active selection, draft contents and editor selection")
end)
if not ok then log("[VRF][MatchedQueue] FAIL " .. tostring(detail)) end
