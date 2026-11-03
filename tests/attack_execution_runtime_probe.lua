-- Run in a fresh Maker Play test with context=server_main.
-- Every case prepares and starts a complete controlled battle before observing the production step.
local map = _EntityService:GetEntityByPath("/maps/template")
local session = isvalid(map) and map:GetComponent("script.BattleSession") or nil
local failures = 0
local function check(condition, message)
    if condition then log("[M1][AttackExecutionProbe][PASS] " .. message)
    else failures = failures + 1; log_error("[M1][AttackExecutionProbe][FAIL] " .. message) end
end

local function row(monsterId, name, x, y, overrides)
    overrides = overrides or {}
    local damage = ({ monster_tank = 40, monster_warrior = 35, monster_shooter = 30 })[monsterId]
    if overrides.AttackDamageMin == nil then overrides.AttackDamageMin = damage end
    if overrides.AttackDamageMax == nil then overrides.AttackDamageMax = damage end
    if monsterId == "monster_tank" and overrides.MaxHp == nil then overrides.MaxHp = 500 end
    return { monsterId = monsterId, name = name, position = Vector3(x, y, 0), overrides = overrides }
end

local function activeProfile(impactDelay, attackInterval, attackDamage, maxHp)
    local result = {
        MoveSpeed = 0,
        RetargetIntervalSeconds = 0,
        ImpactDelaySeconds = impactDelay,
        AttackIntervalSeconds = attackInterval,
    }
    if attackDamage ~= nil then result.AttackDamageMin = attackDamage; result.AttackDamageMax = attackDamage end
    if maxHp ~= nil then result.MaxHp = maxHp end
    return result
end

local function quietProfile(maxHp)
    local result = {
        MoveSpeed = 0,
        AttackDamageMin = 0, AttackDamageMax = 0,
        RetargetIntervalSeconds = 0,
        ImpactDelaySeconds = 0.05,
        AttackIntervalSeconds = 100,
    }
    if maxHp ~= nil then result.MaxHp = maxHp end
    return result
end

local function consumeEnemyOpeningDelay(unit, target, label)
    unit:DriveAttack(target, true)
    unit:AdvanceAttack(session.EnemyOpeningDelay + 0.02)
    check(unit.AttackSerial == 0, label .. " consumes the configured enemy opening delay before attacking")
end

local function catalogProfile(monsterId)
    local source = session:GetMonsterProfile(monsterId)
    if source == nil then return nil end
    local copy = {}
    for key, value in pairs(source) do copy[key] = value end
    -- Pin controlled contact damage independently of the formal catalog's balance.
    local damage = ({ monster_tank = 40, monster_warrior = 35, monster_shooter = 30 })[monsterId]
    copy.AttackDamageMin = damage
    copy.AttackDamageMax = damage
    return copy
end

local function getUnit(name)
    local entity = _EntityService:GetEntityByPath("/maps/template/" .. name)
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
                -- Long fixture intervals prevent repeated autonomous attacks during observation.
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

-- Exact binary fractions keep contact/separation cases independent of float rounding.
for _, kind in ipairs({ "monster_warrior", "monster_shooter" }) do
    for _, direction in ipairs({ 1, -1 }) do
        for _, edge in ipairs({
            { "X touch", 0.75, 0, true }, { "X separated", 0.751, 0, false },
            { "Y upper touch", 0.5, 0.75, true }, { "Y upper separated", 0.5, 0.751, false },
            { "Y lower touch", 0.5, -0.75, true }, { "Y lower separated", 0.5, -0.751, false },
            { "corner touch", 0.75, 0.75, true },
        }) do
            local profile = activeProfile(0.015625, 100, 35)
            profile.AttackRange = 0.625
            profile.AttackRangeY = 0.5
            local label = kind .. " " .. tostring(direction) .. " " .. edge[1]
            if not controlledCase(label, { row(kind, "BoundaryActor", 0, 0, profile) }, {
                row("monster_warrior", "BoundaryTarget", direction * edge[2], edge[3], quietProfile()),
            }, function()
                local source, actor = getUnit("BoundaryActor")
                local targetEntity, target = getUnit("BoundaryTarget")
                for _, entity in ipairs({ source, targetEntity }) do
                    entity.HitComponent.ColliderOffset = Vector2(0.0625, 0.25)
                    entity.HitComponent.BoxSize = Vector2(0.5, 0.5)
                    entity.KinematicbodyComponent.Enable = false
                end
                target:FaceDirection(-direction)
                session:AdvanceForTest(0.001)
                check(actor.AttackSerial == (edge[4] and 1 or 0), label .. " movement and engagement agree")
                -- Even an explicit in-range hint cannot bypass the shared overlap query.
                actor:DriveAttack(targetEntity, true)
                session:AdvanceForTest(0.016)
                check(target.Hp == (edge[4] and 185 or 220), label .. " agrees with native impact")
            end) then return end
        end
    end
