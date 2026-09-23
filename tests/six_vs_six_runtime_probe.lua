-- Execute this probe in Maker Play mode with context=server_main shortly after the fixed battle starts.
-- It observes the production six-versus-six BattleSession seams without adding UI or alternate combat logic.
local map = _EntityService:GetEntityByPath("/maps/map01")
local session = map:GetComponent("script.BattleSession")
local failures = 0

local function check(condition, message)
    -- Record a failed high-level acceptance assertion without hiding later evidence.
    if condition then
        log("[M1][SixVsSixProbe][PASS] " .. message)
    else
        failures = failures + 1
        log_error("[M1][SixVsSixProbe][FAIL] " .. message)
    end
end

local function getEntity(name)
    -- Resolve one fixed roster member by the session's stable map path.
    return _EntityService:GetEntityByPath("/maps/map01/" .. name)
end

local function getPosition(entity)
    -- Read the native RectTile world position used by the production movement path.
    return entity:GetComponent("TransformComponent").WorldPosition
end

local function setPosition(entity, x, y)
    -- Use the RectTile body teleport only for deterministic test fixture placement.
    entity:GetComponent("KinematicbodyComponent"):SetWorldPosition(Vector2(x, y))
end

local function freezeUnit(entity)
    -- Freeze a fixture's own AI while leaving its BattleUnit registration intact.
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

if not isvalid(map) or not isvalid(session) then
    log_error("[M1][SixVsSixProbe][FAIL] map or session is unavailable")
    return
end

check(session.InitialPlayerAlive == 6 and session.InitialEnemyAlive == 6, "fixed six-versus-six roster starts with six alive units per faction")
check(session:IsBattleActive(), "fixed six-versus-six battle enters BATTLE without deployment UI")
local snapshots = session:GetUnitSnapshots()
check(string.find(snapshots, "monsterId=monster_tank") ~= nil and string.find(snapshots, "monsterId=monster_warrior") ~= nil and string.find(snapshots, "monsterId=monster_shooter") ~= nil, "snapshot exposes MonsterId, editable name, and kind for all initial rows")

-- Freeze the production roster so the high-level fixtures are not consumed by the live battle while this probe runs.
for _, name in ipairs({"M1_PlayerTank", "M1_PlayerTank2", "M1_PlayerWarrior", "M1_PlayerWarrior2", "M1_PlayerShooter", "M1_PlayerShooter2", "M1_EnemyTank", "M1_EnemyTank2", "M1_EnemyAssault", "M1_EnemyAssault2", "M1_EnemyShooter", "M1_EnemyShooter2"}) do
    local entity = getEntity(name)
    if isvalid(entity) then
        freezeUnit(entity)
        entity:SetEnable(false)
    end
end

-- Spawn isolated production BattleUnit fixtures so the assertions remain deterministic even if Maker dispatches the probe a few frames after Play starts.
local source = session:SpawnUnit(session.PlayerModelId, "M1_ProbeSource", "PLAYER", "TANK", Vector3(-4, 0, 0))
local preferred = session:SpawnUnit(session.EnemyModelId, "M1_ProbePreferred", "ENEMY", "ASSAULT", Vector3(0, 0, 0))
local replacement = session:SpawnUnit(session.EnemyModelId, "M1_ProbeReplacement", "ENEMY", "ASSAULT", Vector3(0, 0, 0))
local crowdA = session:SpawnUnit(session.PlayerModelId, "M1_ProbeCrowdA", "PLAYER", "TANK", Vector3(-4, -2, 0))
local crowdB = session:SpawnUnit(session.PlayerModelId, "M1_ProbeCrowdB", "PLAYER", "TANK", Vector3(-4, -2, 0))
if not isvalid(source) or not isvalid(preferred) or not isvalid(replacement) or not isvalid(crowdA) or not isvalid(crowdB) then
    log_error("[M1][SixVsSixProbe][FAIL] isolated production fixtures are unavailable")
    return
end

freezeUnit(source)
freezeUnit(preferred)
freezeUnit(replacement)
freezeUnit(crowdB)
setPosition(source, -4, 0)
setPosition(preferred, 0, 0)
setPosition(replacement, 0, 0)

-- same-distance target is retained
check(session:FindNearestEnemy(source, preferred) == preferred, "same-distance target is retained")

-- dead target is reacquired
preferred:SetEnable(false)
check(session:FindNearestEnemy(source, preferred) == replacement, "dead target is reacquired")
preferred:SetEnable(true)

-- crowded units do not block or push each other
local crowdUnitA = crowdA:GetComponent("script.BattleUnit")
local crowdUnitB = crowdB:GetComponent("script.BattleUnit")
local crowdMovementA = crowdA:GetComponent("MovementComponent")
local crowdMovementB = crowdB:GetComponent("MovementComponent")
setPosition(crowdA, -4, -2)
setPosition(crowdB, -4, -2)
setPosition(replacement, 0, -2)
crowdUnitA.MoveSpeed = 1.0
crowdUnitB.MoveSpeed = 1.0
crowdUnitA.RetargetInterval = 0
crowdUnitB.RetargetInterval = 0
session:AdvanceForTest(0.25)
local crowdPositionA = getPosition(crowdA)
local crowdPositionB = getPosition(crowdB)
check(crowdPositionA.x > -4 and crowdPositionB.x > -4 and math.abs(crowdPositionA.x - crowdPositionB.x) < 0.01, "crowded units do not block or push each other")
if isvalid(crowdMovementA) then crowdMovementA:Stop() end
if isvalid(crowdMovementB) then crowdMovementB:Stop() end

-- WIN
check(session:DetermineResult(6, 0) == "WIN", "WIN is selected when the fixed enemy faction is depleted")

-- LOSE
check(session:DetermineResult(0, 6) == "LOSE", "LOSE is selected when the player faction is depleted")

-- same-batch DRAW
check(session:DetermineResult(0, 0) == "DRAW", "same-batch DRAW is selected when both factions are depleted")

-- RESULT stops the battle
local positionAtResult = getPosition(crowdA)
local attackSerialAtResult = crowdUnitA.AttackSerial
session:EnterResult("WIN")
session:EnterResult("LOSE")
session:AdvanceForTest(1.0)
local positionAfterResult = getPosition(crowdA)
check(session.Phase == "RESULT" and session.Result == "WIN" and session:IsBattleActive() == false, "RESULT stops the battle")
check(positionAfterResult.x == positionAtResult.x and positionAfterResult.y == positionAtResult.y and crowdUnitA.AttackSerial == attackSerialAtResult, "RESULT stops movement and future attacks")

if failures == 0 then
    log("[M1][SixVsSixProbe] PASS")
else
    log_error("[M1][SixVsSixProbe] FAILURES=" .. tostring(failures))
end
