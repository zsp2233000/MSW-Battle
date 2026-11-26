-- Run from faction_war_town_document_local.cjs. Stand-ins for the room transport and async storage.
local function exercise(kind)
    local match = { _T = {} }
    setmetatable(match, { __index = matchedBattle })
    local guard, war = kind == "GUARD", kind ~= "LOBBY"
    local battle = { Phase = "WAITING", MatchKey = "test-match" }
    local map = { GetComponent = function(_, name) assert(name == "script.BattleSession"); return battle end }
    match.Entity = { CurrentMap = map }
    local function player(id, profile, currentMap)
        return { CurrentMap = currentMap, PlayerComponent = { UserId = id, ProfileCode = profile } }
    end
    local red, blue = player("red-user", "red-profile", map), player("blue-user", "blue-profile", map)
    local outsider, elsewhere = player("outsider", "other-profile", map), player("elsewhere", "red-profile", {})
    local users = { red, blue, outsider, elsewhere }
    local packets, settleCount, settled = {}, 0, nil
    local offline, board = {}, doc:InitialTowns()
    board.gushan.strength = 25
    isvalid = function(value) return value ~= nil end
    _UserService = { UserEntities = { Values = users }, GetUserEntityByUserId = function(_, id)
        for _, user in ipairs(users) do if user.PlayerComponent.UserId == id then return user end end
    end }
    _MatchFlow = {
        RoomBattleAdmission = function() return {
            key = battle.MatchKey, home = "red-profile", away = guard and "guard:gushan" or "blue-profile", guard = guard,
            homeTown = war and "zuoying" or "", awayTown = war and "gushan" or ""
        } end,
        PublishState = function() end,
        Player = function(_, userId)
            for _, user in ipairs(users) do
                if user.PlayerComponent.UserId == userId and not offline[userId] then return user end
            end
        end
    }
    _RoomService = { RoomKey = battle.MatchKey }
    _FormationHandoff = { Roster = function() return {} end }
    _FactionWarGuard = { Roster = function() return {} end, IsGuardProfile = function(_, profile) return string.sub(profile, 1, 6) == "guard:" end }
    _AbsentResult = { Compose = function() return {} end, Write = function() error("everyone saw the result page: nothing is owed") end,
        Announce = function() error("nobody to announce") end, Clear = function() end }
    _FactionWar = { ReadFaction = function(_, profile, complete) complete(profile == "red-profile" and "RED" or "BLUE") end }
    _FactionWarAttack = { Settle = function(_, key, home, away, result, battleKind, complete)
        settleCount = settleCount + 1
        settled = function()
            local save = doc:Apply(board, { matchKey = key, home = home, away = away, result = result, kind = battleKind })
            board = save.document
            complete(save.outcome.status, save.detail, save.outcome)
        end
    end }
    local read = doc.Read
    doc.Read = function(_, complete) complete(board) end
    function battle:InitializeMatchedBattle(key, home, away)
        self.HomeProfile, self.AwayProfile, self.Phase = home, away, "BATTLE"
        return true
    end
    function battle:ParticipantSide(profile)
        return profile == self.HomeProfile and "PLAYER" or (profile == self.AwayProfile and "ENEMY" or "")
    end
    function battle:ResultForProfile(profile)
        return profile == self.HomeProfile and "WIN" or (profile == self.AwayProfile and "LOSE" or "")
    end
    function match:ReceiveWarResultReceipt(receipt, userId)
        assert(userId == "red-user" or (not guard and userId == "blue-user"), "receipt leaked to a nonparticipant")
        assert(receipt.profile == (userId == "red-user" and "red-profile" or "blue-profile") and receipt.matchId == battle.MatchKey)
        packets[userId] = packets[userId] or {}
        table.insert(packets[userId], receipt)
    end
    match:OnBeginPlay()
    match:OnUpdate(1)
    assert(next(packets) == nil)
    battle.Phase = "RESULT"
    match:OnUpdate(1)
    if not war then
        assert(next(packets) == nil and settleCount == 0)
    else
        local redPackets = packets["red-user"]
        local bluePackets = packets["blue-user"]
        assert(settleCount == 1 and redPackets[1].status == "PENDING" and redPackets[1].destination == "")
        if guard then assert(bluePackets == nil) else assert(bluePackets[1].status == "PENDING") end
        settled()
        match:OnUpdate(1)
        local expectedAfter = guard and 15 or 5
        local last = redPackets[#redPackets]
        assert(last.status == "SAVED" and last.targetBefore == 25 and last.targetAfter == expectedAfter and last.destination == "zuoying")
        if not guard then
            local view = bluePackets[#bluePackets]
            assert(view.origin == "gushan" and view.originBefore == 25 and view.originAfter == 5 and view.destination == "gushan")
        end
        local before = #redPackets
        offline["red-user"] = true
        match:OnUpdate(1)
        offline["red-user"] = nil
        match:HandleWarResultReconnect({ UserId = "red-user" })
        match:OnUpdate(1)
        match:OnUpdate(1)
        assert(#redPackets == before + 1 and redPackets[#redPackets].revision > last.revision and settleCount == 1)
        board.zuoying = { owner = "BLUE", strength = 100 }
        match:HandleWarResultRoomBoardChanged({})
        match:OnUpdate(1)
        last = redPackets[#redPackets]
        assert(#redPackets == before + 2 and last.destination == "nanzih" and last.originLost and last.originAfter == 100 and last.targetAfter == expectedAfter)
        match:HandleWarResultRoomBoardChanged({})
        match:OnUpdate(1)
        assert(#redPackets == before + 2, "unchanged preview should not resend")
        users[1] = player("red-user", "red-profile", map)
        match:OnUpdate(1)
        assert(#redPackets == before + 3 and redPackets[#redPackets].destination == "nanzih", "fresh entity gets the receipt without re-settlement")
        assert(settleCount == 1)

        -- Invoke the real client receiver separately from the mocked server transport.
        local client = { Entity = match.Entity }
        setmetatable(client, { __index = matchedBattle })
        _UserService.LocalPlayer = users[1]
        client:ReceiveWarResultReceipt(last)
        client:ReceiveWarResultReceipt(redPackets[1])
        client:ReceiveWarResultReceipt({ profile = last.profile, matchId = "other-match", revision = last.revision + 1 })
        client:ReceiveWarResultReceipt({ profile = "other-profile", matchId = last.matchId, revision = last.revision + 1 })
        assert(client.WarResultReceipt == last, "other matches/profiles and stale packets cannot replace the current receipt")
    end
    doc.Read = read
end
exercise("HUMAN")
exercise("GUARD")
exercise("LOBBY")
log("[VRF][WarResultReceipt] local room/transport cases PASS")

-- #122: a side that was not in the room when the result settled is owed it as its latest absent result; a side that saw the result page is not.
local function exerciseAbsent(kind, blueArrives)
    local match = { _T = {} }
    setmetatable(match, { __index = matchedBattle })
    local guard, war = kind == "GUARD", kind ~= "LOBBY"
    local battle = { Phase = "WAITING", MatchKey = "absent-match" }
    local map = { GetComponent = function() return battle end }
    match.Entity = { CurrentMap = map }
    local function player(id, profile) return { CurrentMap = map, PlayerComponent = { UserId = id, ProfileCode = profile } } end
    local red, blue = player("red-user", "red-profile"), player("blue-user", "blue-profile")
    local users = { red }
    local board, settled = doc:InitialTowns(), nil
    board.gushan.strength = 25
    local written, announced, cleared = {}, {}, {}
    isvalid = function(value) return value ~= nil end
    _UserService = { UserEntities = { Values = users }, GetUserEntityByUserId = function(_, id)
        for _, user in ipairs(users) do if user.PlayerComponent.UserId == id then return user end end
    end }
    _MatchFlow = {
        RoomBattleAdmission = function() return {
            key = battle.MatchKey, home = "red-profile", away = guard and "guard:gushan" or "blue-profile", guard = guard,
            homeTown = war and "zuoying" or "", awayTown = war and "gushan" or "" } end,
        PublishState = function() end,
        Player = function(_, userId) for _, user in ipairs(users) do if user.PlayerComponent.UserId == userId then return user end end end,
    }
    _RoomService = { RoomKey = battle.MatchKey }
    _FormationHandoff = { Roster = function() return {} end }
    _FactionWarGuard = { Roster = function() return {} end, IsGuardProfile = function(_, profile) return string.sub(profile, 1, 6) == "guard:" end }
    _FactionWar = { ReadFaction = function(_, profile, complete) complete(profile == "red-profile" and "RED" or "BLUE") end }
    _FactionWarAttack = { Settle = function(_, key, home, away, result, battleKind, complete)
        settled = function()
            local save = doc:Apply(board, { matchKey = key, home = home, away = away, result = result, kind = battleKind })
            board = save.document
            complete(save.outcome.status, save.detail, save.outcome)
        end
    end }
    _AbsentResult = {
        Compose = function(_, recordKind, matchKey, result, receipt) return { kind = recordKind, id = matchKey, result = result, war = receipt } end,
        Write = function(_, profile, record, complete) written[profile] = record; complete(true) end,
        Announce = function(_, profile, matchKey) announced[profile] = matchKey end,
        Clear = function(_, profile, matchKey, complete) cleared[profile] = matchKey; complete(true) end,
    }
    local read = doc.Read
    doc.Read = function(_, complete) complete(board) end
    function battle:InitializeMatchedBattle(key, home, away)
        self.HomeProfile, self.AwayProfile, self.Phase = home, away, "BATTLE"
        return true
    end
    function battle:ParticipantSide(profile)
        return profile == self.HomeProfile and "PLAYER" or (profile == self.AwayProfile and "ENEMY" or "")
    end
    function battle:ResultForProfile(profile)
        return profile == self.HomeProfile and "WIN" or (profile == self.AwayProfile and "LOSE" or "")
    end
    function match:ReceiveWarResultReceipt() end
    match:OnBeginPlay()
    match:OnUpdate(1)
    battle.Phase = "RESULT"
    match:OnUpdate(1)
    if war then
        assert(next(written) == nil, "a war result waits for its settlement")
        settled()
        match:OnUpdate(1)
    end
    assert(written["red-profile"] == nil and announced["red-profile"] == nil, "the side that saw the result page is owed nothing")
    if guard then
        assert(next(written) == nil and next(announced) == nil, "a guard has no storage and no window")
        doc.Read = read
        return
    end
    local record = assert(written["blue-profile"], "the absent side's result is written: " .. kind)
    assert(record.id == "absent-match" and record.result == "LOSE" and record.kind == (war and "WAR" or "LOBBY"), "kind and result of the record")
    assert(announced["blue-profile"] == "absent-match", "the absent side is announced once the record is written")
    if war then
        assert(record.war.origin == "gushan" and record.war.target == "zuoying" and record.war.status == "SAVED"
            and record.war.originBefore == 25 and record.war.originAfter == 5, "the war block carries the settled figures of the absent side's own towns")
    else
        assert(record.war == nil, "a lobby result has no war block")
    end
    match:OnUpdate(1)
    match:OnUpdate(1)
    local count = 0
    for _ in pairs(written) do count = count + 1 end
    assert(count == 1, "written once")
    if blueArrives then
        table.insert(users, blue)
        match:OnUpdate(1)
        assert(cleared["blue-profile"] == "absent-match", "a side that comes in and sees the result page takes its absent result back")
        cleared["blue-profile"] = nil
        match:OnUpdate(1)
        assert(cleared["blue-profile"] == nil, "taken back once")
    end
    doc.Read = read
end
exerciseAbsent("HUMAN", false)
exerciseAbsent("HUMAN", true)
exerciseAbsent("LOBBY", false)
exerciseAbsent("LOBBY", true)
exerciseAbsent("GUARD", false)
log("[VRF][AbsentResult] room writes only for sides that did not see the result PASS")
