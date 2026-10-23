-- server_instance_* in a matchprobe room with two players but no admitted match tickets.
-- Create that fixture through RoomService.CreateInstanceRoom / MoveUser from server_main.
local ok, detail = pcall(function()
    local map = _EntityService:GetEntityByPath("/maps/matchprobe")
    local battle = map:GetComponent("script.BattleSession")
    local users = _UserService.UserEntities.Values
    assert(#users == 2 and battle.Phase == "WAITING", "unadmitted room stays empty")
    local home, away = users[1].PlayerComponent.ProfileCode, users[2].PlayerComponent.ProfileCode
    local valid = {{monsterId = "monster_tank", x = -3.25, y = -1.25}}
    local invalid = {
        {},
        {{monsterId = "missing", x = -3.25, y = -1.25}},
        {{monsterId = "monster_tank", x = -3.25, y = -1.25, MaxHp = 999999}},
        {{monsterId = "monster_tank", x = math.huge, y = -1.25}},
        {{monsterId = "monster_tank", x = -999, y = -1.25}},
        {[2] = {monsterId = "monster_tank", x = -3.25, y = -1.25}},
        {valid[1], valid[1]},
        {valid[1], valid[1], valid[1], valid[1], valid[1], valid[1], valid[1]},
    }
    local before = battle:GetDebugSnapshot()
    for _, roster in ipairs(invalid) do
        assert(not battle:InitializeMatchedBattle(_RoomService.RoomKey, home, away, valid, roster), "invalid opponent rejected")
        assert(battle:GetDebugSnapshot() == before, "invalid input is atomic")
    end
    assert(not battle:InitializeMatchedBattle("wrong-room", home, away, valid, valid), "room ownership required")
    assert(not battle:InitializeMatchedBattle(_RoomService.RoomKey, home, home, valid, valid), "distinct participants required")
    assert(battle.PlayerAlive == 0 and battle.EnemyAlive == 0 and battle.Result == "", "no map enemies or invented result")
    local flow = map:GetFirstChildComponentByTypeName("script.MatchedBattle", true)
    assert(isvalid(flow), "map-scoped admission controller exists")
    for attempt = 1, 350 do
        if flow.AdmissionFailed then break end
        wait(0.1)
    end
    assert(flow.AdmissionFailed, "admission timeout reached its failure state")
    assert(battle.Phase == "WAITING" and battle.Result == "", "entry timeout is not a combat loss")
    log("[VRF][MatchedEntryFailure] PASS invalid rosters atomic; no invented result; waiting for visible return test")
end)
if not ok then log("[VRF][MatchedEntryFailure] FAIL " .. tostring(detail)) end