end

for _, kind in ipairs({ "monster_warrior", "monster_shooter" }) do
    local profile = activeProfile(0.125, 100, 35)
    if not controlledCase(kind .. " long frame facing", { row(kind, "HitchActor", 0, 0, profile) }, {
        row("monster_warrior", "HitchTarget", 0.5, 0, quietProfile()),
    }, function()
        local source, actor = getUnit("HitchActor")
        local targetEntity, target = getUnit("HitchTarget")
        actor:DriveAttack(targetEntity, true)
        local facing = source.TransformComponent.Scale.x
        targetEntity.KinematicbodyComponent:SetWorldPosition(Vector2(-0.5, 0))
        local elapsed = actor.AttackAnimationDuration + 0.01
        actor:Tick(elapsed)
        check(source.TransformComponent.Scale.x == facing,
            kind .. " long frame holds facing before resolving the crossed impact deadline")
        actor:AdvanceAttack(elapsed)
        session:AdvanceForTest(0.001)
        check(target.Hp == 220 and target.DamageTakenSerial == 0,
            kind .. " long frame cannot turn a behind-target miss into a hit")
    end) then return end
end

for _, kind in ipairs({ "monster_warrior", "monster_shooter" }) do
    local profile = activeProfile(0.125, 100, 35)
    if not controlledCase(kind .. " fixed attack facing", { row(kind, "FacingActor", 0, 0, profile) }, {
        row("monster_warrior", "FacingTarget", 0.5, 0, quietProfile()),
    }, function()
        local source, actor = getUnit("FacingActor")
        local targetEntity, target = getUnit("FacingTarget")
        session:AdvanceForTest(0.01)
        local facing = source.TransformComponent.Scale.x
        local start = source.TransformComponent.WorldPosition
        targetEntity.KinematicbodyComponent:SetWorldPosition(Vector2(-0.5, 0))
        actor:FaceTarget(targetEntity)
        session:AdvanceForTest(0.14)
        check(actor.AttackSerial == 1 and target.Hp == 220 and source.TransformComponent.Scale.x == facing,
            kind .. " cannot hit behind or turn at the impact frame")
        check(samePosition(start, source.TransformComponent.WorldPosition), kind .. " does not pursue during animation")
        session:AdvanceForTest(actor.AttackAnimationDuration)
        check(source.TransformComponent.Scale.x == -facing,
            kind .. " resumes facing the target after animation")
    end) then return end
end

-- A target collider reaches beyond its transform point at the front edge.
for _, kind in ipairs({ "monster_warrior", "monster_shooter" }) do
    local profile = activeProfile(0.01, 100, 35)
    profile.AttackRange = 0.6
    if not controlledCase(kind .. " frontal collider edge", {
        row(kind, "EdgeActor", -1, 0, profile),
    }, {
        row("monster_warrior", "EdgeTarget", -0.185, 0, quietProfile()),
    }, function()
        local actorEntity, actor = getUnit("EdgeActor")
        local targetEntity, target = getUnit("EdgeTarget")
        actor:DriveAttack(targetEntity, true)
        session:AdvanceForTest(0.02)
        check(target.Hp == 185 and target.DamageTakenSerial == 1,
            kind .. " native hit includes the collider at the frontal edge")
    end) then return end
end

