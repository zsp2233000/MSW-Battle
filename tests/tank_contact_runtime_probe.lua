-- Execute this probe in Maker Play mode with context=server_main during deployment.
-- It drives the production BattleSession, BattleUnit, TankContactAttack, Hit, and knockback paths.
local map = _EntityService:GetEntityByPath("/maps/map01")
local session = map:GetComponent("script.BattleSession")
if isvalid(session) and session.Phase == "DEPLOYMENT" then
    session:TryDeployMonster("monster_tank", Vector3(-4.4, 0, 0))
    session:TryStartBattle()
end
local tank = _EntityService:GetEntityByPath("/maps/map01/M1_Player_1")
local fixedShooter = nil
local tankUnit = tank:GetComponent("script.BattleUnit")
local tankBody = tank:GetComponent("KinematicbodyComponent")
local failures = 0
local probes = {}

local function check(condition, message)
    -- Record a failed acceptance assertion without stopping later probe checks.
    if condition then
        log("[M1][TankProbe][PASS] " .. message)
    else
        failures = failures + 1
        log_error("[M1][TankProbe][FAIL] " .. message)
    end
end

local function getProbePosition(entity)
    -- Read the native Kinematicbody position used by the production knockback path.
    return entity:GetComponent("TransformComponent").WorldPosition
end

local function placeProbesAtTank()
    -- Re-overlap both real enemy entities so the production per-target timers can be observed.
    local position = getProbePosition(tank)
    for index, entity in ipairs(probes) do
        local movement = entity:GetComponent("MovementComponent")
        if isvalid(movement) then
            movement.InputSpeed = 0
            movement:Stop()
        end
        local offset = index == 1 and 0.2 or -0.2
        entity:GetComponent("KinematicbodyComponent"):SetWorldPosition(Vector2(position.x + offset, position.y))
    end
end

local function logProbeState(label)
    -- Publish direct runtime state for the acceptance ledger.
    local firstUnit = probes[1]:GetComponent("script.BattleUnit")
    local secondUnit = probes[2]:GetComponent("script.BattleUnit")
    local tankPosition = getProbePosition(tank)
    log("[M1][TankProbe] " .. label .. " hp1=" .. tostring(firstUnit.Hp) .. " hp2=" .. tostring(secondUnit.Hp) .. " tank=" .. tostring(tankPosition.x) .. "," .. tostring(tankPosition.y) .. " event=" .. session.LastEvent .. " serial=" .. tostring(session.EventSerial))
end

if not isvalid(map) or not isvalid(session) or not isvalid(tank) or not isvalid(tankUnit) or not isvalid(tankBody) or not session:IsBattleActive() then
    log_error("[M1][TankProbe][FAIL] battle session is not ready")
    return
end

-- Disable every fixed unit except the Tank under test so the six-versus-six session cannot consume the contact fixtures.
for _, name in ipairs({"M1_PlayerTank2", "M1_PlayerWarrior", "M1_PlayerWarrior2", "M1_PlayerShooter", "M1_PlayerShooter2", "M1_EnemyTank", "M1_EnemyTank2", "M1_EnemyAssault", "M1_EnemyAssault2", "M1_EnemyShooter", "M1_EnemyShooter2"}) do
    local entity = _EntityService:GetEntityByPath("/maps/map01/" .. name)
    if isvalid(entity) then
        local unit = entity:GetComponent("script.BattleUnit")
        local movement = entity:GetComponent("MovementComponent")
        if isvalid(unit) then
            unit:CancelAttack()
            unit.MoveSpeed = 0
            unit.RetargetInterval = 99
        end
        if isvalid(movement) then movement:Stop() end
        entity:SetEnable(false)
    end
end

-- Freeze the fixed shooter so its ranged adapter cannot affect the tank contact fixtures.
if isvalid(fixedShooter) then
    local shooterUnit = fixedShooter:GetComponent("script.BattleUnit")
    local shooterMovement = fixedShooter:GetComponent("MovementComponent")
    if isvalid(shooterUnit) then
        shooterUnit:CancelAttack()
        shooterUnit.MoveSpeed = 0
        shooterUnit.RetargetInterval = 99
    end
    if isvalid(shooterMovement) then
        shooterMovement.InputSpeed = 0
        shooterMovement:Stop()
    end
end

-- Freeze the Tank only for this probe so its position can be compared across contact hits.
tankUnit.MoveSpeed = 0
tankBody:SetWorldPosition(Vector2(0, 0))
local initialPosition = getProbePosition(tank)
for index = 1, 2 do
    local enemy = session:SpawnUnit(session.EnemyModelId, "M1_TankProbeEnemy" .. tostring(index), "ENEMY", "ASSAULT", Vector3(10, 10, 0))
    local enemyUnit = enemy:GetComponent("script.BattleUnit")
    enemyUnit.MoveSpeed = 0
    enemyUnit.RetargetInterval = 99
    enemyUnit:Configure("ENEMY", enemy.Name, "ASSAULT", 220, 0, 0, 99, 0.6, 99, 0.18, 0.6, 0, 2.0, Vector2(1.2, 1.2), 0.8, 0.2)
    table.insert(probes, enemy)
