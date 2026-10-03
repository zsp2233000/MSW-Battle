-- Run in a fresh Maker Play test, context=server_main.
-- Manual time controls custom battle logic; native physics still runs normally.
local session = _EntityService:GetEntityByPath("/maps/map01"):GetComponent("script.BattleSession")
local failures = 0
local function check(condition, message)
    if condition then log("[AttackClockProbe][PASS] " .. message)
    else failures = failures + 1; log_error("[AttackClockProbe][FAIL] " .. message) end
end
if session.BeginManualSimulation == nil then
    log_error("[AttackClockProbe][FAIL] manual clock API is missing")
    return
end
check(session:BeginManualSimulation(), "manual clock is acquired explicitly")
local ok, detail = pcall(function()
    check(not session:BeginManualSimulation(), "a second driver cannot acquire the clock")
    session:TryDeployMonster("monster_shooter", Vector3(-2, 0, 0))
    local shooter = _EntityService:GetEntityByPath("/maps/map01/M1_Player_1")
    local target = _EntityService:GetEntityByPath("/maps/map01/M1_EnemyAssault")
    for _, entity in ipairs(session:GetMapEntity().Children:ToTable()) do
        local unit = entity:GetComponent("script.BattleUnit")
        if isvalid(unit) then
            unit.MoveSpeed = 0
            if entity ~= shooter and entity ~= target then entity:SetEnable(false) end
        end
    end
    target.KinematicbodyComponent:SetWorldPosition(Vector2(1, 0))
    target:GetComponent("script.BattleUnit").AttackRange = 0
    local actor = shooter:GetComponent("script.BattleUnit")
    local defender = target:GetComponent("script.BattleUnit")
    local hp = defender.Hp
    session:TryStartBattle()
    session:AdvanceForTest(0.05)
    check(actor.AttackSerial == 1 and defender.Hp == hp, "manual step starts one pre-impact attack")
    wait(0.35)
    check(actor.AttackSerial == 1 and defender.Hp == hp, "live frames do not advance a manually held attack")
    session:AdvanceForTest(actor.ImpactDelay + 0.01)
    check(defender.Hp == hp - 30, "manual elapsed time reaches the native hit")
    session:EndManualSimulation()
    local serial = actor.AttackSerial
    session:AdvanceForTest(10)
    check(actor.AttackSerial == serial, "manual elapsed time is rejected while live clock owns the session")
    wait(1.1)
    check(actor.AttackSerial > serial, "live clock resumes attacks after release")
end)
session:EndManualSimulation()
if not ok then check(false, tostring(detail)) end
log("[AttackClockProbe] failures=" .. tostring(failures))
