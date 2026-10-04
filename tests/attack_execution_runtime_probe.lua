-- Run in a fresh Maker Play test with context=server_main.
-- Every case prepares and starts a complete controlled battle before observing the production step.
local map = _EntityService:GetEntityByPath("/maps/map01")
local session = isvalid(map) and map:GetComponent("script.BattleSession") or nil
local failures = 0
local function check(condition, message)
    if condition then log("[M1][AttackExecutionProbe][PASS] " .. message)
    else failures = failures + 1; log_error("[M1][AttackExecutionProbe][FAIL] " .. message) end
end

local function row(monsterId, name, x, y, overrides)
    return { monsterId = monsterId, name = name, position = Vector3(x, y, 0), overrides = overrides }
end

local function activeProfile(impactDelay, attackInterval, attackDamage, maxHp)
    local result = {
        MoveSpeed = 0,
        RetargetIntervalSeconds = 0,
        ImpactDelaySeconds = impactDelay,
        AttackIntervalSeconds = attackInterval,
    }
    if attackDamage ~= nil then result.AttackDamage = attackDamage end
    if maxHp ~= nil then result.MaxHp = maxHp end
    return result
end

local function quietProfile(maxHp)
    local result = {
        MoveSpeed = 0,
        AttackDamage = 0,
        AttackRange = 0,
        RetargetIntervalSeconds = 0,
        ImpactDelaySeconds = 0.05,
        AttackIntervalSeconds = 100,
    }
    if maxHp ~= nil then result.MaxHp = maxHp end
    return result
end

local function consumeEnemyOpeningDelay(unit, target, label)
    unit:DriveAttack(target, true)
    session:AdvanceForTest(session.EnemyOpeningDelay + 0.02)
    check(unit.AttackSerial == 0, label .. " consumes the configured enemy opening delay before attacking")
end

local function catalogProfile(monsterId)
    local source = session:GetMonsterProfile(monsterId)
    if source == nil then return nil end
    local copy = {}
    for key, value in pairs(source) do copy[key] = value end
    return copy
end

local function getUnit(name)
    local entity = _EntityService:GetEntityByPath("/maps/map01/" .. name)
    if not isvalid(entity) then return nil, nil end
    return entity, entity:GetComponent("script.BattleUnit")
end

local function getAttack(entity)
    if not isvalid(entity) then return nil end
    return entity:GetComponent("script.BattleAttackComposition")
end

local function contains(value, fragment)
    return string.find(value or "", fragment, 1, true) ~= nil
end

local function samePosition(left, right)
    return math.abs(left.x - right.x) < 0.0001 and math.abs(left.y - right.y) < 0.0001
end

local function controlledCase(label, playerRoster, enemyRoster, callback)
    local acquireOk, acquired = pcall(function() return session:BeginManualSimulation() end)
    if not acquireOk then
        check(false, label .. " clock acquisition raised: " .. tostring(acquired))
        return false
    end
    if acquired ~= true then
        check(false, label .. " acquires its own manual clock")
        return false
    end

    local callOk, completed = pcall(function()
        local prepared = session:PrepareBattleForTest(playerRoster, enemyRoster)
        check(prepared == true, label .. " prepares a complete controlled roster")
        if prepared ~= true then return false end

        local expectedPlayers = #playerRoster
        local expectedEnemies = #enemyRoster
        check(session.PlayerAlive == expectedPlayers and session.EnemyAlive == expectedEnemies,
            label .. " registers every actor, target, decoy, and reserve")

        for _, roster in ipairs({ playerRoster, enemyRoster }) do
            for _, entry in ipairs(roster) do
                local entity, unit = getUnit(entry.name)
                check(isvalid(entity) and isvalid(unit), label .. " resolves prepared unit " .. entry.name)
                if not isvalid(entity) or not isvalid(unit) then return false end
                -- Keep autonomous acquisition inert; explicit intent still uses the installed adapter.
                unit.AttackRange = 0
                local movement = entity:GetComponent("MovementComponent")
                if isvalid(movement) then movement:Stop() end
            end
        end

        local started = session:TryStartBattle()
        check(started == true and session.Phase == "BATTLE"
            and session.InitialPlayerAlive == expectedPlayers and session.InitialEnemyAlive == expectedEnemies,
            label .. " starts with the prepared battle counts")
        if started ~= true then return false end

        callback()
        return true
    end)

    local releaseOk, releaseDetail = pcall(function() session:EndManualSimulation() end)
    if not releaseOk then
        check(false, label .. " clock release raised: " .. tostring(releaseDetail))
    end
    if not callOk then
        check(false, label .. " raised: " .. tostring(completed))
        return false
    end
    return completed == true
