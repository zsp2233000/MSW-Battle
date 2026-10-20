-- Run in the matched server_instance_* context after matched_battle_queue_runtime_probe.lua.
local ok, detail = pcall(function()
    local battle = _EntityService:GetEntityByPath("/maps/matchprobe"):GetComponent("script.BattleSession")
    assert(battle.InitialPlayerAlive == 6 and battle.InitialEnemyAlive == 1, "queue-time rosters, not the later one-unit save")
    assert(battle:PrepareBattleForTest({}, {}) == false, "Maker fixture cannot replace a production match")
    assert(battle:InitializeMatchedBattle(battle.MatchKey, battle.HomeProfile, battle.AwayProfile, {}, {}) == false, "cannot initialize twice")
    for attempt = 1, 450 do if battle.Phase == "RESULT" then break end wait(0.1) end
    assert(battle.Phase == "RESULT", "natural battle finishes")
    assert(battle:ResultForProfile(battle.HomeProfile) == "WIN", "six tanks win naturally")
    assert(battle:ResultForProfile(battle.AwayProfile) == "LOSE", "opponent sees the complementary result")
    assert(battle:ResultForProfile("outsider") == "", "outsider has no result")
    local serial = battle.EventSerial
    wait(1)
    assert(battle.EventSerial == serial, "terminal state stays stable")
    local ids = {}
    for _, user in ipairs(_UserService.UserEntities.Values) do table.insert(ids, user.PlayerComponent.UserId) end
    for _, userId in ipairs(ids) do _MatchProbe:ReturnForUser(userId) end
    log("[VRF][MatchedRoom] PASS immutable 6v1; natural WIN/LOSE; stable terminal; return dispatched")
end)
if not ok then log("[VRF][MatchedRoom] FAIL " .. tostring(detail)) end
