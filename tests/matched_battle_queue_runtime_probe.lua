-- Maker server_main, with two connected players. Uses the same server commands as the real RPCs.
local ok, detail = pcall(function()
    local users = _UserService.UserEntities.Values
    local dedicated = {}
    for _, user in ipairs(users) do
        if user.PlayerComponent.ProfileCode == 'hf2601' or user.PlayerComponent.ProfileCode == 'hf2602' then table.insert(dedicated, user) end
    end
    if #dedicated == 2 then users = dedicated end
    assert(#users == 2, "requires two connected Maker players")
    local first, second = users[1], users[2]
    local firstId, secondId = first.PlayerComponent.UserId, second.PlayerComponent.UserId
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
    local nextSession = _FormationService:GetSession(firstId)
    local nextMatch = nextSession.saved.slots[tostring(nextSession.saved.activeSlot)].units
    assert(#nextMatch == 1, "later saved formation has one unit")
    local expected = {}
    for _, userId in ipairs({firstId, secondId}) do
        local session = _FormationService:GetSession(userId)
        local drafts = {}
        for index = 1, 5 do drafts[tostring(index)] = _FormationSchema:CopyUnits(session.drafts[tostring(index)].units) end
        expected[userId] = { saved = _FormationSchema:CopyDocument(session.saved), editSlot = session.editSlot, drafts = drafts, player = _UserService:GetUserEntityByUserId(userId) }
    end
    log("[VRF][MatchedQueue] queued six; later confirmed save one; cancel/requeue passed")
    _MatchProbe:QueueForUser(secondId)
    log("[VRF][MatchedQueue] PASS participants=2")
    -- Keep detached expectations in this coroutine while the room probe drives battle and return.
    wait(0.2)
    for _, userId in ipairs({firstId, secondId}) do
        local restored
        for attempt = 1, 900 do
            local player = _UserService:GetUserEntityByUserId(userId)
            if isvalid(player) and player.CurrentMapName == "formationlobby" then
                restored = _FormationService:GetSession(userId)
                if restored ~= nil and restored.initialized then break end
            end
            wait(0.1)
        end
        assert(restored ~= nil and restored.initialized, "returned formation data available")
        local restoredSessionId = restored.sessionId
        _FormationService:HandleEntityDestroyEvent(EntityDestroyEvent(expected[userId].player))
        local afterOldDestroy = _FormationService:GetSession(userId)
        assert(afterOldDestroy ~= nil and afterOldDestroy.initialized and afterOldDestroy.sessionId == restoredSessionId, "old entity destruction cannot remove the returned session")
        local before = expected[userId].saved
        local after = restored.saved
        assert(before.activeSlot == after.activeSlot and before.revision == after.revision, "active selection and save revision retained")
        for index = 1, 5 do
            local key = tostring(index)
            assert(before.slots[key].revision == after.slots[key].revision, "slot revision retained")
            assert(_FormationSchema:SameUnits(before.slots[key].units, after.slots[key].units), "all five saved formations retained")
        end
        assert(restored.editSlot == expected[userId].editSlot, "editor selection retained")
        local beforeDrafts = expected[userId].drafts
        local afterDrafts = restored.drafts
        for index = 1, 5 do
            local key = tostring(index)
            assert(_FormationSchema:SameUnits(beforeDrafts[key], afterDrafts[key].units), "all five login drafts retained")
        end
    end
    log("[VRF][MatchedPreservation] PASS five saved slots, active selection, draft contents and editor selection")
end)
if not ok then log("[VRF][MatchedQueue] FAIL " .. tostring(detail)) end