end
session.EnemyAlive = session.EnemyAlive + 2

_TimerService:SetTimerOnce(function()
    -- Trigger the first native contact, then wait a frame for HitEvent and session batch resolution.
    placeProbesAtTank()
    tankUnit:DriveAttack(tank, true)
    _TimerService:SetTimerOnce(function()
        -- First contact proves fixed 40 damage, two overlapping targets, semantic event emission, and no Tank recoil.
        local firstUnit = probes[1]:GetComponent("script.BattleUnit")
        local secondUnit = probes[2]:GetComponent("script.BattleUnit")
        check(firstUnit.Hp == 180 and secondUnit.Hp == 180, "first overlap damages both targets for 40")
        check(session.LastEvent == "DAMAGE" or session.LastEvent == "DEAD", "contact reaches the semantic damage event")
        local position = getProbePosition(tank)
        check(math.abs(position.x - initialPosition.x) < 0.001 and math.abs(position.y - initialPosition.y) < 0.001, "Tank does not recoil from contact")
        check(firstUnit.CombatState ~= "STUN" and secondUnit.CombatState ~= "STUN", "contact does not stun targets")
        check(firstUnit.CombatState == "ON_HIT" and secondUnit.CombatState == "ON_HIT", "damaged units hold ON_HIT for the hit-stop window")
        logProbeState("after-first-contact")

        -- Re-overlap before the cooldown expires; neither target may take a second hit.
        placeProbesAtTank()
        tankUnit:DriveAttack(tank, true)
        _TimerService:SetTimerOnce(function()
            local firstBefore = probes[1]:GetComponent("script.BattleUnit").Hp
            local secondBefore = probes[2]:GetComponent("script.BattleUnit").Hp
            check(firstBefore == 180 and secondBefore == 180, "per-target cooldown blocks repeat contact before 2 seconds")

            -- Retry after the full cooldown and wait for the next HitEvent batch.
            _TimerService:SetTimerOnce(function()
                placeProbesAtTank()
                tankUnit:DriveAttack(tank, true)
                _TimerService:SetTimerOnce(function()
                    local firstAfter = probes[1]:GetComponent("script.BattleUnit").Hp
                    local secondAfter = probes[2]:GetComponent("script.BattleUnit").Hp
                    check(firstAfter == 140 and secondAfter == 140, "both target cooldowns expire independently at 2 seconds")

                    -- Wait for the next cooldown before probing the arena boundary.
                    _TimerService:SetTimerOnce(function()
                        tankBody:SetWorldPosition(Vector2(session.ArenaMaxX - 0.5, 0))
                        for index, entity in ipairs(probes) do
                            local movement = entity:GetComponent("MovementComponent")
                            if isvalid(movement) then
                                movement.InputSpeed = 0
                                movement:Stop()
                            end
                            local offset = index == 1 and 0.1 or -0.1
                            entity:GetComponent("KinematicbodyComponent"):SetWorldPosition(Vector2(session.ArenaMaxX - 0.1 + offset, 0))
                        end
                        tankUnit:DriveAttack(tank, true)
                        _TimerService:SetTimerOnce(function()
                            -- The actual production knockback must move only enemies and clamp at ArenaMaxX.
                            local tankPosition = getProbePosition(tank)
                            check(math.abs(tankPosition.x - (session.ArenaMaxX - 0.5)) < 0.001, "Tank stays in place at the boundary probe")
                            for _, entity in ipairs(probes) do
                                local position = getProbePosition(entity)
                                check(position.x <= session.ArenaMaxX + 0.001, "enemy knockback is clamped to the arena boundary")
                            end
                            logProbeState("after-boundary-contact")
                            local firstAtResult = probes[1]:GetComponent("script.BattleUnit").Hp
                            local secondAtResult = probes[2]:GetComponent("script.BattleUnit").Hp
                            session:EnterResult("WIN")
                            placeProbesAtTank()
                            tankUnit:DriveAttack(tank, true)
                            _TimerService:SetTimerOnce(function()
                                -- The terminal phase must block future contact damage.
                                check(probes[1]:GetComponent("script.BattleUnit").Hp == firstAtResult and probes[2]:GetComponent("script.BattleUnit").Hp == secondAtResult, "RESULT blocks future contact damage")
                                logProbeState("after-result")
                                if failures == 0 then
                                    log("[M1][TankProbe] PASS")
                                else
                                    log_error("[M1][TankProbe] FAILURES=" .. tostring(failures))
                                end
                            end, 0.25)
                        end, 0.25)
                    end, 2.1)
                end, 0.25)
            end, 1.1)
        end, 1.0)
    end, 0.1)
end, 0.25)
