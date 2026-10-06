-- Run in a fresh Maker Play test with context=server_main.
-- Exercises public target selection, live crowded movement, and natural WIN/LOSE/DRAW settlement.
local map = nil
local session = nil
local failures = 0
local manualClockOwned = false

local function check(condition, message)
    if condition then log("[M1][TargetCrowdingProbe][PASS] " .. message)
    else failures = failures + 1; log_error("[M1][TargetCrowdingProbe][FAIL] " .. message) end
end

local function row(monsterId, name, position, overrides)
    return { monsterId = monsterId, name = name, position = position, overrides = overrides }
end

local function getEntity(name)
    return _EntityService:GetEntityByPath("/maps/map01/" .. name)
end

local function getUnit(entity)
    if not isvalid(entity) then return nil end
    return entity:GetComponent("script.BattleUnit")
end

local function getPosition(entity)
    return entity:GetComponent("TransformComponent").WorldPosition
end

local function setPosition(entity, x, y)
    entity:GetComponent("KinematicbodyComponent"):SetWorldPosition(Vector2(x, y))
end

local function waitFor(predicate, timeout, interval)
    local elapsed = 0
    while elapsed < timeout do
        if predicate() then return true end
        wait(interval)
        elapsed = elapsed + interval
    end
    return predicate()
end

local function releaseClockAndCheck(label)
    if not manualClockOwned then return end
    session:EndManualSimulation()
    manualClockOwned = false
    local reacquired = session:BeginManualSimulation()
    check(reacquired, label .. " releases the manual clock")
    if reacquired then session:EndManualSimulation() end
end

local function prepareScene(label, players, enemies, releaseForLiveFrames)
    local acquired = session:BeginManualSimulation()
    check(acquired, label .. " acquires the manual clock")
    if not acquired then return false end
    manualClockOwned = true

    local prepared = session:PrepareBattleForTest(players, enemies)
    check(prepared, label .. " prepares a complete controlled roster")
    if not prepared then return false end
    local started = session:TryStartBattle()
    check(started and session:IsBattleActive(), label .. " starts through TryStartBattle")
    if not started then return false end
    if releaseForLiveFrames == true then releaseClockAndCheck(label) end
    return true
end

local function assertTerminalStop(label, entities)
    local state = {}
    for index, entity in ipairs(entities) do
        local unit = getUnit(entity)
        local position = getPosition(entity)
        state[index] = {
            hp = unit.Hp,
            damageSerial = unit.DamageTakenSerial,
            attackSerial = unit.AttackSerial,
            x = position.x,
            y = position.y,
            target = unit.CurrentTargetName,
            knockback = unit.KnockbackActive,
        }
        check(unit.CurrentTargetName == "", label .. " clears target " .. entity.Name .. " at RESULT")
        check(not unit.KnockbackActive, label .. " clears knockback for " .. entity.Name .. " at RESULT")
    end
    local phase = session.Phase
    local result = session.Result
    local eventSerial = session.EventSerial
    local playerAlive = session.PlayerAlive
    local enemyAlive = session.EnemyAlive
    wait(2.2)
    check(session.Phase == phase and session.Result == result and session.EventSerial == eventSerial
        and session.PlayerAlive == playerAlive and session.EnemyAlive == enemyAlive,
        label .. " keeps result and roster counts immutable on real frames")
    for index, entity in ipairs(entities) do
        local unit = getUnit(entity)
        local position = getPosition(entity)
        local before = state[index]
        check(unit.Hp == before.hp and unit.DamageTakenSerial == before.damageSerial,
            label .. " prevents post-result health changes for " .. entity.Name)
        check(unit.AttackSerial == before.attackSerial,
            label .. " prevents post-result attacks for " .. entity.Name)
        check(math.abs(position.x - before.x) < 0.001 and math.abs(position.y - before.y) < 0.001,
            label .. " prevents post-result movement for " .. entity.Name)
        check(unit.CurrentTargetName == "" and not unit.KnockbackActive,
            label .. " keeps target and knockback work cleared for " .. entity.Name)
    end
end