for _, kind in ipairs({ "monster_warrior", "monster_shooter", "monster_tank" }) do
    local randomProfile = activeProfile(0.01, 100, nil, 10000)
    randomProfile.AttackDamageMin = 8
    randomProfile.AttackDamageMax = 9
    if not controlledCase(kind .. " random damage", {
        row(kind, "RangeActor", -1, 0, randomProfile),
    }, {
        row("monster_warrior", "RangeTarget", -0.5, 0, quietProfile(10000)),
        row("monster_warrior", "RangeDecoy", -0.5, 0.15, quietProfile(10000)),
    }, function()
        local actor, unit = getUnit("RangeActor")
        local targetEntity, target = getUnit("RangeTarget")
        local decoyEntity, decoy = getUnit("RangeDecoy")
        -- Hold native physics while the manual clock tests damage independently of tank knockback.
        targetEntity.KinematicbodyComponent.Enable = false
        decoyEntity.KinematicbodyComponent.Enable = false
        local nativeDamage = nil
        local connection = targetEntity:ConnectEvent(HitEvent, function(event) nativeDamage = event.TotalDamage end)
        local seen, independent = {}, false
        for index = 1, 32 do
            targetEntity.KinematicbodyComponent:SetWorldPosition(Vector2(-0.5, 0))
            decoyEntity.KinematicbodyComponent:SetWorldPosition(Vector2(-0.5, 0.15))
            local before, beforeDecoy = target.Hp, decoy.Hp
            if index > 1 then
                unit:Tick(unit.AttackAnimationDuration + 0.01)
                unit:AdvanceAttack(101)
            end
            unit:DriveAttack(targetEntity, true)
            session:AdvanceForTest(0.02)
            local damage = before - target.Hp
            local decoyDamage = beforeDecoy - decoy.Hp
            check(damage >= 8 and damage <= 9 and damage % 1 == 0, kind .. " draws an integer in range")
            seen[damage] = true
            check(contains(session.EventHistory, "HIT:" .. actor.Name .. ":RangeTarget:" .. tostring(damage))
                and contains(session.EventHistory, "DAMAGE:" .. actor.Name .. ":RangeTarget:" .. tostring(damage))
                and nativeDamage == damage, "native display damage, hit events and HP share the same draw")
            if kind ~= "monster_tank" then
                check(decoyDamage == 0, kind .. " keeps its target lock")
            else
                check(decoyDamage >= 8 and decoyDamage <= 9, "area target receives its own in-range damage")
                if damage ~= decoyDamage then independent = true end
            end
        end
        local count = 0
        for _ in pairs(seen) do count = count + 1 end
        check(count > 1 and seen[8] and seen[9], kind .. " draws vary and include both endpoints")
        check(kind ~= "monster_tank" or independent, "area targets do not share a single damage draw")
        targetEntity:DisconnectEvent(HitEvent, connection)
    end) then return end
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
        check(target.Hp == expectedHp and target.DamageTakenSerial == 1,
            suffix .. " applies the configured native HitEvent damage")
        check(decoy.Hp == 220 and decoy.DamageTakenSerial == 0,
            suffix .. " hits only its locked target, not the enemy beside it")
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
        unit:DriveAttack(_EntityService:GetEntityByPath("/maps/template/" .. targetName), true)
        session:AdvanceForTest(0.05)
        unit:CancelAttack()
        unit:AdvanceAttack(0.2)
        session:AdvanceForTest(0.001)
        check(target.Hp == 220 and target.DamageTakenSerial == 0,
            suffix .. " cancellation removes an unaccepted hit")
        unit:DriveAttack(_EntityService:GetEntityByPath("/maps/template/" .. targetName), true)
        check(unit.AttackSerial == 2,
            suffix .. " stopping clears the interval regardless of attack type")
        check(isvalid(actor), suffix .. " remains available after cancelling pending work")
    end) then return end
end

for _, kind in ipairs({ "monster_warrior", "monster_shooter" }) do
    local suffix = kind == "monster_warrior" and "Assault" or "Shooter"
    local actorName = "Issue57_LeaveActor_" .. suffix
    local targetName = "Issue57_LeaveTarget_" .. suffix
    local decoyName = "Issue57_LeaveDecoy_" .. suffix
    if not controlledCase(suffix .. " locked target leaves", {
        row(kind, actorName, -1, 0, activeProfile(0.01, 100)),
    }, {
        row("monster_warrior", targetName, -0.5, 0, quietProfile()),
        row("monster_warrior", decoyName, -0.5, 0.15, quietProfile()),
    }, function()
        local _, unit = getUnit(actorName)
        local targetEntity, target = getUnit(targetName)
        local _, decoy = getUnit(decoyName)
        unit:DriveAttack(targetEntity, true)
        targetEntity.KinematicbodyComponent:SetWorldPosition(Vector2(3.5, 0))
        session:AdvanceForTest(0.03)
        check(target.Hp == 220 and target.DamageTakenSerial == 0,
            suffix .. " whiffs when the locked target left before impact")
        check(decoy.Hp == 220 and decoy.DamageTakenSerial == 0,
            suffix .. " does not switch to another enemy still in range")
        check(unit.AttackSerial == 1 and unit.AttackPoiseActive,
            suffix .. " whiff keeps one attack playing its animation")
        session:AdvanceForTest(math.max(0, unit.AttackAnimationDuration - 0.05))
        check(unit.AttackPoiseActive, suffix .. " whiff holds the attack until just before the animation ends")
        session:AdvanceForTest(0.03)
        check(not unit.AttackPoiseActive, suffix .. " whiff releases the attack when the animation ends")
        targetEntity.KinematicbodyComponent:SetWorldPosition(Vector2(-0.5, 0))
        unit:DriveAttack(targetEntity, true)
        check(unit.AttackSerial == 1, suffix .. " whiff consumes the attack interval")
        unit:AdvanceAttack(101)
        unit:DriveAttack(targetEntity, true)
        check(unit.AttackSerial == 2, suffix .. " attacks again once the interval elapses")
    end) then return end
