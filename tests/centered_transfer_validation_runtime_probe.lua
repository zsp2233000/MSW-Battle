-- server_main with the dedicated hf2601 fixture. Corruption is injected only at the storage seam.
local ok, detail = pcall(function()
    local player
    for _, user in ipairs(_UserService.UserEntities.Values) do
        if user.PlayerComponent.ProfileCode == 'hf2601' then player = user break end
    end
    assert(isvalid(player), 'requires the dedicated virtual player')
    local userId, profile = player.PlayerComponent.UserId, player.PlayerComponent.ProfileCode
    local ticket = _FormationHandoff:Read(profile)
    assert(ticket ~= nil, 'fixture ticket read')
    ticket.data = {schema=1,profile=profile,attempt=_UtilLogic:NewGuid(),requestId=_UtilLogic:NewGuid(),source=_WorldInstanceService.WorldInstanceId,adapter='local',state='QUEUED',started=DateTime.UtcNow.Elapsed,expires=0,matchKey=''}
    assert(_FormationHandoff:Reserve(userId, ticket), 'fixture reserved')
    local storage = _DataStorageService:GetUserDataStorage(profile)
    local code, baseline = storage:GetAndWait(_FormationHandoff.StorageKey)
    assert(code == 0, 'fixture captured at external storage seam')
    local function write(raw)
        local readCode, current = storage:GetAndWait(_FormationHandoff.StorageKey)
        assert(readCode == 0, 'fixture current bytes')
        local done, result = false, -1
        _FormationStorage:Write(profile, _FormationHandoff.StorageKey, current, raw, function(value) result, done = value, true end)
        for attempt = 1, 200 do if done then break end wait(0.05) end
        assert(done and result == 0, 'fixture boundary write confirmed')
    end
    local tested, reason = pcall(function()
        for _, kind in ipairs({'coordinate', 'saved', 'fixed', 'draft'}) do
            local data = _HttpService:JSONDecode(baseline)
            if kind == 'coordinate' then data.transfer.coordinateSchema = 1 end
            if kind == 'saved' then data.transfer.saved = string.gsub(data.transfer.saved, '"schema":2', '"schema":1', 1) end
            if kind == 'fixed' then data.transfer.fixed = 'invalid-json' end
            if kind == 'draft' then
                local drafts = _HttpService:JSONDecode(data.transfer.drafts)
                drafts['1'].version = 'invalid'
                data.transfer.drafts = _HttpService:JSONEncode(drafts)
            end
            write(_HttpService:JSONEncode(data))
            local invalid = _FormationHandoff:Read(profile)
            if kind == 'coordinate' then
                assert(invalid == nil, 'old coordinate schema rejected')
            else
                assert(invalid ~= nil and _FormationHandoff:Roster(invalid.id) == nil, 'corrupt handoff cannot admit a roster')
                invalid.data.state = 'RETURNING'
                assert(_FormationHandoff:Store(invalid), 'return fixture persisted')
                local session = _FormationService:GetSession(userId)
                local version = session.drafts[tostring(session.editSlot)].version
                assert(not _FormationHandoff:Restore(userId, invalid.id), 'corrupt handoff cannot restore')
                assert(session.drafts[tostring(session.editSlot)].version == version, 'rejected restore is atomic')
            end
            write(baseline)
        end
    end)
    write(baseline)
    ticket = _FormationHandoff:Read(profile)
    assert(ticket ~= nil and _FormationHandoff:Close(userId, ticket, 'CANCELLED'), 'fixture cleaned')
    assert(tested, tostring(reason))

    local session = _FormationService:GetSession(userId)
    local slot = session.editSlot
    local version = session.drafts[tostring(slot)].version
    local tiles = _EntityService:GetEntityByPath('/maps/template/RectTileMap').RectTileMapComponent
    local original = tiles:ToCellPosition(Vector3(-2.25,0.25,0))
    local mirror = tiles:ToCellPosition(Vector3(_FormationMapLayout:MirrorX(-2.25),0.25,0))
    local originalName, mirrorName = tiles:GetTile(original).Name, tiles:GetTile(mirror).Name
    local function reject(label)
        _FormationService:UpdateDraftForUser(userId, {{monsterId='monster_tank',x=-2.25,y=0.25}}, version, slot)
        assert(session.drafts[tostring(slot)].version == version, label)
    end
    tested, reason = pcall(function()
        tiles:RemoveTile(original)
        reject('missing original rejected')
        tiles:SetTile(originalName, original)
        tiles:RemoveTile(mirror)
        reject('missing mirror rejected')
        tiles:SetTile('Baram_10048', mirror)
        reject('mirror wall rejected')
    end)
    tiles:SetTile(originalName, original)
    tiles:SetTile(mirrorName, mirror)
    assert(tested, tostring(reason))
    log('[VRF][CenteredTransfer] PASS old schemas and corrupt handoffs rejected atomically; native terrain restored')
end)
if not ok then log('[VRF][CenteredTransfer] FAIL '..tostring(detail)) end
