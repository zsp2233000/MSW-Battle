-- Run in Maker Play with context=server_main before pressing Start in the UI.
-- Exercises the production server deployment gates without replacing combat logic.
local map = nil
local session = nil
local failures = 0
local function check(condition, message)
    if condition then
        log("[M1][DeploymentProbe][PASS] " .. message)
    else
        failures = failures + 1
        log_error("[M1][DeploymentProbe][FAIL] " .. message)
    end
end

local runOk, runDetail = pcall(function()
map = _EntityService:GetEntityByPath("/maps/map01")
session = isvalid(map) and map:GetComponent("script.BattleSession") or nil
check(isvalid(map) and isvalid(session), "map and BattleSession are available")
if not isvalid(session) then return end

check(session.Phase == "DEPLOYMENT" and session.PlayerAlive == 0 and session.EnemyAlive == 6,
    "deployment starts empty against six fixed enemies")
check(not session:TryStartBattle(), "zero player units cannot start")
check(not session:TryRemoveDeployedUnitAt(Vector3(-5, 1, 0)), "removal with no deployed player unit is rejected")
check(not session:TryDeployMonster("missing_monster", Vector3(-4, 0, 0)), "unknown MonsterId is rejected")
check(not session:TryDeployMonster("monster_tank", Vector3(-5.01, 0, 0)), "left of boundary is rejected")
check(not session:TryDeployMonster("monster_tank", Vector3(-4, 1.01, 0)), "above boundary is rejected")
local tankProfile = session:GetMonsterProfile("monster_tank")
local secondTankProfile = session:GetMonsterProfile("monster_tank")
local originalName = tankProfile.MonsterName
local originalMaxHp = tankProfile.MaxHp
local originalAttackDamage = tankProfile.AttackDamage
local originalStandAnimation = tankProfile.StandAnimationRUID
check(tankProfile ~= secondTankProfile, "profile lookups return distinct outer tables")
tankProfile.MonsterName = "ProbeMutation"
tankProfile.MaxHp = -1
tankProfile.AttackDamage = -1
local profileAfterMutation = session:GetMonsterProfile("monster_tank")
check(profileAfterMutation.MonsterName == originalName and profileAfterMutation.MaxHp == originalMaxHp
    and profileAfterMutation.AttackDamage == originalAttackDamage,
    "editing a profile copy does not mutate catalog name, health, or attack")
check(profileAfterMutation.StandAnimationRUID == originalStandAnimation,
    "profile copies retain the catalog animation resource value")
check(session:TryDeployMonster("monster_tank", Vector3(-5, 1, 0)), "inclusive top-left boundary accepts first unit")
local first = _EntityService:GetEntityByPath("/maps/map01/M1_Player_1")
local firstUnit = isvalid(first) and first:GetComponent("script.BattleUnit") or nil
check(isvalid(firstUnit) and firstUnit.MonsterId == "monster_tank" and firstUnit.MonsterName == originalName
    and firstUnit.MaxHp == originalMaxHp and firstUnit.AttackDamage == originalAttackDamage,
    "deployed unit uses the unmodified catalog profile")
check(not session:TryDeployMonster("monster_tank", Vector3(-4.41, 1, 0)), "distance below 0.6 is rejected")
check(session:TryDeployMonster("monster_tank", Vector3(-4.4, 1, 0)), "same MonsterId deploys at distance 0.6")
check(session:TryDeployMonster("monster_warrior", Vector3(-3.8, 1, 0)), "different MonsterId deploys")
check(session:TryDeployMonster("monster_shooter", Vector3(-3.2, 1, 0)), "third type deploys")
check(session:TryDeployMonster("monster_tank", Vector3(-2.6, 1, 0)), "same MonsterId can repeat")
check(session:TryDeployMonster("monster_warrior", Vector3(-2, 1, 0)), "inclusive right boundary accepts sixth unit")
for playerCount = 1, 6 do
    check(session:CanStartBattleWithPlayerCount(playerCount), "start accepts player count " .. tostring(playerCount))
end
check(not session:CanStartBattleWithPlayerCount(0), "start rejects player count zero")
check(not session:CanStartBattleWithPlayerCount(7), "start rejects player count above capacity")
check(not session:TryDeployMonster("monster_shooter", Vector3(-2, 0, 0)), "seventh unit is rejected")
check(session.PlayerAlive == 6 and session.EnemyAlive == 6, "rejections preserve roster counts")

local invalidZ = 0 / 0
check(not session:TryRemoveDeployedUnitAt(Vector3(-2, 1, invalidZ)), "removal with a NaN z coordinate is rejected")
check(not session:TryRemoveDeployedUnitAt(Vector3(-1.49, 1, 0)), "removal outside the 0.5 radius is rejected")
check(session:TryRemoveDeployedUnitAt(Vector3(-2, 1, 0)), "position-based removal selects the deployed unit")
check(session.PlayerAlive == 5 and string.find(session:GetUnitSnapshots(), "M1_Player_6", 1, true) == nil,
    "removal releases one roster slot and updates the public unit snapshot")
check(session:TryDeployMonster("monster_shooter", Vector3(-2, -3, 0)), "inclusive bottom boundary accepts replacement")
check(session.PlayerAlive == 6 and string.find(session:GetUnitSnapshots(), "M1_Player_7", 1, true) ~= nil,
    "redeployment registers exactly one replacement unit")
check(session:TryStartBattle(), "one to six units can start battle")
check(session.Phase == "BATTLE" and session.InitialPlayerAlive == 6, "start locks six-unit roster")
check(not session:CanStartBattleWithPlayerCount(1), "start gate closes after battle begins")
check(not session:TryDeployMonster("monster_tank", Vector3(-4, -2, 0)), "deployment after start is rejected")
local beforeRemove = session.PlayerAlive
check(not session:TryRemoveDeployedUnitAt(Vector3(-2, -3, 0)), "removal after start is rejected")
check(session.PlayerAlive == beforeRemove, "rejected removal preserves the roster count")
check(not session:TryStartBattle(), "second start is rejected")
end)

if not runOk then check(false, "probe raised: " .. tostring(runDetail)) end

if failures == 0 then
    log("[M1][DeploymentProbe] PASS")
else
    log_error("[M1][DeploymentProbe] FAILURES=" .. tostring(failures))
end
