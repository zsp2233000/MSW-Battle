-- server_main after adding dedicated virtual players with profile codes hf2601 and hf2602.
local ok, detail = pcall(function()
    for attempt = 1, 450 do
        local joined = 0
        for _, player in ipairs(_UserService.UserEntities.Values) do
            if player.PlayerComponent.ProfileCode == 'hf2601' or player.PlayerComponent.ProfileCode == 'hf2602' then joined = joined + 1 end
        end
        if joined == 2 then break end
        wait(0.1)
    end
    local count = 0
    for _, player in ipairs(_UserService.UserEntities.Values) do
        local profile = player.PlayerComponent.ProfileCode
        if profile == 'hf2601' or profile == 'hf2602' then
            local userId = player.PlayerComponent.UserId
            local session = _FormationService:GetSession(userId)
            if not session.initialized or (session.loadState ~= 'READY' and session.loadState ~= 'NEW') then _FormationService:Load(session) end
            for attempt = 1, 200 do if session.initialized and not session.pending then break end wait(0.1) end
            assert(session.initialized and not session.pending, 'fixture loaded')
            _FormationService:UpdateDraftForUser(userId, {{monsterId='monster_tank',x=-3.25,y=-1.25}}, session.drafts[tostring(session.editSlot)].version, session.editSlot)
            _FormationService:SaveForUser(userId, session.drafts[tostring(session.editSlot)].version, session.editSlot)
            for attempt = 1, 200 do if not session.pending then break end wait(0.1) end
            assert(session.drafts[tostring(session.editSlot)].saveState == 'SAVED', 'fixture save confirmed')
            _FormationService:ActivateForUser(userId, session.editSlot, session.saved.slots[tostring(session.editSlot)].revision)
            for attempt = 1, 200 do if not session.pending then break end wait(0.1) end
            assert(session.saved.activeSlot == session.editSlot, 'fixture saved formation activated')
            count = count + 1
        end
    end
    assert(count > 0, 'dedicated fixture player joined')
    log('[VRF][HandoffFixture] ready players='..tostring(count))
end)
if not ok then log('[VRF][HandoffFixture] FAIL '..tostring(detail)) end
