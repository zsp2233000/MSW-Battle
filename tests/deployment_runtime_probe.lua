-- Run in Maker Play with context=server_main before pressing Start in the UI.
-- Exercises the production server deployment gates without replacing combat logic.
local map = _EntityService:GetEntityByPath("/maps/map01")
local session = isvalid(map) and map:GetComponent("script.BattleSession") or nil
if not isvalid(session) then
    log_error("[M1][DeploymentProbe][FAIL] BattleSession unavailable")
    return
end

local failures = 0
local function check(condition, message)
    if condition then
        log("[M1][DeploymentProbe][PASS] " .. message)
    else
        failures = failures + 1
        log_error("[M1][DeploymentProbe][FAIL] " .. message)
    end
end

check(session.Phase == "DEPLOYMENT" and session.PlayerAlive == 0 and session.EnemyAlive == 6,
    "deployment starts empty against six fixed enemies")
check(not session:TryStartBattle(), "zero player units cannot start")
check(not session:TryDeployMonster("missing_monster", Vector3(-4, 0, 0)), "unknown MonsterId is rejected")
check(not session:TryDeployMonster("monster_tank", Vector3(-5.01, 0, 0)), "left of boundary is rejected")
check(not session:TryDeployMonster("monster_tank", Vector3(-4, 1.01, 0)), "above boundary is rejected")
local tankProfile = session:GetMonsterProfile("monster_tank")
local originalName = tankProfile.MonsterName
tankProfile.MonsterName = "RenamedTank"
check(session:TryDeployMonster("monster_tank", Vector3(-5, 1, 0)), "inclusive top-left boundary accepts first unit")
local first = _EntityService:GetEntityByPath("/maps/map01/M1_Player_1")
local firstUnit = isvalid(first) and first:GetComponent("script.BattleUnit") or nil
check(isvalid(firstUnit) and firstUnit.MonsterId == "monster_tank" and firstUnit.MonsterName == "RenamedTank",
    "changing MonsterName keeps MonsterId identity")
tankProfile.MonsterName = originalName
local variant = {}
for key, value in pairs(tankProfile) do variant[key] = value end
variant.MonsterId = "probe_tank_variant"
variant.MonsterName = "VariantTank"
session._T.monstersById[variant.MonsterId] = variant
check(not session:TryDeployMonster("monster_tank", Vector3(-4.41, 1, 0)), "distance below 0.6 is rejected")
check(session:TryDeployMonster(variant.MonsterId, Vector3(-4.4, 1, 0)), "same type with different MonsterId is accepted at distance 0.6")
check(session:TryDeployMonster("monster_warrior", Vector3(-3.8, 1, 0)), "different MonsterId deploys")
check(session:TryDeployMonster("monster_shooter", Vector3(-3.2, 1, 0)), "third type deploys")
check(session:TryDeployMonster("monster_tank", Vector3(-2.6, 1, 0)), "same MonsterId can repeat")
check(session:TryDeployMonster("monster_warrior", Vector3(-2, 1, 0)), "inclusive right boundary accepts sixth unit")
check(not session:TryDeployMonster("monster_shooter", Vector3(-2, 0, 0)), "seventh unit is rejected")
check(session.PlayerAlive == 6 and session.EnemyAlive == 6, "rejections preserve roster counts")

session:RemoveDeployedUnit(#session._T.units)
check(session.PlayerAlive == 5, "removal releases one roster slot")
check(session:TryDeployMonster("monster_shooter", Vector3(-2, -3, 0)), "inclusive bottom boundary accepts replacement")
check(session:TryStartBattle(), "one to six units can start battle")
check(session.Phase == "BATTLE" and session.InitialPlayerAlive == 6, "start locks six-unit roster")
check(not session:TryDeployMonster("monster_tank", Vector3(-4, -2, 0)), "deployment after start is rejected")
local beforeRemove = session.PlayerAlive
session:RemoveDeployedUnit(#session._T.units)
check(session.PlayerAlive == beforeRemove, "removal after start is rejected")
check(not session:TryStartBattle(), "second start is rejected")

if failures == 0 then
    log("[M1][DeploymentProbe] PASS")
else
    log_error("[M1][DeploymentProbe] FAILURES=" .. tostring(failures))
end