local function runTerminalScenario(label, playerRow, enemyRow, expectedResult)
    if not prepareScene(label, { playerRow }, { enemyRow }, true) then return end
    local player = getEntity(playerRow.name)
    local enemy = getEntity(enemyRow.name)
    local playerUnit = getUnit(player)
    local enemyUnit = getUnit(enemy)
    check(isvalid(playerUnit) and isvalid(enemyUnit), label .. " exposes both registered BattleUnits")
    if not isvalid(playerUnit) or not isvalid(enemyUnit) then return end

    local ended = waitFor(function() return session.Phase == "RESULT" end, 3.0, 0.05)
    check(ended and session.Result == expectedResult,
        label .. " naturally resolves as " .. expectedResult .. " through full session steps")
    if not ended then return end
    check(session.InitialPlayerAlive == 1 and session.InitialEnemyAlive == 1,
        label .. " records both prepared roster entries as initial combatants")
    check(session.LastEvent == "RESULT", label .. " publishes the natural RESULT event")

    if expectedResult == "WIN" then
        check(playerUnit.AttackSerial > 0 and enemyUnit.DamageTakenSerial > 0 and enemyUnit.Hp == 0
            and session.PlayerAlive == 1 and session.EnemyAlive == 0,
            label .. " wins through a real lethal player HitEvent")
    elseif expectedResult == "LOSE" then
        check(enemyUnit.AttackSerial > 0 and playerUnit.DamageTakenSerial > 0 and playerUnit.Hp == 0
            and session.PlayerAlive == 0 and session.EnemyAlive == 1,
            label .. " loses through a real lethal enemy HitEvent")
    else
        check(playerUnit.AttackSerial > 0 and enemyUnit.AttackSerial > 0
            and playerUnit.DamageTakenSerial > 0 and enemyUnit.DamageTakenSerial > 0
            and playerUnit.Hp == 0 and enemyUnit.Hp == 0
            and session.PlayerAlive == 0 and session.EnemyAlive == 0,
            label .. " draws after both accepted native lethal hits resolve")
    end
    assertTerminalStop(label, { player, enemy })
end

