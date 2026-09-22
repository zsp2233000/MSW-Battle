-- Execute this probe in Maker Play mode with context=server_main after the fixed battle starts.
-- It drives the production BattleSession, BattleUnit, ShooterAttack, Hit, and result-stop paths.
local map = _EntityService:GetEntityByPath("/maps/map01")
local session = map:GetComponent("script.BattleSession")
local failures = 0

local function check(condition, message)
    -- Record a failed acceptance assertion without stopping later probe checks.
    if condition then
        log("[M1][ShooterProbe][PASS] " .. message)
    else
        failures = failures + 1
        log_error("[M1][ShooterProbe][FAIL] " .. message)
    end
end

local function getPosition(entity)
    -- Read the native Kinematicbody position used by the production movement path.
    return entity:GetComponent("TransformComponent").WorldPosition
end

local function freezeUnit(entity)
    -- Freeze an unrelated fixture so this probe isolates the shooter behavior.
    local unit = entity:GetComponent("script.BattleUnit")
    local movement = entity:GetComponent("MovementComponent")
    if isvalid(unit) then
        unit:CancelAttack()
        unit.MoveSpeed = 0
        unit.RetargetInterval = 99
    end
    if isvalid(movement) then
        movement.InputSpeed = 0
        movement:Stop()
    end
end

local function silenceAssaultTarget(entity)
    -- Keep a real BattleUnit target alive without letting its own adapter affect the probe.
    local unit = entity:GetComponent("script.BattleUnit")
    unit:Configure("ENEMY", entity.Name, "ASSAULT", 220, 0, 0, 99, 0.6, 99, 0.18, 0.6, 0, 2.0, Vector2(1.2, 1.2), 0.8, 0.2)
    freezeUnit(entity)
end

local function hasProjectileEntity(entity)
    -- Inspect the actual map hierarchy so the no-projectile contract is not inferred from snapshots alone.
    if not isvalid(entity) then return false end
    if string.find(string.lower(entity.Name), "projectile", 1, true) ~= nil then return true end
    if entity.Children == nil then return false end
    for _, child in ipairs(entity.Children:ToTable()) do
        if hasProjectileEntity(child) then return true end
    end
    return false
end

if not isvalid(map) or not isvalid(session) or not session:IsBattleActive() then
    log_error("[M1][ShooterProbe][FAIL] fixed battle session is not ready")
    return
end

local fixedTank = _EntityService:GetEntityByPath("/maps/map01/M1_PlayerTank")
local fixedShooter = _EntityService:GetEntityByPath("/maps/map01/M1_PlayerShooter")
local fixedAssault = _EntityService:GetEntityByPath("/maps/map01/M1_EnemyAssault")
if isvalid(fixedTank) then freezeUnit(fixedTank) end
if isvalid(fixedShooter) then freezeUnit(fixedShooter) end
if isvalid(fixedAssault) then
    freezeUnit(fixedAssault)
    fixedAssault:GetComponent("KinematicbodyComponent"):SetWorldPosition(Vector2(-5, 1.5))
end

local shooter = session:SpawnUnit(session.PlayerModelId, "M1_ShooterProbe", "PLAYER", "SHOOTER", Vector3(0, 0, 0))
local target = session:SpawnUnit(session.EnemyModelId, "M1_ShooterProbeTarget", "ENEMY", "ASSAULT", Vector3(5, 0, 0))
if not isvalid(shooter) or not isvalid(target) then
    log_error("[M1][ShooterProbe][FAIL] shooter fixture spawn failed")
    return
end
session.PlayerAlive = session.PlayerAlive + 1
session.EnemyAlive = session.EnemyAlive + 1
silenceAssaultTarget(target)

local shooterUnit = shooter:GetComponent("script.BattleUnit")
local targetUnit = target:GetComponent("script.BattleUnit")
local shooterStart = getPosition(shooter)
session:AdvanceForTest(0.5)
local outsideRangeHp = targetUnit.Hp
local movedShooter = getPosition(shooter)
check(movedShooter.x > shooterStart.x, "shooter approaches a target beyond 4.0 range")
check(outsideRangeHp == 220, "shooter does not attack while target remains beyond 4.0 range")

session:AdvanceForTest(1.0)
local firstHitHp = targetUnit.Hp
local firstAttackSerial = shooterUnit.AttackSerial
check(firstHitHp == 190, "shooter deals fixed 30 damage after the configurable impact delay")
check(session.LastEvent == "DAMAGE", "shooter reaches the semantic damage event through Hit")

