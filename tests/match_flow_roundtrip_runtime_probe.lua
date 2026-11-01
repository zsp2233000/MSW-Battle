-- server_main after Flow52 PREPARE and the real client's confirmed queue. Requires the hf2602 virtual peer.
-- FormationService.StorageKey must be isolated; use the same handoff key in every room (the default).
-- Start matching with the real client's lobby button, then queue the peer below. This coroutine keeps
-- detached expectations while the client result probe drives return. Return the peer from its room too.
local function await(predicate, tries)
    for _ = 1, tries or 200 do if predicate() then return true end wait(0.1) end
    return false
end
local ok, detail = pcall(function()
    assert(string.sub(_FormationService.StorageKey, 1, 7) == 'Issue52', 'isolated formation fixture required')
    local peer, owner
    for _, player in ipairs(_UserService.UserEntities.Values) do
        if player.PlayerComponent.ProfileCode == 'hf2602' then peer = player else owner = player end
    end
    assert(isvalid(owner) and isvalid(peer), 'one real client and one virtual peer')
    local peerId, ownerId = peer.PlayerComponent.UserId, owner.PlayerComponent.UserId
    local session = _FormationService:GetSession(peerId)
    _FormationService:Load(session)
    assert(await(function() return session.initialized and not session.pending and (session.loadState == 'READY' or session.loadState == 'NEW') end), 'peer loaded isolated key')
    local slotId = session.editSlot
    _FormationService:SaveForUser(peerId, {{monsterId='monster_tank',x=-3.25,y=-1.25}}, slotId,
        session.saved.slots[tostring(slotId)].revision, _UtilLogic:NewGuid())
    assert(await(function() return not session.pending and #session.saved.slots[tostring(slotId)].units == 1 end), 'peer saved')
    _FormationService:ActivateForUser(peerId, slotId, session.saved.slots[tostring(slotId)].revision)
    assert(await(function() return not session.pending and session.saved.activeSlot == slotId end), 'peer activated')
    local expected = {}
    for _, id in ipairs({ownerId, peerId}) do
        local s = _FormationService:GetSession(id)
        expected[id] = { saved = _FormationSchema:CopyDocument(s.saved), editSlot = s.editSlot }
    end
    local own = _FormationService:GetSession(ownerId)
    assert(own.saved.activeSlot == 3 and own.saved.slots['3'].revision == 2, 'updated third group is active')
    for index = 1, 5 do assert(#own.saved.slots[tostring(index)].units > 0, 'five saved groups before battle') end
    assert(_MatchProbe:IsFormationLocked(ownerId), 'real client started matching')
    local ticket = _FormationHandoff:Read(owner.PlayerComponent.ProfileCode)
    assert(ticket ~= nil and ticket.data.state == 'QUEUED', 'queue reservation confirmed')
    local fixed = _FormationHandoff:Roster(ticket.id)
    assert(fixed ~= nil and #fixed == 1 and fixed[1].x == -7 and fixed[1].y == 1, 'updated active version is fixed for this match')
    local done, code, raw = false, -1, nil
    _FormationStorage:Read(owner.PlayerComponent.ProfileCode, _FormationHandoff.StorageKey, function(result, key, value)
        code, raw, done = result, value, true
    end)
    assert(await(function() return done end) and code == 0, 'durable handoff read')
    local transfer = _HttpService:JSONDecode(raw).transfer
    assert(transfer.drafts == nil and transfer.draft == nil, 'DB handoff contains no unsaved content')
    local saved = transfer.saved
    transfer.drafts = { ['3'] = {{monsterId='monster_tank',x=-1,y=0}} }
    local legacy = _FormationHandoff:DecodeTransfer(transfer, _FormationService:GetCatalog())
    assert(legacy ~= nil and _FormationSchema:EncodeDocument(legacy.document) == saved and legacy.units[1].x == -7, 'legacy unsaved content is ignored')
    _MatchProbe:QueueForUser(peerId)
    log('[VRF][Flow52Roundtrip] ENTERING fixed slot=3 revision=2; confirmed-only DB; legacy content ignored')
    for _, id in ipairs({ownerId, peerId}) do
        assert(await(function() return not isvalid(_UserService:GetUserEntityByUserId(id)) end), 'participant left main room')
    end
    for _, id in ipairs({ownerId, peerId}) do
        assert(await(function()
            local p = _UserService:GetUserEntityByUserId(id)
            if not isvalid(p) or p.CurrentMapName ~= 'formationlobby' or _MatchProbe:IsFormationLocked(id) then return false end
            local s = _FormationService:GetSession(id)
            return s.initialized and not s.pending and (s.loadState == 'READY' or s.loadState == 'NEW')
        end, 1800), 'participant returned and restoration confirmed')
        local restored = _FormationService:GetSession(id)
        local before, after = expected[id].saved, restored.saved
        assert(before.activeSlot == after.activeSlot and before.revision == after.revision and before.writeId == after.writeId, 'active choice and document version retained; no automatic formation save')
        for index = 1, 5 do
            local key = tostring(index)
            assert(before.slots[key].revision == after.slots[key].revision and _FormationSchema:SameUnits(before.slots[key].units, after.slots[key].units), 'all five saved groups and revisions retained')
        end
        assert(restored.editSlot == expected[id].editSlot and restored.drafts == nil, 'preview selection retained without unsaved content')
    end
    log('[VRF][Flow52Roundtrip] PASS five groups; active/version retained; no automatic save; confirmed handoff; both returned')
end)
if not ok then log('[VRF][Flow52Roundtrip] FAIL ' .. tostring(detail)) end