local runOk, runDetail = pcall(function()
    map = _EntityService:GetEntityByPath("/maps/map01")
    session = isvalid(map) and map:GetComponent("script.BattleSession") or nil
    if not isvalid(map) or not isvalid(session) then
        check(false, "map and BattleSession are available")
        return
    end

    local targetScene = {
        row("monster_warrior", "Issue17_TargetSource", Vector3(0, 0, 0), {
            MoveSpeed = 0,
            AttackDamage = 0,
            AttackRange = 0,
            RetargetIntervalSeconds = 0,
            AttackIntervalSeconds = 100,
        }),
    }
    local targetEnemies = {
        row("monster_warrior", "Issue17_NearestA", Vector3(-2, 0, 0), {
            MoveSpeed = 0, AttackDamage = 0, AttackRange = 0,
            RetargetIntervalSeconds = 0, AttackIntervalSeconds = 100,
        }),
        row("monster_warrior", "Issue17_NearestB", Vector3(2.5, 0, 0), {
            MoveSpeed = 0, AttackDamage = 0, AttackRange = 0,
            RetargetIntervalSeconds = 0, AttackIntervalSeconds = 100,
        }),
    }
    if not prepareScene("nearest and tie preference", targetScene, targetEnemies, false) then return end
    local source = getEntity("Issue17_TargetSource")
    local nearestA = getEntity("Issue17_NearestA")
    local nearestB = getEntity("Issue17_NearestB")
    local sourceUnit = getUnit(source)
    check(isvalid(sourceUnit) and isvalid(nearestA) and isvalid(nearestB),
        "target selection scene exposes its controlled entities")
    if not isvalid(sourceUnit) or not isvalid(nearestA) or not isvalid(nearestB) then return end

    session:AdvanceForTest(0.02)
    check(sourceUnit.CurrentTargetName == nearestA.Name, "unit selects the nearest live enemy through Tick")
    setPosition(nearestB, 2, 0)
    session:AdvanceForTest(0.02)
    check(sourceUnit.CurrentTargetName == nearestA.Name,
        "existing target is retained when another target becomes exactly equidistant")
    setPosition(nearestB, 1, 0)
    session:AdvanceForTest(0.02)
    check(sourceUnit.CurrentTargetName == nearestB.Name, "unit switches when another live enemy becomes nearer")
    local enemyCountBeforeDisable = session.EnemyAlive
    nearestB:SetEnable(false)
    session:AdvanceForTest(0.02)
    check(sourceUnit.CurrentTargetName == nearestA.Name,
        "unit reacquires a valid target after the selected target is explicitly disabled")
    check(session.EnemyAlive == enemyCountBeforeDisable,
        "disabling an invalid target does not change the registered alive count")
    releaseClockAndCheck("target selection")

    local deadTargetPlayer = row("monster_warrior", "Issue17_DeadTargetSource", Vector3(0, 0, 0), {
        MaxHp = 220,
        MoveSpeed = 0,
        AttackDamage = 35,
        AttackRange = 1.2,
        RetargetIntervalSeconds = 0,
        ImpactDelaySeconds = 0.1,
        AttackIntervalSeconds = 0.7,
    })
    local deadTargetNear = row("monster_warrior", "Issue17_DeadTarget", Vector3(0.5, 0, 0), {
        MaxHp = 35,
        MoveSpeed = 0,
        AttackDamage = 0,
        AttackRange = 0,
        RetargetIntervalSeconds = 0,
        AttackIntervalSeconds = 100,
    })
    local deadTargetFar = row("monster_warrior", "Issue17_ReplacementTarget", Vector3(3.5, 0, 0), {
        MoveSpeed = 0,
        AttackDamage = 0,
        AttackRange = 0,
        RetargetIntervalSeconds = 0,
        AttackIntervalSeconds = 100,
    })
    if not prepareScene("dead-target reacquisition", { deadTargetPlayer }, { deadTargetNear, deadTargetFar }, true) then return end
    local deadSource = getEntity(deadTargetPlayer.name)
    local deadTarget = getEntity(deadTargetNear.name)
    local replacement = getEntity(deadTargetFar.name)
    local deadSourceUnit = getUnit(deadSource)
    local deadTargetUnit = getUnit(deadTarget)
    check(isvalid(deadSourceUnit) and isvalid(deadTargetUnit) and isvalid(replacement),
        "dead-target scene exposes all prepared entities")
    if not isvalid(deadSourceUnit) or not isvalid(deadTargetUnit) or not isvalid(replacement) then return end

    local lethalHit = waitFor(function() return deadTargetUnit.Hp == 0 end, 2.5, 0.05)
    check(lethalHit and deadTargetUnit.DamageTakenSerial > 0,
        "selected target dies from the attacker's native lethal HitEvent")
    if not lethalHit then return end
    local reacquired = waitFor(function() return deadSourceUnit.CurrentTargetName == replacement.Name end, 1.0, 0.05)
    check(reacquired and session.EnemyAlive == 1 and session.Phase == "BATTLE",
        "unit reacquires the surviving enemy after a real death without ending the battle")

    local boundary = session.ArenaMaxX
    local crowdPlayers = {
        row("monster_warrior", "Issue17_CrowdA", Vector3(boundary - 0.7, 0, 0), {
            MoveSpeed = 1,
            AttackDamage = 0,
            AttackRange = 0,
            RetargetIntervalSeconds = 0,
            AttackIntervalSeconds = 100,
        }),
        row("monster_warrior", "Issue17_CrowdB", Vector3(boundary - 0.7, 0, 0), {
            MoveSpeed = 1,
            AttackDamage = 0,
            AttackRange = 0,
            RetargetIntervalSeconds = 0,
            AttackIntervalSeconds = 100,
        }),
    }
    local crowdEnemy = row("monster_warrior", "Issue17_CrowdTarget", Vector3(boundary, 0, 0), {
        MoveSpeed = 0,
        AttackDamage = 0,
        AttackRange = 0,
        RetargetIntervalSeconds = 0,
        AttackIntervalSeconds = 100,
    })
    if not prepareScene("overlapping crowd and arena boundary", crowdPlayers, { crowdEnemy }, true) then return end
    local crowdA = getEntity("Issue17_CrowdA")
    local crowdB = getEntity("Issue17_CrowdB")
    local crowdStartA = getPosition(crowdA)
    local crowdStartB = getPosition(crowdB)
    wait(0.75)
    local crowdPositionA = getPosition(crowdA)
    local crowdPositionB = getPosition(crowdB)
    check(crowdPositionA.x > crowdStartA.x + 0.15 and crowdPositionB.x > crowdStartB.x + 0.15,
        "overlapping units both displace toward their target on real physics frames")
    check(crowdPositionA.x <= boundary + 0.001 and crowdPositionB.x <= boundary + 0.001
        and crowdPositionA.x >= boundary - 0.05 and crowdPositionB.x >= boundary - 0.05,
        "crowded units approach but remain clamped to the arena edge")
    check(math.abs(crowdPositionA.x - crowdPositionB.x) < 0.05
        and math.abs(crowdPositionA.y - crowdPositionB.y) < 0.05,
        "overlap does not block either unit or create unintended body separation")
    setPosition(crowdA, boundary + 0.2, crowdPositionA.y)
    setPosition(crowdB, boundary + 0.2, crowdPositionB.y)
    wait(0.15)
    crowdPositionA = getPosition(crowdA)
    crowdPositionB = getPosition(crowdB)
    check(math.abs(crowdPositionA.x - boundary) < 0.001 and math.abs(crowdPositionB.x - boundary) < 0.001,
        "live unit ticks clamp both controlled bodies back inside the arena")

    runTerminalScenario("natural WIN", row("monster_warrior", "Issue17_WinPlayer", Vector3(-0.5, 0, 0), {
        MaxHp = 220,
        MoveSpeed = 0,
        AttackDamage = 35,
        AttackRange = 1.2,
        RetargetIntervalSeconds = 0,
        ImpactDelaySeconds = 0,
        AttackIntervalSeconds = 0.7,
    }), row("monster_warrior", "Issue17_WinEnemy", Vector3(0.5, 0, 0), {
        MaxHp = 35,
        MoveSpeed = 0,
        AttackDamage = 0,
        AttackRange = 0,
        RetargetIntervalSeconds = 0,
        AttackIntervalSeconds = 100,
    }), "WIN")

    runTerminalScenario("natural LOSE", row("monster_warrior", "Issue17_LosePlayer", Vector3(-0.5, 0, 0), {
        MaxHp = 35,
        MoveSpeed = 0,
        AttackDamage = 0,
        AttackRange = 0,
        RetargetIntervalSeconds = 0,
        AttackIntervalSeconds = 100,
    }), row("monster_warrior", "Issue17_LoseEnemy", Vector3(0.5, 0, 0), {
        MaxHp = 220,
        MoveSpeed = 0,
        AttackDamage = 35,
        AttackRange = 1.2,
        RetargetIntervalSeconds = 0,
        ImpactDelaySeconds = 0,
        AttackIntervalSeconds = 0.7,
    }), "LOSE")

    runTerminalScenario("natural same-batch DRAW", row("monster_tank", "Issue17_DrawPlayer", Vector3(0, 0, 0), {
        MaxHp = 40,
        MoveSpeed = 0,
        AttackRange = 10,
        RetargetIntervalSeconds = 0,
    }), row("monster_tank", "Issue17_DrawEnemy", Vector3(0, 0, 0), {
        MaxHp = 40,
        MoveSpeed = 0,
        AttackRange = 10,
        RetargetIntervalSeconds = 0,
    }), "DRAW")
end)

if manualClockOwned and session ~= nil then
    local cleanupOk, cleanupDetail = pcall(function() session:EndManualSimulation() end)
    manualClockOwned = false
    if not cleanupOk then check(false, "error cleanup releases the manual clock: " .. tostring(cleanupDetail)) end
end
if not runOk then check(false, "probe raised: " .. tostring(runDetail)) end
if failures == 0 then log("[M1][TargetCrowdingProbe] PASS")
else log_error("[M1][TargetCrowdingProbe] FAILURES=" .. tostring(failures)) end
