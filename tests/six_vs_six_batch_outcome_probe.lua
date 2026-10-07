-- Run in a fresh Maker Play test with context=server_main.
-- Native AttackComponent HitEvents feed the complete BattleSession settlement step.
local session = nil
local failures = 0
local manualClockOwned = false

local function check(condition, message)
    if condition then log("[M1][SixVsSixBatch][PASS] " .. message)
    else failures = failures + 1; log_error("[M1][SixVsSixBatch][FAIL] " .. message) end
end

local function profile(maxHp, attackDamage, attackRange)
    return {
        MaxHp = maxHp,
        MoveSpeed = 0,
        AttackDamage = attackDamage,
        AttackRange = attackRange,
        RetargetIntervalSeconds = 100,
        ImpactDelaySeconds = 0,
        AttackIntervalSeconds = 100,
    }
end

local function rosterEntry(name, x, maxHp, attackDamage, attackRange)
    return {
        monsterId = "monster_warrior",
        name = name,
        position = Vector3(x, 0, 0),
        overrides = profile(maxHp, attackDamage, attackRange),
    }
end

local function getUnit(name)
    local entity = _EntityService:GetEntityByPath("/maps/map01/" .. name)
    if not isvalid(entity) then return nil, nil end
    return entity, entity:GetComponent("script.BattleUnit")
end

local function prepareDuel(playerHp, enemyHp, playerDamage, enemyDamage)
    local players = { rosterEntry("M1_OutcomePlayer", -0.25, playerHp, playerDamage, playerDamage > 0 and 0.65 or 0) }
    local enemies = { rosterEntry("M1_OutcomeEnemy", 0.25, enemyHp, enemyDamage, enemyDamage > 0 and 0.65 or 0) }
    local prepared = session:PrepareBattleForTest(players, enemies)
    check(prepared == true, "controlled 1v1 scene is prepared")
    if not prepared then return nil, nil, nil, nil end
    local playerEntity, player = getUnit("M1_OutcomePlayer")
    local enemyEntity, enemy = getUnit("M1_OutcomeEnemy")
    check(isvalid(player) and isvalid(enemy), "controlled duel units are available")
    if not isvalid(player) or not isvalid(enemy) then return nil, nil, nil, nil end
    local started = session:TryStartBattle()
    check(started == true and session.Phase == "BATTLE", "controlled duel starts through the session command")
    if not started then return nil, nil, nil, nil end
    return playerEntity, player, enemyEntity, enemy
end

local function events()
    local result = {}
    for event in string.gmatch(session.EventHistory or "", "[^;]+") do table.insert(result, event) end
    return result
end

local function eventName(event)
    return string.match(event, "^([^:]+)") or ""
end

local function countEvents(name)
    local count = 0
    for _, event in ipairs(events()) do
        if eventName(event) == name then count = count + 1 end
    end
    return count
end