session:AdvanceForTest(0.5)
check(targetUnit.Hp == 190 and shooterUnit.AttackSerial == firstAttackSerial, "shooter attack interval blocks a second shot before 0.8 seconds")
session:AdvanceForTest(0.31)
check(shooterUnit.AttackSerial == firstAttackSerial + 1, "shooter starts the next shot after the 0.8 second interval")
session:AdvanceForTest(0.2)
check(targetUnit.Hp == 160, "shooter applies the next hit after its impact delay")

local cancelShooter = session:SpawnUnit(session.PlayerModelId, "M1_ShooterProbeCancel", "PLAYER", "SHOOTER", Vector3(0, -1, 0))
local cancelTarget = session:SpawnUnit(session.EnemyModelId, "M1_ShooterProbeCancelTarget", "ENEMY", "ASSAULT", Vector3(3, -1, 0))
if not isvalid(cancelShooter) or not isvalid(cancelTarget) then
    log_error("[M1][ShooterProbe][FAIL] cancellation fixture spawn failed")
    return
end
session.PlayerAlive = session.PlayerAlive + 1
session.EnemyAlive = session.EnemyAlive + 1
silenceAssaultTarget(cancelTarget)
freezeUnit(cancelShooter)
session:AdvanceForTest(0.05)
cancelTarget:GetComponent("KinematicbodyComponent"):SetWorldPosition(Vector2(5, -1))
session:AdvanceForTest(0.2)
check(cancelTarget:GetComponent("script.BattleUnit").Hp == 220, "target leaves range before impact cancels the pending shot")

local timingShooter = session:SpawnUnit(session.PlayerModelId, "M1_ShooterProbeTiming", "PLAYER", "SHOOTER", Vector3(0, -2, 0))
local timingTarget = session:SpawnUnit(session.EnemyModelId, "M1_ShooterProbeTimingTarget", "ENEMY", "ASSAULT", Vector3(3, -2, 0))
if not isvalid(timingShooter) or not isvalid(timingTarget) then
    log_error("[M1][ShooterProbe][FAIL] impact timing fixture spawn failed")
    return
end
session.PlayerAlive = session.PlayerAlive + 1
session.EnemyAlive = session.EnemyAlive + 1
silenceAssaultTarget(timingTarget)
freezeUnit(timingShooter)
local timingTargetUnit = timingTarget:GetComponent("script.BattleUnit")
session:AdvanceForTest(0.05)
check(timingTargetUnit.Hp == 220, "shooter keeps target HP unchanged during the pre-impact window")
check(session.LastEvent == "ATTACK_START", "shooter publishes the semantic attack-start event before impact")
session:AdvanceForTest(0.2)
check(timingTargetUnit.Hp == 190, "shooter applies damage after the configured impact time")

local deathShooter = session:SpawnUnit(session.PlayerModelId, "M1_ShooterProbeDeath", "PLAYER", "SHOOTER", Vector3(0, -3, 0))
local deathTarget = session:SpawnUnit(session.EnemyModelId, "M1_ShooterProbeDeathTarget", "ENEMY", "ASSAULT", Vector3(3, -3, 0))
if not isvalid(deathShooter) or not isvalid(deathTarget) then
    log_error("[M1][ShooterProbe][FAIL] death cancellation fixture spawn failed")
    return
end
session.PlayerAlive = session.PlayerAlive + 1
session.EnemyAlive = session.EnemyAlive + 1
silenceAssaultTarget(deathTarget)
freezeUnit(deathShooter)
local deathTargetUnit = deathTarget:GetComponent("script.BattleUnit")
session:AdvanceForTest(0.05)
session:QueueDamage(deathTarget, 220, deathShooter)
session:AdvanceForTest(0.05)
session:AdvanceForTest(0.2)
check(deathTargetUnit.IsDead == true and deathTargetUnit.Hp == 0 and deathTargetUnit.DamageTakenSerial == 1, "target dies before impact and cancels the pending shot")

local snapshots = session:GetUnitSnapshots()
check(string.find(snapshots, "Projectile") == nil and string.find(snapshots, "projectile") == nil and not hasProjectileEntity(map), "shooter registers no projectile entity")

session:EnterResult("WIN")
local hpAtResult = targetUnit.Hp
session:AdvanceForTest(1.0)
check(targetUnit.Hp == hpAtResult, "RESULT blocks future shooter movement, attacks, and damage")

if failures == 0 then
    log("[M1][ShooterProbe] PASS")
else
    log_error("[M1][ShooterProbe] FAILURES=" .. tostring(failures))
end
