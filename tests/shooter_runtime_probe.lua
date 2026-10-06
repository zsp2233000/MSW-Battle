-- Run in a fresh Maker Play test with context=server_main.
-- Verifies native hitscan movement, catalog impact timing, and natural result shutdown on live frames.
local map = nil
local session = nil
local failures = 0
local manualClockOwned = false

local function check(condition, message)
    if condition then log("[M1][ShooterProbe][PASS] " .. message)
    else failures = failures + 1; log_error("[M1][ShooterProbe][FAIL] " .. message) end
end

local function row(monsterId, name, position, overrides)
    return { monsterId = monsterId, name = name, position = position, overrides = overrides }
end

local function position(entity)
    return entity:GetComponent("TransformComponent").WorldPosition
end

local function distance(left, right)
    local dx = right.x - left.x
    local dy = right.y - left.y
    return math.sqrt(dx * dx + dy * dy)
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

local function releaseClockAndCheck()
    if not manualClockOwned then return end
    session:EndManualSimulation()
    manualClockOwned = false
    local reacquired = session:BeginManualSimulation()
    check(reacquired, "scene setup releases the manual clock for real frames")
    if reacquired then session:EndManualSimulation() end
end

local function prepareScene()
    local acquired = session:BeginManualSimulation()
    check(acquired, "controlled shooter scene acquires the manual clock")
    if not acquired then return false end
    manualClockOwned = true
    local prepared = session:PrepareBattleForTest(
        { row("monster_shooter", "Issue17_Shooter", Vector3(-2, 0, 0), {
            RetargetIntervalSeconds = 0.05,
        }) },
        { row("monster_warrior", "Issue17_ShooterTarget", Vector3(3, 0, 0), {
            MaxHp = 30,
            MoveSpeed = 0,
            AttackDamage = 0,
            AttackRange = 0,
            RetargetIntervalSeconds = 0,
            AttackIntervalSeconds = 100,
        }) }
    )
    check(prepared, "shooter and stationary target use copied official profiles")
    if not prepared then return false end
    local started = session:TryStartBattle()
    check(started and session:IsBattleActive(), "controlled shooter scene starts through TryStartBattle")
    if not started then return false end
    releaseClockAndCheck()
    return true
end

local function hasProjectileEntity()
    for _, entity in ipairs(map.Children:ToTable()) do
        if string.find(string.lower(entity.Name), "projectile", 1, true) ~= nil then return true end
    end
    return false
end