local function damageAmountEvents(amount)
    local count = 0
    local suffix = ":" .. tostring(amount)
    for _, event in ipairs(events()) do
        if eventName(event) == "DAMAGE" and string.sub(event, -#suffix) == suffix then count = count + 1 end
    end
    return count
end

local function damageAndDeathPrecedeResult()
    local history = events()
    local resultIndex = nil
    local lastCombatIndex = 0
    local results = 0
    for index, event in ipairs(history) do
        local name = eventName(event)
        if name == "DAMAGE" or name == "DEAD" then lastCombatIndex = index end
        if name == "RESULT" then results = results + 1; resultIndex = index end
    end
    return results == 1 and resultIndex ~= nil and lastCombatIndex > 0 and lastCombatIndex < resultIndex
end

local function acceptAttack(attacker, defenderEntity)
    attacker:DriveAttack(defenderEntity, true)
    attacker:AdvanceAttack(0)
end

local function consumeEnemyOpeningDelay(attacker, defenderEntity)
    attacker:DriveAttack(defenderEntity, true)
    attacker:AdvanceAttack(session.EnemyOpeningDelay + 0.01)
end

local function settleOneHit(outcome, side)
    local playerEntity, player, enemyEntity, enemy = prepareDuel(100, 100,
        side == "player" and 100 or 0, side == "enemy" and 100 or 0)
    if player == nil or enemy == nil then return end
    if side == "player" then acceptAttack(player, enemyEntity)
    else
        consumeEnemyOpeningDelay(enemy, playerEntity)
        acceptAttack(enemy, playerEntity)
    end
    session:AdvanceForTest(1 / 60)
    local expectedPlayers = outcome == "LOSE" and 0 or 1
    local expectedEnemies = outcome == "WIN" and 0 or 1
    check(session.Phase == "RESULT" and session.Result == outcome
        and session.PlayerAlive == expectedPlayers and session.EnemyAlive == expectedEnemies,
        outcome == "WIN" and "one accepted lethal hit produces WIN" or "one accepted lethal hit produces LOSE")
    check(countEvents("RESULT") == 1 and damageAndDeathPrecedeResult(),
        outcome .. " publishes one RESULT after DAMAGE and DEAD")
end

local function settleDraw(playerFirst)
    local playerEntity, player, enemyEntity, enemy = prepareDuel(100, 100, 100, 100)
    if player == nil or enemy == nil then return end
    consumeEnemyOpeningDelay(enemy, playerEntity)
    player:DriveAttack(enemyEntity, true)
    enemy:DriveAttack(playerEntity, true)
    if playerFirst then
        player:AdvanceAttack(0)
        enemy:AdvanceAttack(0)
    else
        enemy:AdvanceAttack(0)
        player:AdvanceAttack(0)
    end
    session:AdvanceForTest(1 / 60)
    check(session.Phase == "RESULT" and session.Result == "DRAW"
        and session.PlayerAlive == 0 and session.EnemyAlive == 0,
        playerFirst and "same-batch lethal hits produce DRAW in player-first order"
            or "same-batch lethal hits produce DRAW in enemy-first order")
    check(countEvents("RESULT") == 1 and countEvents("DAMAGE") == 2
        and countEvents("DEAD") == 2 and damageAndDeathPrecedeResult(),
        "DRAW publishes both DAMAGE and DEAD observations before one RESULT")
    local beforeEventSerial = session.EventSerial
    local beforeHistory = session.EventHistory
    local deploymentAccepted = session:TryDeployMonster("monster_warrior", Vector3(-3, 0, 0))
    local restartAccepted = session:TryStartBattle()
    player:DriveAttack(enemyEntity, true)
    session:AdvanceForTest(0.1)
    check(deploymentAccepted == false and restartAccepted == false
        and session.Phase == "RESULT" and session.Result == "DRAW"
        and session.PlayerAlive == 0 and session.EnemyAlive == 0
        and session.EventSerial == beforeEventSerial and session.EventHistory == beforeHistory,
        "DRAW rejects later battle commands and remains stable after a full step")
end

local runOk, runDetail = pcall(function()
    local map = _EntityService:GetEntityByPath("/maps/map01")
    session = isvalid(map) and map:GetComponent("script.BattleSession") or nil
    check(isvalid(map) and isvalid(session), "map and BattleSession are available")
    if not isvalid(map) or not isvalid(session) then return end
    local acquired = session:BeginManualSimulation()
    check(acquired == true, "outcome probe acquires the manual clock")
    if not acquired then return end
    manualClockOwned = true

    settleOneHit("WIN", "player")
    settleOneHit("LOSE", "enemy")
    settleDraw(true)
    settleDraw(false)

    local secondPlayerRoster = { rosterEntry("M1_SecondOutcomePlayer", -0.45, 100, 30, 0.65) }
    local secondEnemyRoster = { rosterEntry("M1_SecondOutcomeEnemy", 0, 220, 0, 0) }
    check(session:PrepareBattleForTest(
        { rosterEntry("M1_FirstOutcomePlayer", -0.45, 100, 35, 0.65), secondPlayerRoster[1] },
        secondEnemyRoster), "two attacker scene is prepared for separate accepted hits")
    local firstEntity, first = getUnit("M1_FirstOutcomePlayer")
    local secondEntity, second = getUnit("M1_SecondOutcomePlayer")
    local targetEntity, target = getUnit("M1_SecondOutcomeEnemy")
    check(isvalid(first) and isvalid(second) and isvalid(target), "two attackers and their target are available")
    if isvalid(first) and isvalid(second) and isvalid(target) then
        check(session:TryStartBattle(), "two attacker scene starts through the session command")
        local damageSerial = target.DamageTakenSerial
        local soundSerial = target.OnHitSoundSerial
        local soundRUID = target.OnHitSoundRUID
        first:DriveAttack(targetEntity, true)
        second:DriveAttack(targetEntity, true)
        first:AdvanceAttack(0)
        second:AdvanceAttack(0)
        session:AdvanceForTest(1 / 60)
        local soundDeltaMatches = soundRUID ~= nil and soundRUID ~= ""
            and target.OnHitSoundSerial == soundSerial + 2
            or (soundRUID == nil or soundRUID == "") and target.OnHitSoundSerial == soundSerial
        check(target.Hp == 155 and target.DamageTakenSerial == damageSerial + 2
            and soundDeltaMatches and damageAmountEvents(35) == 1 and damageAmountEvents(30) == 1,
            "two accepted hits retain separate HP, serial, sound, and damage-event observations")
    end

    local winPlayerEntity, winPlayer, winEnemyEntity, winEnemy = prepareDuel(100, 100, 100, 0)
    if winPlayer ~= nil and winEnemy ~= nil then
        acceptAttack(winPlayer, winEnemyEntity)
        session:AdvanceForTest(1 / 60)
        local playerPosition = winPlayerEntity:GetComponent("TransformComponent").WorldPosition
        local before = {
            hp = winPlayer.Hp,
            damage = winPlayer.DamageTakenSerial,
            attacks = winPlayer.AttackSerial,
            x = playerPosition.x,
            y = playerPosition.y,
            eventSerial = session.EventSerial,
            history = session.EventHistory,
        }
        local deploymentAccepted = session:TryDeployMonster("monster_warrior", Vector3(-3, 0, 0))
        local restartAccepted = session:TryStartBattle()
        winPlayer:DriveAttack(winEnemyEntity, true)
        session:AdvanceForTest(0.1)
        local afterPosition = winPlayerEntity:GetComponent("TransformComponent").WorldPosition
        check(deploymentAccepted == false and restartAccepted == false
            and session.Phase == "RESULT" and session.Result == "WIN"
            and session.PlayerAlive == 1 and session.EnemyAlive == 0
            and winPlayer.Hp == before.hp and winPlayer.DamageTakenSerial == before.damage
            and winPlayer.AttackSerial == before.attacks and winPlayer.CurrentTargetName == ""
            and winPlayer.CombatState == "RESULT_STOP" and winPlayer.KnockbackActive == false
            and math.abs(afterPosition.x - before.x) < 0.0001
            and math.abs(afterPosition.y - before.y) < 0.0001
            and session.EventSerial == before.eventSerial and session.EventHistory == before.history,
            "result rejects later battle commands and keeps the terminal state stable for a full step")
    end
end)

if manualClockOwned and isvalid(session) then
    local cleanupOk, cleanupDetail = pcall(function() session:EndManualSimulation() end)
    manualClockOwned = false
    if not cleanupOk then check(false, "error cleanup releases its owned clock: " .. tostring(cleanupDetail)) end
end
if not runOk then check(false, "probe raised: " .. tostring(runDetail)) end
if failures == 0 then log("[M1][SixVsSixBatch] PASS")
else log_error("[M1][SixVsSixBatch] FAILURES=" .. tostring(failures)) end
