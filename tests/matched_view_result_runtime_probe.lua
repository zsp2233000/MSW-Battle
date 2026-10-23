-- Run in the matched server instance. Confirms one natural terminal and complementary viewer results, then returns.
local ok, detail = pcall(function()
    local battle = _EntityService:GetEntityByPath("/maps/matchprobe"):GetComponent("script.BattleSession")
    assert(battle.InitialPlayerAlive == 6 and battle.InitialEnemyAlive == 6, "formal match is not 6v6")
    for _ = 1, 900 do if battle.Phase == "RESULT" then break end wait(0.1) end
    assert(battle.Phase == "RESULT", "natural battle did not finish")
    local home = battle:ResultForProfile(battle.HomeProfile)
    local away = battle:ResultForProfile(battle.AwayProfile)
    assert(home == "WIN" or home == "LOSE" or home == "DRAW", "home result missing")
    if home == "DRAW" then assert(away == "DRAW", "draw must be shared")
    elseif home == "WIN" then assert(away == "LOSE", "away result is not complementary")
    else assert(away == "WIN", "away result is not complementary") end
    local serial = battle.EventSerial
    wait(1)
    assert(battle.EventSerial == serial and battle.Phase == "RESULT", "terminal state changed")
    local ids = {}
    for _, user in ipairs(_UserService.UserEntities.Values) do table.insert(ids, user.PlayerComponent.UserId) end
    for _, userId in ipairs(ids) do _MatchProbe:ReturnForUser(userId) end
    log("[VRF][BattleView] RESULT_PASS home=" .. home .. " away=" .. away .. " events=" .. tostring(serial))
end)
if not ok then log("[VRF][BattleView] RESULT_FAIL " .. tostring(detail)) end
