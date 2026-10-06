-- Run in a fresh Maker Play test with context=server_main.
-- Exercise complete-batch settlement through observable session and unit state.
local map = nil
local session = nil
local failures = 0
local manualClockOwned = false

local function check(condition, message)
    if condition then log("[M1][SixVsSixBatch][PASS] " .. message)
    else failures = failures + 1; log_error("[M1][SixVsSixBatch][FAIL] " .. message) end
end

local function getUnit(name)
    local entity = _EntityService:GetEntityByPath("/maps/map01/" .. name)
    if not isvalid(entity) then return nil, nil end
    return entity, entity:GetComponent("script.BattleUnit")
end

local function quietProfile(maxHp)
    return {
        MaxHp = maxHp or 100,
        MoveSpeed = 0,
        AttackDamage = 0,
        AttackRange = 0,
        RetargetIntervalSeconds = 0,
        AttackIntervalSeconds = 100,
    }
end

local function rosterEntry(monsterId, name, x, y, maxHp)
    return {
        monsterId = monsterId,
        name = name,
        position = Vector3(x, y, 0),
        overrides = quietProfile(maxHp),
    }
end

local function prepareDuel(playerHp, enemyHp)
    local players = { rosterEntry("monster_warrior", "M1_OutcomePlayer", -4, 0, playerHp) }
    local enemies = { rosterEntry("monster_tank", "M1_OutcomeEnemy", 1, 0, enemyHp) }
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

local function settleOneHit(outcome, side)
    local playerEntity, player, enemyEntity, enemy = prepareDuel(100, 100)
    if player == nil or enemy == nil then return end
    if side == "player" then session:QueueDamage(enemyEntity, 100, playerEntity)
    else session:QueueDamage(playerEntity, 100, enemyEntity) end
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
    local playerEntity, player, enemyEntity, enemy = prepareDuel(100, 100)
    if player == nil or enemy == nil then return end
    if playerFirst then
        session:QueueDamage(enemyEntity, 100, playerEntity)
        session:QueueDamage(playerEntity, 100, enemyEntity)
        session:AdvanceForTest(1 / 60)
        check(session.Phase == "RESULT" and session.Result == "DRAW"
            and session.PlayerAlive == 0 and session.EnemyAlive == 0,
            "same-batch lethal hits produce DRAW in player-first order")
    else
        session:QueueDamage(playerEntity, 100, enemyEntity)
        session:QueueDamage(enemyEntity, 100, playerEntity)
        session:AdvanceForTest(1 / 60)
        check(session.Phase == "RESULT" and session.Result == "DRAW"
            and session.PlayerAlive == 0 and session.EnemyAlive == 0,
            "same-batch lethal hits produce DRAW in enemy-first order")
    end
    check(countEvents("RESULT") == 1 and countEvents("DAMAGE") == 2
        and countEvents("DEAD") == 2 and damageAndDeathPrecedeResult(),
        "DRAW publishes both DAMAGE and DEAD observations before one RESULT")
    local beforeEventSerial = session.EventSerial
    local beforeHistory = session.EventHistory
    local deploymentAccepted = session:TryDeployMonster("monster_warrior", Vector3(-3, 0, 0))
    local restartAccepted = session:TryStartBattle()
    session:AdvanceForTest(0.1)
    check(deploymentAccepted == false and restartAccepted == false
        and session.Phase == "RESULT" and session.Result == "DRAW"
        and session.PlayerAlive == 0 and session.EnemyAlive == 0
        and session.EventSerial == beforeEventSerial and session.EventHistory == beforeHistory,
        "DRAW rejects later battle commands and remains stable after a full step")
end

local runOk, runDetail = pcall(function()
    map = _EntityService:GetEntityByPath("/maps/map01")
    session = isvalid(map) and map:GetComponent("script.BattleSession") or nil
    if not isvalid(map) or not isvalid(session) then
        check(false, "map and BattleSession are available")
        return
    end
    local acquired = session:BeginManualSimulation()
    check(acquired == true, "outcome probe acquires the manual clock")
    if not acquired then return end
    manualClockOwned = true

    settleOneHit("WIN", "player")
    settleOneHit("LOSE", "enemy")
    settleDraw(true)
    settleDraw(false)

    local playerEntity, player, enemyEntity, enemy = prepareDuel(100, 220)
    if player ~= nil and enemy ~= nil then
        local damageSerial = enemy.DamageTakenSerial
        local soundSerial = enemy.OnHitSoundSerial
        local soundRUID = enemy.OnHitSoundRUID
        session:QueueDamage(enemyEntity, 35, playerEntity)
        session:QueueDamage(enemyEntity, 30, playerEntity)
        session:AdvanceForTest(1 / 60)
        local soundDeltaMatches = soundRUID ~= nil and soundRUID ~= ""
            and enemy.OnHitSoundSerial == soundSerial + 2
            or (soundRUID == nil or soundRUID == "") and enemy.OnHitSoundSerial == soundSerial
        check(enemy.Hp == 155 and enemy.DamageTakenSerial == damageSerial + 2
            and soundDeltaMatches and damageAmountEvents(35) == 1 and damageAmountEvents(30) == 1,
            "two accepted hits retain separate HP, serial, sound, and damage-event observations")
    end

    local winPlayerEntity, winPlayer, winEnemyEntity = prepareDuel(100, 100)
    if winPlayer ~= nil then
        session:QueueDamage(winEnemyEntity, 100, winPlayerEntity)
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
        session:QueueDamage(winPlayerEntity, 25, winEnemyEntity)
        session:QueueKnockback(winEnemyEntity, winPlayerEntity, 0.5)
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
    if not cleanupOk then check(false, "error cleanup releases manual clock: " .. tostring(cleanupDetail)) end
end
if not runOk then check(false, "probe raised: " .. tostring(runDetail)) end
if failures == 0 then log("[M1][SixVsSixBatch] PASS")
else log_error("[M1][SixVsSixBatch] FAILURES=" .. tostring(failures)) end