end

local runOk, runDetail = pcall(function()
if not isvalid(session) then
    check(false, "BattleSession unavailable")
    return
end

if session.BeginManualSimulation == nil or session.PrepareBattleForTest == nil then
    check(false, "controlled battle and manual clock interfaces are available")
    return
end

for _, kind in ipairs({ "monster_warrior", "monster_shooter" }) do
    local suffix = kind == "monster_warrior" and "Assault" or "Shooter"
    local actorName = "Issue16_AreaActor_" .. suffix
    local targetName = "Issue16_AreaTarget_" .. suffix
    local decoyName = "Issue16_AreaDecoy_" .. suffix
    if not controlledCase(suffix .. " native hit", {
        row(kind, actorName, -1, 0, activeProfile(0.18, 0.8)),
    }, {
        row("monster_warrior", targetName, -0.5, 0, quietProfile()),
        row("monster_warrior", decoyName, -0.5, 0.15, quietProfile()),
    }, function()
        local actorEntity, unit = getUnit(actorName)
        local targetEntity, target = getUnit(targetName)
        local _, decoy = getUnit(decoyName)
        local attack = getAttack(actorEntity)
        unit:DriveAttack(targetEntity, true)
        unit:DriveAttack(targetEntity, true)
        check(unit.AttackSerial == 1, suffix .. " accepts one attack intent")
        session:AdvanceForTest(0.05)
        check(target.Hp == 220 and target.DamageTakenSerial == 0,
            suffix .. " keeps target HP unchanged before impact")
        check(contains(session.EventHistory, "ATTACK_START:" .. actorEntity.Name), suffix .. " publishes attack start")
        session:AdvanceForTest(0.14)
        local expectedHp = kind == "monster_warrior" and 185 or 190
        local expectedDecoyHp = kind == "monster_warrior" and 185 or 220
        check(target.Hp == expectedHp and target.DamageTakenSerial == 1,
            suffix .. " applies the configured native HitEvent damage")
        check(decoy.Hp == expectedDecoyHp,
            suffix .. " preserves warrior area hits and shooter target lock")
        local hitAt = string.find(session.EventHistory, "HIT:" .. actorEntity.Name .. ":" .. targetName, 1, true)
        local targetHitAt = string.find(session.EventHistory, "TARGET_HIT:" .. actorEntity.Name .. ":" .. targetName, 1, true)
        local damageAt = string.find(session.EventHistory, "DAMAGE:" .. actorEntity.Name .. ":" .. targetName, 1, true)
        check(hitAt ~= nil and targetHitAt ~= nil and damageAt ~= nil
            and hitAt < targetHitAt and targetHitAt < damageAt,
            suffix .. " preserves ordered native hit and damage events")
        check(isvalid(actorEntity) and isvalid(attack), suffix .. " keeps its actor and installed attack composition")
    end) then return end
end

for _, kind in ipairs({ "monster_warrior", "monster_shooter" }) do
    local suffix = kind == "monster_warrior" and "Assault" or "Shooter"
    local actorName = "Issue16_CancelActor_" .. suffix
    local targetName = "Issue16_CancelTarget_" .. suffix
    if not controlledCase(suffix .. " cancellation", {
        row(kind, actorName, -1, 0, activeProfile(0.18, 0.8)),
    }, {
        row("monster_warrior", targetName, -0.5, 0, quietProfile()),
    }, function()
        local actor, unit = getUnit(actorName)
        local _, target = getUnit(targetName)
        unit:DriveAttack(_EntityService:GetEntityByPath("/maps/map01/" .. targetName), true)
        session:AdvanceForTest(0.05)
        unit:CancelAttack()
        session:AdvanceForTest(0.2)
        check(target.Hp == 220 and target.DamageTakenSerial == 0,
            suffix .. " cancellation removes an unaccepted hit")
        unit:DriveAttack(_EntityService:GetEntityByPath("/maps/map01/" .. targetName), true)
        local expectedSerial = kind == "monster_warrior" and 1 or 2
        check(unit.AttackSerial == expectedSerial,
            suffix .. " retains its existing ordinary cancellation cooldown")
        check(isvalid(actor), suffix .. " remains available after cancelling pending work")
    end) then return end
end

do
    local actorName = "Issue16_RangeActor"
    local targetName = "Issue16_RangeTarget"
    local reserveName = "Issue16_RangeReserve"
    if not controlledCase("shooter range cancellation", {
        row("monster_shooter", actorName, -1, 0, activeProfile(0.18, 0.8)),
    }, {
        row("monster_warrior", targetName, -0.5, 0, quietProfile()),
        row("monster_warrior", reserveName, 3.4, 1.4, quietProfile()),
    }, function()
        local actor, unit = getUnit(actorName)
        local targetEntity, target = getUnit(targetName)
        unit:DriveAttack(targetEntity, true)
        session:AdvanceForTest(0.05)
        targetEntity.KinematicbodyComponent:SetWorldPosition(Vector2(3.5, 0))
        session:AdvanceForTest(0.2)
        check(target.Hp == 220 and target.DamageTakenSerial == 0,
            "shooter leaving range cancels its unaccepted hit")
        targetEntity.KinematicbodyComponent:SetWorldPosition(Vector2(-0.5, 0))
        unit:DriveAttack(targetEntity, true)
        check(unit.AttackSerial == 2, "shooter can retry after leaving range")
        targetEntity.KinematicbodyComponent:SetWorldPosition(Vector2(3.5, 0))
        session:AdvanceForTest(0.2)
        check(target.Hp == 220 and target.DamageTakenSerial == 0,
            "second out-of-range attempt is cancelled without damaging the living target")
        check(isvalid(actor) and isvalid(getUnit(reserveName)), "the prepared reserve remains registered")
    end) then return end
end

do
    local actorName = "Issue16_ToleranceActor"
    local targetName = "Issue16_ToleranceTarget"
    if not controlledCase("warrior impact tolerance", {
        row("monster_warrior", actorName, -1, 0, activeProfile(0.18, 0.8)),
    }, {
        row("monster_warrior", targetName, -0.5, 0, quietProfile()),
    }, function()
        local actor, unit = getUnit(actorName)
        local targetEntity, target = getUnit(targetName)
        unit:DriveAttack(targetEntity, true)
        targetEntity.KinematicbodyComponent:SetWorldPosition(Vector2(-0.36, 0))
        session:AdvanceForTest(0.2)
        check(target.Hp == 185 and target.DamageTakenSerial == 1,
            "warrior keeps the 0.05 impact range tolerance")
        check(isvalid(actor), "warrior actor remains registered after impact")
    end) then return end
end

for _, kind in ipairs({ "monster_warrior", "monster_shooter" }) do
    local suffix = kind == "monster_warrior" and "Assault" or "Shooter"
    local actorName = "Issue16_ReconfigureActor_" .. suffix
    local targetName = "Issue16_ReconfigureTarget_" .. suffix
    if not controlledCase(suffix .. " same-adapter reconfiguration", {
        row(kind, actorName, -1, 0, activeProfile(0.18, 0.8)),
    }, {
        row("monster_warrior", targetName, -0.5, 0, quietProfile()),
    }, function()
        local actor, unit = getUnit(actorName)
        local targetEntity, target = getUnit(targetName)
        local attack = getAttack(actor)
        local data = catalogProfile(kind)
        unit:DriveAttack(targetEntity, true)
        session:AdvanceForTest(0.05)
        check(attack:Configure(data, 0), suffix .. " can reconfigure on its existing actor")
        session:AdvanceForTest(0.2)
        check(target.Hp == 220 and unit.AttackSerial == 1,
            suffix .. " discards pending work without rewinding observations")
        unit:DriveAttack(targetEntity, true)
        check(unit.AttackSerial == 2, suffix .. " accepts the replacement attack intent")
        session:AdvanceForTest(data.ImpactDelaySeconds + 0.02)
        local expectedHp = kind == "monster_warrior" and 185 or 190
        check(target.Hp == expectedHp and target.DamageTakenSerial == 1,
            suffix .. " delivers the replacement attack through the full session step")
    end) then return end
end

do
    local actorName = "Issue16_AdapterActor"
    local targetName = "Issue16_AdapterTarget"
    if not controlledCase("attack adapter replacement", {
        row("monster_shooter", actorName, -1, 0, activeProfile(0.18, 0.8)),
    }, {
        row("monster_warrior", targetName, -0.5, 0, quietProfile()),
    }, function()
        local actor, unit = getUnit(actorName)
        local targetEntity, target = getUnit(targetName)
        local attack = getAttack(actor)
        local warrior = catalogProfile("monster_warrior")
        unit:DriveAttack(targetEntity, true)
        check(attack:Configure(warrior, 0) and unit.UnitKind == "ASSAULT",
            "same actor can replace its shooter adapter with the warrior adapter")
        session:AdvanceForTest(0.2)
        check(target.Hp == 220 and unit.AttackSerial == 1,
            "adapter replacement cancels the unaccepted shot")
        unit:DriveAttack(targetEntity, true)
        session:AdvanceForTest(warrior.ImpactDelaySeconds + 0.02)
        check(target.Hp == 185 and target.DamageTakenSerial == 1 and unit.AttackSerial == 2,
            "replacement adapter alone delivers its native area hit")
    end) then return end
end

do
    local actorName = "Issue16_TankSwitchActor"
    local firstTargetName = "Issue16_TankSwitchTarget"
    local replacementName = "Issue16_TankSwitchReplacement"
    if not controlledCase("tank and shooter adapter switch", {
        row("monster_shooter", actorName, -1, 0, activeProfile(0.18, 0.8)),
    }, {
        row("monster_warrior", firstTargetName, -0.5, 0, quietProfile()),
        row("monster_warrior", replacementName, 3.4, 1.4, quietProfile()),
    }, function()
        local actor, unit = getUnit(actorName)
        local firstTargetEntity, firstTarget = getUnit(firstTargetName)
        local replacementEntity, replacement = getUnit(replacementName)
        local attack = getAttack(actor)
        local tank = catalogProfile("monster_tank")
        local shooter = catalogProfile("monster_shooter")
        check(attack:Configure(tank, 0) and unit.UnitKind == "TANK",
            "switch to tank updates installed attack classification")
        unit:DriveAttack(nil, false)
        session:AdvanceForTest(0.02)
        check(firstTarget.Hp == 180 and firstTarget.DamageTakenSerial == 1 and firstTarget.KnockbackActive,
            "reconfigured tank preserves contact damage and native knockback")
        check(attack:Configure(shooter, 0) and unit.UnitKind == "SHOOTER",
            "switch from tank restores shooter classification")
        replacementEntity.KinematicbodyComponent:SetWorldPosition(Vector2(-0.5, 0))
        unit:DriveAttack(replacementEntity, true)
        session:AdvanceForTest(shooter.ImpactDelaySeconds + 0.02)
        check(replacement.Hp == 190 and replacement.DamageTakenSerial == 1
            and not replacement.KnockbackActive,
            "reconfigured shooter delivers hitscan damage without tank knockback")
    end) then return end
end

do
    local actorName = "Issue16_RecoveryActor"
    local targetName = "Issue16_RecoveryTarget"
    local decoyName = "Issue16_RecoveryDecoy"
    if not controlledCase("invalid configuration recovery", {
        row("monster_shooter", actorName, -1, 0, activeProfile(0.18, 0.8)),
    }, {
        row("monster_warrior", targetName, -0.5, 0, quietProfile()),
        row("monster_warrior", decoyName, -0.5, 0.15, quietProfile()),
    }, function()
        local actor, unit = getUnit(actorName)
        local targetEntity, target = getUnit(targetName)
        local _, decoy = getUnit(decoyName)
        local attack = getAttack(actor)
        local shooter = catalogProfile("monster_shooter")
        local warrior = catalogProfile("monster_warrior")
        unit:DriveAttack(targetEntity, true)
        check(attack:Configure({ MonsterType = "INVALID" }, 0) == false,
            "invalid attack configuration is rejected explicitly")
        session:AdvanceForTest(1)
        unit:DriveAttack(targetEntity, true)
        check(target.Hp == 220 and unit.AttackSerial == 1,
            "rejected configuration leaves no active attack work")
        check(attack:Configure(warrior, 0), "configuration recovers with another native adapter")
        unit:DriveAttack(targetEntity, true)
        session:AdvanceForTest(warrior.ImpactDelaySeconds + 0.02)
        check(target.Hp == 185 and decoy.Hp == 185
            and target.DamageTakenSerial == 1 and decoy.DamageTakenSerial == 1,
            "recovered warrior preserves area hits after rejected shooter configuration")
        check(shooter.MonsterType == "SHOOTER", "recovery fixture came from the shooter catalog profile")
    end) then return end
end

do
    local actorName = "Issue16_FrozenShooter"
    local targetName = "Issue16_FrozenShooterTarget"
    local reserveName = "Issue16_FrozenShooterReserve"
    if not controlledCase("accepted shooter hit survives reconfiguration", {
        row("monster_shooter", actorName, -1, 0, activeProfile(0.18, 0.8)),
    }, {
        row("monster_warrior", targetName, 1.5, 0, quietProfile()),
        row("monster_warrior", reserveName, 3.4, 1.4, quietProfile()),
    }, function()
        local actor, unit = getUnit(actorName)
        local targetEntity, target = getUnit(targetName)
        local attack = getAttack(actor)
        local shooter = catalogProfile("monster_shooter")
        local tank = catalogProfile("monster_tank")
        local acceptedEffect = unit:GetHitEffectRUID()
        unit:DriveAttack(targetEntity, true)
        -- Emit one real adapter HitEvent; the following AdvanceForTest applies the complete damage batch.
        unit:AdvanceAttack(0.2)
        check(unit.AttackSerial == 1 and target.Hp == 220,
            "native shooter hit is accepted before the session batch is advanced")
        check(attack:Configure(tank, 0) and unit.UnitKind == "TANK",
            "accepted shooter hit can be followed by an adapter replacement")
        unit:SetMonsterIdentity(unit.MonsterId, unit.MonsterName, "")
        session:AdvanceForTest(0.02)
        check(target.Hp == 190 and target.DamageTakenSerial == 1,
            "accepted shooter damage survives replacement before full-step resolution")
        check(acceptedEffect ~= "" and target.HitEffectSerial == 1
            and target.LastHitEffectRUID == acceptedEffect and target.CombatState == "ON_HIT",
            "accepted shooter hit retains its captured hit effect and hit-stop policy")
        check(shooter.MonsterType == "SHOOTER", "accepted policy starts from the shooter catalog profile")
    end) then return end
end

do
    local actorName = "Issue16_FrozenTank"
    local targetName = "Issue16_FrozenTankTarget"
    local reserveName = "Issue16_FrozenTankReserve"
    if not controlledCase("accepted tank hit survives reconfiguration", {
        row("monster_tank", actorName, -1, 0, activeProfile(0.18, 2)),
    }, {
        row("monster_warrior", targetName, -0.5, 0, quietProfile()),
        row("monster_warrior", reserveName, 3.4, 1.4, quietProfile()),
    }, function()
        local actor, unit = getUnit(actorName)
        local _, target = getUnit(targetName)
        local attack = getAttack(actor)
        local shooter = catalogProfile("monster_shooter")
        local shooterEffect = shooter.HitEffectRUID
        unit:SetMonsterIdentity(unit.MonsterId, unit.MonsterName, shooterEffect)
        unit:DriveAttack(nil, false)
        check(unit.AttackSerial == 1 and target.Hp == 220,
            "native tank contact is accepted before the session batch is advanced")
        check(attack:Configure(shooter, 0) and unit.UnitKind == "SHOOTER",
            "accepted tank contact can be followed by an adapter replacement")
        session:AdvanceForTest(0.02)
        check(target.Hp == 180 and target.DamageTakenSerial == 1 and target.KnockbackActive,
            "accepted tank contact retains damage and queued knockback")
        check(target.HitEffectSerial == 0 and target.CombatState ~= "ON_HIT",
            "accepted tank contact retains its no-hit-effect and no-hit-stop policy")
    end) then return end
end

do
    local actorName = "Issue16_HitStopActor"
    local targetName = "Issue16_HitStopTarget"
    local hitterName = "Issue16_HitStopHitter"
    if not controlledCase("hit stop blocks new intent but advances accepted work", {
        row("monster_shooter", actorName, -1, 0, activeProfile(0.18, 0.01)),
    }, {
        row("monster_warrior", targetName, -0.5, 0, quietProfile()),
        row("monster_shooter", hitterName, -1, 0.15, activeProfile(0.01, 2, 1)),
    }, function()
        local actorEntity, actor = getUnit(actorName)
        local targetEntity, target = getUnit(targetName)
        local hitterEntity, hitter = getUnit(hitterName)
        consumeEnemyOpeningDelay(hitter, actorEntity, "hit-stop enemy shooter")
        actor:DriveAttack(targetEntity, true)
        hitter:DriveAttack(actorEntity, true)
        session:AdvanceForTest(0.02)
        check(actor.DamageTakenSerial == 1 and actor.CombatState == "ON_HIT",
            "opposing native hit starts actor hit stop")
        actor.AttackRange = 4
        session:AdvanceForTest(0.16)
        check(target.Hp == 190 and target.DamageTakenSerial == 1,
            "already pending attack advances through hit stop and applies its HitEvent")
        check(actor.AttackSerial == 1,
            "hit stop blocks a new automatic attack intent during the accepted strike")
        check(contains(session.EventHistory, "DAMAGE:" .. hitterEntity.Name .. ":" .. actorEntity.Name)
            and contains(session.EventHistory, "DAMAGE:" .. actorEntity.Name .. ":" .. targetEntity.Name),
            "both opposing and outgoing damage events remain observable")
    end) then return end
end

do
    local actorName = "Issue16_BatchActor"
    local playerReserveName = "Issue16_BatchPlayerReserve"
    local targetName = "Issue16_BatchTarget"
    local killerName = "Issue16_BatchKiller"
    local enemyReserveName = "Issue16_BatchEnemyReserve"
    if not controlledCase("accepted hit survives same-batch attacker death", {
        row("monster_shooter", killerName, -1, 0, activeProfile(0.01, 2, 30)),
        row("monster_warrior", targetName, -0.4, 0.3, quietProfile(30)),
        row("monster_tank", playerReserveName, -4, 1.4, quietProfile()),
    }, {
        row("monster_shooter", actorName, -0.5, 0, activeProfile(0.01, 2, 30, 30)),
        row("monster_tank", enemyReserveName, 3.4, 1.4, quietProfile()),
    }, function()
        local actorEntity, actor = getUnit(actorName)
        local _, playerReserve = getUnit(playerReserveName)
        local targetEntity, target = getUnit(targetName)
        local killerEntity, killer = getUnit(killerName)
        local _, enemyReserve = getUnit(enemyReserveName)
        local acceptedEffect = actor:GetHitEffectRUID()

        consumeEnemyOpeningDelay(actor, targetEntity, "same-batch dying shooter")
        killer:DriveAttack(actorEntity, true)
        actor:DriveAttack(targetEntity, true)
        session:AdvanceForTest(0.05)

        check(actor.AttackSerial == 1 and killer.AttackSerial == 1,
            "both lethal native attacks are accepted in the same full battle step")
        check(actor.IsDead and actor.Hp == 0 and actor.DamageTakenSerial == 1,
            "the first resolved HitEvent kills the accepted shooter before its outgoing hit settles")
        check(target.IsDead and target.Hp == 0 and target.DamageTakenSerial == 1,
            "the shooter's already accepted hit still resolves after its death")
        check(acceptedEffect ~= "" and target.HitEffectSerial == 1
            and target.LastHitEffectRUID == acceptedEffect,
            "same-batch shooter death preserves the accepted hit's captured effect policy")
        check(playerReserve:IsAlive() and enemyReserve:IsAlive()
            and session.Phase == "BATTLE" and session.Result == "",
            "live reserves keep the legitimate post-death battle observable")
        local killerDamageAt = string.find(session.EventHistory,
            "DAMAGE:" .. killerEntity.Name .. ":" .. actorEntity.Name, 1, true)
        local attackerDeathAt = string.find(session.EventHistory, "DEAD:" .. actorEntity.Name, 1, true)
        local outgoingHitAt = string.find(session.EventHistory,
            "DAMAGE:" .. actorEntity.Name .. ":" .. targetName, 1, true)
        check(killerDamageAt ~= nil and attackerDeathAt ~= nil and outgoingHitAt ~= nil
            and killerDamageAt < attackerDeathAt and attackerDeathAt < outgoingHitAt
            and contains(session.EventHistory, "DAMAGE:" .. actorEntity.Name .. ":" .. targetName)
            and contains(session.EventHistory, "DEAD:" .. actorEntity.Name)
            and contains(session.EventHistory, "DEAD:" .. targetName),
            "the accepted outgoing damage event follows its attacker's same-batch death event")
    end) then return end
end

do
    local actorName = "Issue16_DyingActor"
    local reserveName = "Issue16_DyingActorReserve"
    local targetName = "Issue16_DyingActorTarget"
    local killerName = "Issue16_DyingActorKiller"
    if not controlledCase("attacker death cancels unresolved shot", {
        row("monster_shooter", actorName, -1, 0, activeProfile(0.18, 0.8, 30, 30)),
        row("monster_tank", reserveName, -4, 1.4, quietProfile()),
    }, {
        row("monster_warrior", targetName, 1.5, 0, quietProfile()),
        row("monster_shooter", killerName, -0.5, 0.2, activeProfile(0.01, 2, 30)),
    }, function()
        local actorEntity, actor = getUnit(actorName)
        local _, reserve = getUnit(reserveName)
        local targetEntity, target = getUnit(targetName)
        local killerEntity, killer = getUnit(killerName)
        consumeEnemyOpeningDelay(killer, actorEntity, "pending-shot killer")
        actor:DriveAttack(targetEntity, true)
        killer:DriveAttack(actorEntity, true)
        session:AdvanceForTest(0.05)
        check(actor.IsDead and actor.Hp == 0 and actor.DamageTakenSerial == 1,
            "enemy attack kills the pending shooter through the battle step")
        check(reserve:IsAlive() and session.Phase == "BATTLE" and session.Result == "",
            "prepared player reserve keeps observation in BATTLE after actor death")
        session:AdvanceForTest(0.25)
        check(target.Hp == 220 and target.DamageTakenSerial == 0 and actor.AttackSerial == 1,
            "dead attacker cannot resolve its unaccepted shot")
        check(contains(session.EventHistory, "DAMAGE:" .. killerEntity.Name .. ":" .. actorEntity.Name)
            and not contains(session.EventHistory, "RESULT"),
            "death is recorded without forcing a terminal result")
    end) then return end
end

do
    local actorName = "Issue16_TargetDeathShooter"
    local killerName = "Issue16_TargetDeathKiller"
    local targetName = "Issue16_DyingTarget"
    local reserveName = "Issue16_DyingTargetReserve"
    if not controlledCase("target death cancels pending shooter hit", {
        row("monster_shooter", actorName, -1, 0, activeProfile(0.18, 0.8)),
        row("monster_warrior", killerName, 0, 0, activeProfile(0.01, 2, 35)),
    }, {
        row("monster_warrior", targetName, 0.3, 0, quietProfile(35)),
        row("monster_tank", reserveName, 3.4, 1.4, quietProfile()),
    }, function()
        local shooterEntity, shooter = getUnit(actorName)
        local killerEntity, killer = getUnit(killerName)
        local _, target = getUnit(targetName)
        local _, reserve = getUnit(reserveName)
        local targetEntity = _EntityService:GetEntityByPath("/maps/map01/" .. targetName)
        shooter:DriveAttack(targetEntity, true)
        killer:DriveAttack(targetEntity, true)
        session:AdvanceForTest(0.05)
        check(target.IsDead and target.Hp == 0 and target.DamageTakenSerial == 1,
            "warrior attack kills the selected target before shooter impact")
        check(reserve:IsAlive() and session.Phase == "BATTLE" and session.Result == "",
            "prepared enemy reserve keeps observation in BATTLE after target death")
        session:AdvanceForTest(0.2)
        check(target.DamageTakenSerial == 1 and shooter.AttackSerial == 1,
            "shooter does not deliver another native hit to the dead target")
        check(isvalid(shooterEntity) and isvalid(killerEntity)
            and contains(session.EventHistory, "DAMAGE:" .. killerEntity.Name .. ":" .. targetName),
            "target death retains its legitimate attack and semantic damage event")
    end) then return end
end

do
    local actorName = "Issue16_TankMultiActor"
    local firstName = "Issue16_TankMultiFirst"
    local secondName = "Issue16_TankMultiSecond"
    local thirdName = "Issue16_TankMultiThird"
    if not controlledCase("tank multi-target contact cooldowns", {
        row("monster_tank", actorName, -1, 0, activeProfile(0.18, 2)),
    }, {
        row("monster_warrior", firstName, -0.5, 0, quietProfile()),
        row("monster_warrior", secondName, -1, 0.3, quietProfile()),
        row("monster_warrior", thirdName, 3.4, 1.4, quietProfile()),
    }, function()
        local actor, unit = getUnit(actorName)
        local _, first = getUnit(firstName)
        local _, second = getUnit(secondName)
        local thirdEntity, third = getUnit(thirdName)
        unit:DriveAttack(nil, false)
        session:AdvanceForTest(0.02)
        check(first.Hp == 180 and second.Hp == 180 and third.Hp == 220
            and unit.AttackSerial == 2,
            "one tank contact announces and damages each in-range defender")
        unit:DriveAttack(nil, false)
        session:AdvanceForTest(0.02)
        check(first.Hp == 180 and second.Hp == 180 and unit.AttackSerial == 2,
            "each defender keeps its own contact cooldown")
        thirdEntity.KinematicbodyComponent:SetWorldPosition(Vector2(-0.8, 0.2))
        unit:DriveAttack(nil, false)
        session:AdvanceForTest(0.02)
        check(third.Hp == 180 and third.DamageTakenSerial == 1 and unit.AttackSerial == 3,
            "a new defender is not blocked by other targets' cooldowns")
        check(isvalid(actor), "tank actor remains registered after multiple contacts")
    end) then return end
end

for _, kind in ipairs({ "monster_warrior", "monster_shooter" }) do
    local suffix = kind == "monster_warrior" and "Assault" or "Shooter"
    local actorName = "Issue16_OpeningActor_" .. suffix
    local targetName = "Issue16_OpeningTarget_" .. suffix
    if not controlledCase(suffix .. " opening delay", {
        row(kind, actorName, -1, 0, activeProfile(0.18, 0.8)),
    }, {
        row("monster_warrior", targetName, -0.5, 0, quietProfile()),
    }, function()
        local actor, unit = getUnit(actorName)
        local targetEntity, target = getUnit(targetName)
        local attack = getAttack(actor)
        local data = catalogProfile(kind)
        check(attack:Configure(data, 0.12), suffix .. " accepts the configured opening delay")
        unit:DriveAttack(targetEntity, true)
        check(unit.AttackSerial == 0, suffix .. " does not announce before opening delay elapses")
        session:AdvanceForTest(0.05)
        unit:DriveAttack(targetEntity, true)
        check(unit.AttackSerial == 0, suffix .. " keeps the opening delay during early steps")
        session:AdvanceForTest(0.08)
        unit:DriveAttack(targetEntity, true)
        check(unit.AttackSerial == 1, suffix .. " consumes the opening delay once")
        session:AdvanceForTest(data.ImpactDelaySeconds + 0.02)
        local expectedHp = kind == "monster_warrior" and 185 or 190
        check(target.Hp == expectedHp and target.DamageTakenSerial == 1,
            suffix .. " performs the first attack after its opening delay")
    end) then return end
end

do
    local actorName = "Issue16_TerminalActor"
    local targetName = "Issue16_TerminalTarget"
    if not controlledCase("natural WIN terminal boundary", {
        row("monster_shooter", actorName, -1, 0, activeProfile(0.18, 0.8)),
    }, {
        row("monster_warrior", targetName, -0.5, 0, quietProfile(30)),
    }, function()
        local actorEntity, actor = getUnit(actorName)
        local targetEntity, target = getUnit(targetName)
        local actorBefore = actorEntity.TransformComponent.WorldPosition
        local targetBeforeHp = target.Hp
        actor:DriveAttack(targetEntity, true)
        session:AdvanceForTest(0.05)
        check(target.Hp == targetBeforeHp and actor.AttackSerial == 1,
            "terminal target remains alive before the lethal attack impact")
        session:AdvanceForTest(0.14)
        check(session.Phase == "RESULT" and session.Result == "WIN",
            "legal native lethal damage produces the actual WIN result")
        check(target.Hp == 0 and target.IsDead and target.DamageTakenSerial == 1,
            "terminal target records the applied lethal HitEvent")
        check(contains(session.EventHistory, "DAMAGE:" .. actorEntity.Name .. ":" .. targetName)
            and contains(session.EventHistory, "DEAD:" .. targetName)
            and session.LastEvent == "RESULT",
            "terminal damage, death, and result semantic events are published")

        local attackSerial = actor.AttackSerial
        local targetHp = target.Hp
        local damageSerial = target.DamageTakenSerial
        local eventSerial = session.EventSerial
        local eventHistory = session.EventHistory
        local actorPosition = actorEntity.TransformComponent.WorldPosition
        local targetPosition = targetEntity.TransformComponent.WorldPosition
        actor:DriveAttack(targetEntity, true)
        session:AdvanceForTest(0.5)
        local actorAfter = actorEntity.TransformComponent.WorldPosition
        local targetAfter = targetEntity.TransformComponent.WorldPosition
        check(actor.AttackSerial == attackSerial and target.Hp == targetHp
            and target.DamageTakenSerial == damageSerial,
            "terminal WIN blocks later attack and damage changes")
        check(session.EventSerial == eventSerial and session.EventHistory == eventHistory,
            "terminal WIN blocks later semantic combat events")
        check(samePosition(actorPosition, actorAfter) and samePosition(targetPosition, targetAfter)
            and samePosition(actorBefore, actorAfter),
            "terminal WIN leaves actor and defeated target positions stable")
    end) then return end
end

end)
if not runOk then check(false, "attack execution probe raised: " .. tostring(runDetail)) end

if failures == 0 then
    log("[M1][AttackExecutionProbe] PASS")
else
    log_error("[M1][AttackExecutionProbe] FAILURES=" .. tostring(failures))
end