local runOk, runDetail = pcall(function()
    map = _EntityService:GetEntityByPath("/maps/map01")
    session = isvalid(map) and map:GetComponent("script.BattleSession") or nil
    if not isvalid(map) or not isvalid(session) then
        check(false, "map and BattleSession are available")
        return
    end
    if not prepareScene() then return end

    local shooter = _EntityService:GetEntityByPath("/maps/map01/Issue17_Shooter")
    local target = _EntityService:GetEntityByPath("/maps/map01/Issue17_ShooterTarget")
    local actor = isvalid(shooter) and shooter:GetComponent("script.BattleUnit") or nil
    local defender = isvalid(target) and target:GetComponent("script.BattleUnit") or nil
    check(isvalid(actor) and isvalid(defender), "prepared shooter and target components are available")
    if not isvalid(actor) or not isvalid(defender) then return end

    wait(0.3)
    local approachPosition = position(shooter)
    check(approachPosition.x > -2 and defender.Hp == 30,
        "shooter moves under native physics while the target remains beyond firing range and unharmed")

    local attackStarted = waitFor(function() return actor.AttackSerial > 0 end, 3.0, 0.01)
    check(attackStarted, "shooter begins an attack after approaching the target")
    if not attackStarted then return end
    local attackObservedAtMs = DateTime.UtcNow.Elapsed
    local attackStartDistance = distance(position(shooter), position(target))
    check(attackStartDistance <= actor.AttackRange + 0.001,
        "attack starts only after the shooter enters its catalog range")
    check(defender.Hp == 30 and defender.DamageTakenSerial == 0,
        "AttackSerial advances before the catalog impact frame reaches the target")

    local expectedImpactMs = actor.ImpactDelay * 1000
    local frameToleranceMs = 50
    check(expectedImpactMs > 0, "shooter profile has a measurable positive impact delay")
    local observedImpactMs = nil
    while true do
        local elapsedMs = DateTime.UtcNow.Elapsed - attackObservedAtMs
        if defender.DamageTakenSerial > 0 then
            observedImpactMs = elapsedMs
            break
        end
        if elapsedMs >= expectedImpactMs + frameToleranceMs then break end
        wait(0.01)
    end
    local impactObserved = observedImpactMs ~= nil
    check(impactObserved, "native HitEvent arrives by the profile impact deadline")
    if not impactObserved then return end
    log("[M1][ShooterProbe] expectedImpactMs=" .. tostring(expectedImpactMs)
        .. " observedImpactMs=" .. tostring(observedImpactMs)
        .. " toleranceMs=" .. tostring(frameToleranceMs))
    check(observedImpactMs >= expectedImpactMs - frameToleranceMs
        and observedImpactMs <= expectedImpactMs + frameToleranceMs,
        "native HitEvent lands within one-frame tolerance of the profile impact frame")
    check(defender.Hp == 0 and defender.DamageTakenSerial == 1,
        "hitscan applies exactly the catalog 30 damage at its impact frame")
    check(session.Phase == "RESULT" and session.Result == "WIN"
        and session.PlayerAlive == 1 and session.EnemyAlive == 0,
        "real lethal hitscan damage naturally settles the registered roster as WIN")
    check(not hasProjectileEntity(), "hitscan does not spawn a projectile entity")

    local shooterSerial = actor.AttackSerial
    local defenderSerial = defender.AttackSerial
    local resultEventSerial = session.EventSerial
    local shooterHp = actor.Hp
    local defenderHp = defender.Hp
    local shooterDamageSerial = actor.DamageTakenSerial
    local defenderDamageSerial = defender.DamageTakenSerial
    local shooterPosition = position(shooter)
    local targetPosition = position(target)
    check(actor.CurrentTargetName == "" and defender.CurrentTargetName == "",
        "RESULT clears the shooter and target references")
    check(not actor.KnockbackActive and not defender.KnockbackActive,
        "RESULT leaves no pending knockback")
    wait(2.2)
    local shooterAfter = position(shooter)
    local targetAfter = position(target)
    check(session.Phase == "RESULT" and session.Result == "WIN" and session.EventSerial == resultEventSerial,
        "result and event history remain unchanged on real frames")
    check(actor.AttackSerial == shooterSerial and defender.AttackSerial == defenderSerial
        and actor.Hp == shooterHp and defender.Hp == defenderHp
        and actor.DamageTakenSerial == shooterDamageSerial and defender.DamageTakenSerial == defenderDamageSerial,
        "RESULT prevents new attacks, hit events, and health changes for every unit")
    check(math.abs(shooterAfter.x - shooterPosition.x) < 0.001
        and math.abs(shooterAfter.y - shooterPosition.y) < 0.001
        and math.abs(targetAfter.x - targetPosition.x) < 0.001
        and math.abs(targetAfter.y - targetPosition.y) < 0.001,
        "RESULT stops further native body movement")
    check(actor.CurrentTargetName == "" and defender.CurrentTargetName == "",
        "RESULT keeps all unit target references cleared on real frames")
    check(not actor.KnockbackActive and not defender.KnockbackActive and not hasProjectileEntity(),
        "no knockback or projectile appears after RESULT")

    local reacquired = session:BeginManualSimulation()
    check(reacquired, "completed shooter probe can reacquire the released manual clock")
    if reacquired then session:EndManualSimulation() end
end)

if manualClockOwned and session ~= nil then
    local cleanupOk, cleanupDetail = pcall(function() session:EndManualSimulation() end)
    manualClockOwned = false
    if not cleanupOk then check(false, "error cleanup releases the manual clock: " .. tostring(cleanupDetail)) end
end
if not runOk then check(false, "probe raised: " .. tostring(runDetail)) end
if failures == 0 then log("[M1][ShooterProbe] PASS")
else log_error("[M1][ShooterProbe] FAILURES=" .. tostring(failures)) end
