-- Maker server_main: queue two existing saved formations without modifying player data.
local ok, detail = pcall(function()
    local users = _UserService.UserEntities.Values
    assert(#users == 2, "requires two connected Maker players")
    for _, user in ipairs(users) do
        assert(user.CurrentMap.Name == "formationlobby" or user.CurrentMap.Name == "formationsim", "return to preparation first")
        local record = _FormationService:GetSession(user.PlayerComponent.UserId)
        assert(record.initialized and not record.pending, "formation must be loaded and idle")
        local slot = record.saved.slots[tostring(record.saved.activeSlot)]
        assert(slot ~= nil and #slot.units == 6, "save and activate a six-unit formation first")
        for _, draft in pairs(record.drafts) do
            assert((#draft.units == 0 and draft.saveState == "UNSAVED") or draft.version == draft.savedVersion, "save drafts before running the queue probe")
        end
    end
    for _, user in ipairs(users) do _MatchProbe:QueueForUser(user.PlayerComponent.UserId) end
    log("[VRF][BattleView] SETUP_DISPATCHED verify admission and RESULT_PASS in the matched instance")
end)
if not ok then log("[VRF][BattleView] SETUP_FAIL " .. tostring(detail)) end