end

do
    local actorName = "Issue16_ToleranceActor"
    local targetName = "Issue16_ToleranceTarget"
    if not controlledCase("warrior exact frontal boundary", {
        row("monster_warrior", actorName, -1, 0, activeProfile(0.18, 0.8)),
    }, {
        row("monster_warrior", targetName, -0.5, 0, quietProfile()),
    }, function()
        local actor, unit = getUnit(actorName)
        local targetEntity, target = getUnit(targetName)
        unit:DriveAttack(targetEntity, true)
        targetEntity.KinematicbodyComponent:SetWorldPosition(Vector2(-0.17, 0))
        session:AdvanceForTest(0.2)
        check(target.Hp == 220 and target.DamageTakenSerial == 0,
            "warrior rejects a separated collider without the former 0.05 tolerance")
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
        unit:AdvanceAttack(0.2)
        session:AdvanceForTest(0.001)
        check(target.Hp == 220 and unit.AttackSerial == 2,
            suffix .. " discards pending work and allows a new autonomous attack")
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
        unit:AdvanceAttack(0.2)
        session:AdvanceForTest(0.001)
        check(target.Hp == 220 and unit.AttackSerial == 2,
            "adapter replacement cancels the unaccepted shot")
        unit:DriveAttack(targetEntity, true)
        session:AdvanceForTest(warrior.ImpactDelaySeconds + 0.02)
        check(target.Hp == 185 and target.DamageTakenSerial == 1 and unit.AttackSerial == 2,
            "replacement adapter alone delivers its native hit")
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
        check(target.Hp == 185 and decoy.Hp == 220
            and target.DamageTakenSerial == 1 and decoy.DamageTakenSerial == 0,
            "recovered warrior hits its locked target after rejected shooter configuration")
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
        row("monster_tank", actorName, -1, 0, activeProfile(0.18, 2, 40)),
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
    local actorName = "Issue16_PoiseActor"
    local firstTankName = "Issue16_PoiseTank"
    local shooterName = "Issue16_PoiseShooter"
    local lateTankName = "Issue16_PoiseLateTank"
    local recoveryTankName = "Issue16_PoiseRecoveryTank"
    if not controlledCase("attack poise through the full animation", {
        row("monster_tank", firstTankName, 3.4, 1.4, activeProfile(0.18, 2, 40)),
        row("monster_shooter", shooterName, 3.4, 1.4, activeProfile(0, 100)),
        row("monster_tank", lateTankName, 3.4, 1.4, activeProfile(0.18, 2, 40)),
        row("monster_tank", recoveryTankName, 3.4, 1.4, activeProfile(0.18, 2, 40)),
    }, {
        row("monster_warrior", actorName, -0.5, 0, activeProfile(0.18, 100)),
    }, function()
        local actorEntity, actor = getUnit(actorName)
        local firstTankEntity, firstTank = getUnit(firstTankName)
        local shooterEntity, shooter = getUnit(shooterName)
        local lateTankEntity, lateTank = getUnit(lateTankName)
        local recoveryTankEntity, recoveryTank = getUnit(recoveryTankName)
        firstTankEntity.KinematicbodyComponent:SetWorldPosition(Vector2(-1, 0))
        consumeEnemyOpeningDelay(actor, firstTankEntity, "attack poise actor")
        actor:DriveAttack(firstTankEntity, true)
        check(actor.AttackSerial == 1 and actor.AttackPoiseActive and actor.AttackAnimationDuration > 0,
            "accepted attack starts poise for its full animation")

        local startPosition = actorEntity.TransformComponent.WorldPosition
        firstTank:DriveAttack(nil, false)
        session:AdvanceForTest(0.02)
        local afterTankHit = actorEntity.TransformComponent.WorldPosition
        check(actor.Hp == 180 and actor.DamageTakenSerial == 1,
            "tank damage still applies during attack poise")
        check(actor.AttackPoiseActive and actor.CombatState == "ATTACK" and not actor.KnockbackActive
            and samePosition(startPosition, afterTankHit),
            "tank knockback and hit reaction do not interrupt an active attack")

        shooterEntity.KinematicbodyComponent:SetWorldPosition(Vector2(-1, 0.2))
        shooter:DriveAttack(actorEntity, true)
        session:AdvanceForTest(0.02)
        check(actor.Hp == 150 and actor.DamageTakenSerial == 2 and actor.AttackPoiseActive
            and actor.CombatState == "ATTACK",
            "non-tank damage applies without hit-stop during attack poise")

        session:AdvanceForTest(math.max(0, actor.AttackAnimationDuration - 0.08))
        local beforeLateHit = actorEntity.TransformComponent.WorldPosition
        lateTankEntity.KinematicbodyComponent:SetWorldPosition(Vector2(-1, 0))
        lateTank:DriveAttack(nil, false)
        session:AdvanceForTest(0.02)
        check(actor.Hp == 110 and actor.DamageTakenSerial == 3 and actor.AttackPoiseActive
            and not actor.KnockbackActive and samePosition(beforeLateHit, actorEntity.TransformComponent.WorldPosition),
            "a hit near the end of the attack animation still deals damage without knockback")

        session:AdvanceForTest(0.1)
        check(not actor.AttackPoiseActive and not actor.KnockbackActive,
            "attack poise expires after the complete attack animation without deferred knockback")

        recoveryTankEntity.KinematicbodyComponent:SetWorldPosition(Vector2(-1, 0))
        recoveryTank:DriveAttack(nil, false)
        session:AdvanceForTest(0.02)
        check(actor.Hp == 70 and actor.DamageTakenSerial == 4 and actor.KnockbackActive,
            "a new tank hit after recovery applies normal knockback")
        check(isvalid(shooterEntity), "the non-tank interruption source remains registered")
    end) then return end
end

do
    local actorName = "Issue16_PoiseLethalActor"
    local reserveName = "Issue16_PoiseLethalReserve"
    local tankName = "Issue16_PoiseLethalTank"
    local enemyReserveName = "Issue16_PoiseLethalEnemyReserve"
    if not controlledCase("attack poise does not prevent lethal damage", {
        row("monster_warrior", actorName, -0.5, 0, activeProfile(0.18, 100, nil, 30)),
        row("monster_warrior", reserveName, 3.4, 1.4, quietProfile()),
    }, {
        row("monster_tank", tankName, -1, 0, activeProfile(0.18, 2, 40)),
        row("monster_tank", enemyReserveName, 3.4, 1.4, quietProfile()),
    }, function()
        local actorEntity, actor = getUnit(actorName)
        local tankEntity, tank = getUnit(tankName)
        actor:DriveAttack(tankEntity, true)
        tank:DriveAttack(nil, false)
        session:AdvanceForTest(0.02)
        check(actor.Hp == 0 and actor.IsDead and actor.CombatState == "DEAD"
            and actor.DamageTakenSerial == 1,
            "lethal damage kills a unit during attack poise")
        check(not actor.AttackPoiseActive and not actor.KnockbackActive
            and contains(session.EventHistory, "DEAD:" .. actorEntity.Name),
            "death clears attack poise and bypasses knockback")
        check(session.Phase == "BATTLE", "reserves keep the lethal case inside the active battle")
    end) then return end
end

do
    local actorName = "Issue16_HitStopActor"
    local targetName = "Issue16_HitStopTarget"
    local hitterName = "Issue16_HitStopHitter"
    if not controlledCase("attack poise ignores hit stop but advances accepted work", {
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
        check(actor.DamageTakenSerial == 1 and actor.CombatState == "ATTACK" and actor.AttackPoiseActive,
            "opposing native hit applies damage without interrupting attack poise")
        session:AdvanceForTest(0.16)
        check(target.Hp == 190 and target.DamageTakenSerial == 1,
            "already pending attack advances through hit stop and applies its HitEvent")
        check(actor.AttackSerial == 1,
            "the accepted attack remains singular through its pending strike")
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

for _, kind in ipairs({ "monster_warrior", "monster_shooter" }) do
    local suffix = kind == "monster_warrior" and "Assault" or "Shooter"
    local actorName = "Issue16_TargetDeathActor_" .. suffix
    local killerName = "Issue16_TargetDeathKiller_" .. suffix
    local targetName = "Issue16_DyingTarget_" .. suffix
    local reserveName = "Issue16_DyingTargetReserve_" .. suffix
    if not controlledCase(suffix .. " whiffs when its target dies", {
        row(kind, actorName, -1, 0, activeProfile(0.18, 100)),
        row("monster_warrior", killerName, -1, 0.2, activeProfile(0.01, 100, 35)),
    }, {
        row("monster_warrior", targetName, -0.5, 0, quietProfile(35)),
        row("monster_tank", reserveName, 3.4, 1.4, quietProfile()),
    }, function()
        local actorEntity, actor = getUnit(actorName)
        local killerEntity, killer = getUnit(killerName)
        local _, target = getUnit(targetName)
        local _, reserve = getUnit(reserveName)
        local targetEntity = _EntityService:GetEntityByPath("/maps/template/" .. targetName)
        actor:DriveAttack(targetEntity, true)
        killer:DriveAttack(targetEntity, true)
        session:AdvanceForTest(0.05)
        check(target.IsDead and target.Hp == 0 and target.DamageTakenSerial == 1,
            "killer attack kills the locked target before the actor impact")
        check(reserve:IsAlive() and session.Phase == "BATTLE" and session.Result == "",
            "prepared enemy reserve keeps observation in BATTLE after target death")
        check(session.EnemyAlive == 1 and target.CurrentTargetName == "" and target.CombatState == "DEAD",
            "death immediately removes alive eligibility and clears the defender target")
        session:AdvanceForTest(0.2)
        check(target.DamageTakenSerial == 1 and actor.AttackSerial == 1,
            "actor does not deliver another native hit to the dead target")
        check(isvalid(actorEntity) and isvalid(killerEntity)
            and contains(session.EventHistory, "DAMAGE:" .. killerEntity.Name .. ":" .. targetName),
            "target death retains its legitimate attack and semantic damage event")
        local history = session.EventHistory
        local soundSerial = target.OnHitSoundSerial
        local effectSerial = target.HitEffectSerial
        local attackSerial = target.AttackSerial
        -- Isolate the damage guard from the native StateComponent's automatic HIT transition.
        -- DEAD -> HIT is an invalid native transition; this fresh Play is discarded after the probe.
        local state = targetEntity:GetComponent("StateComponent")
        state:DisconnectHitEvent()
        local delivered = 0
        local observer = targetEntity:ConnectEvent(HitEvent, function(event) delivered = delivered + 1 end)
        targetEntity:SendEvent(HitEvent(Vector2(-0.5, 0), killerEntity, { 999 }, nil,
            HitFeedbackAction.Default, false, 999))
        session:AdvanceForTest(0.01)
        targetEntity:DisconnectEvent(HitEvent, observer)
        check(delivered == 1, "late native HitEvent reaches the dead defender event bus")
        check(session.Phase == "BATTLE" and session.Result == "" and session.PlayerAlive == 2 and session.EnemyAlive == 1,
            "post-death native event is tested with both factions still alive")
        check(target.IsDead and target.Hp == 0 and target.DamageTakenSerial == 1
            and target.OnHitSoundSerial == soundSerial and target.HitEffectSerial == effectSerial
            and target.AttackSerial == attackSerial and session.EventHistory == history,
            "dead defender rejects a later native HitEvent without damage, sound, effect, or semantic events")
        local reserveEntity = _EntityService:GetEntityByPath("/maps/template/" .. reserveName)
        reserveEntity.KinematicbodyComponent:SetWorldPosition(Vector2(-0.5, 0))
        actor:Tick(actor.AttackAnimationDuration + 0.01)
        actor:AdvanceAttack(0.001)
        actor:DriveAttack(reserveEntity, true)
        check(actor.AttackSerial == 1, suffix .. " whiff on a dead target consumes the attack interval")
        actor:AdvanceAttack(101)
        actor:DriveAttack(reserveEntity, true)
        check(actor.AttackSerial == 2, suffix .. " attacks again once the interval elapses")
    end) then return end
end

do
    local actorName = "Issue16_TankMultiActor"
    local firstName = "Issue16_TankMultiFirst"
    local secondName = "Issue16_TankMultiSecond"
    local thirdName = "Issue16_TankMultiThird"
    if not controlledCase("tank multi-target contact cooldowns", {
        row("monster_tank", actorName, -1, 0, activeProfile(0.18, 2, 40)),
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
