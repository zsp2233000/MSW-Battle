-- Run in a fresh Maker Play test with context=server_main.
-- Movement uses live Maker frames; attack timing and cancellation coverage lives in attack_execution_runtime_probe.lua.
local map = _EntityService:GetEntityByPath("/maps/map01")
local session = map:GetComponent("script.BattleSession")
local failures = 0
local function check(condition, message)
    if condition then log("[M1][ShooterProbe][PASS] " .. message)
    else failures = failures + 1; log_error("[M1][ShooterProbe][FAIL] " .. message) end
end
local ok, detail = pcall(function()
    session:BeginManualSimulation()
    session:TryDeployMonster("monster_shooter", Vector3(-2, 0, 0))
    local shooter = _EntityService:GetEntityByPath("/maps/map01/M1_Player_1")
    for _, entity in ipairs(map.Children:ToTable()) do
        if entity ~= shooter and isvalid(entity:GetComponent("script.BattleUnit")) then entity:SetEnable(false) end
    end
    local targetProfile = {}
    for key, value in pairs(session:GetMonsterProfile("monster_warrior")) do targetProfile[key] = value end
    targetProfile.MoveSpeed = 0
    targetProfile.AttackDamage = 0
    targetProfile.AttackRange = 0
    local target = session:SpawnConfiguredUnit(targetProfile.ModelId, "M1_ShooterProbeTarget", "ENEMY", targetProfile, Vector3(3, 0, 0))
    local actor = shooter:GetComponent("script.BattleUnit")
    local defender = target:GetComponent("script.BattleUnit")
    session:TryStartBattle()
    session:EndManualSimulation()
    wait(0.3)
    check(shooter.TransformComponent.WorldPosition.x > -2, "shooter approaches a target beyond 4.0 range with native movement")
    check(defender.Hp == 220, "shooter does not hit before reaching firing range")
    wait(2.5)
    check(defender.Hp == 190, "live shooter delivers fixed 30 damage after its profile impact frame")
    local hasProjectile = false
    for _, entity in ipairs(map.Children:ToTable()) do
        if string.find(string.lower(entity.Name), "projectile", 1, true) then hasProjectile = true end
    end
    check(not hasProjectile, "hitscan does not spawn a projectile entity")
    session:EnterResult("WIN")
    local hp, serial = defender.Hp, actor.AttackSerial
    wait(2.5)
    check(defender.Hp == hp and actor.AttackSerial == serial, "RESULT stops live movement and future shots")
end)
session:EndManualSimulation()
if not ok then check(false, tostring(detail)) end
log("[M1][ShooterProbe] failures=" .. tostring(failures))
