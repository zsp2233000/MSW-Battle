-- Run in a fresh Maker Play test with context=server_main.
-- Uses a controlled roster, native TankContactAttack/HitEvent, live frames, and natural result settlement.
local map = nil
local session = nil
local failures = 0
local manualClockOwned = false

local function check(condition, message)
    if condition then log("[M1][TankProbe][PASS] " .. message)
    else failures = failures + 1; log_error("[M1][TankProbe][FAIL] " .. message) end
end

local function row(monsterId, name, position, overrides)
    return { monsterId = monsterId, name = name, position = position, overrides = overrides }
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

local function prepareScene()
    local acquired = session:BeginManualSimulation()
    check(acquired, "controlled contact scene acquires the manual clock")
    if not acquired then return false end
    manualClockOwned = true

    local prepared = session:PrepareBattleForTest(
        { row("monster_tank", "Issue17_Tank", Vector3(0, 0, 0), {
            MaxHp = 500,
            MoveSpeed = 0,
            AttackRange = 10,
            RetargetIntervalSeconds = 0,
        }) },
        {
            row("monster_warrior", "Issue17_TankTargetA", Vector3(0.2, 0, 0), {
                MaxHp = 160,
                MoveSpeed = 0,
                AttackDamage = 0,
                AttackRange = 0,
                RetargetIntervalSeconds = 0,
                AttackIntervalSeconds = 100,
            }),
            row("monster_warrior", "Issue17_TankTargetB", Vector3(2, 0, 0), {
                MaxHp = 160,
                MoveSpeed = 0,
                AttackDamage = 0,
                AttackRange = 0,
                RetargetIntervalSeconds = 0,
                AttackIntervalSeconds = 100,
            }),
        }
    )
    check(prepared, "tank and two official enemy profiles are prepared")
    if not prepared then return false end
    local started = session:TryStartBattle()
    check(started and session:IsBattleActive(), "controlled contact scene starts through TryStartBattle")
    if not started then return false end
    return true
end

local runOk, runDetail = pcall(function()
    map = _EntityService:GetEntityByPath("/maps/map01")
    session = isvalid(map) and map:GetComponent("script.BattleSession") or nil
    if not isvalid(map) or not isvalid(session) then
        check(false, "map and BattleSession are available")
        return
    end
    if not prepareScene() then return end

    local tank = _EntityService:GetEntityByPath("/maps/map01/Issue17_Tank")
    local first = _EntityService:GetEntityByPath("/maps/map01/Issue17_TankTargetA")
    local second = _EntityService:GetEntityByPath("/maps/map01/Issue17_TankTargetB")
    local tankUnit = isvalid(tank) and tank:GetComponent("script.BattleUnit") or nil
    local firstUnit = isvalid(first) and first:GetComponent("script.BattleUnit") or nil
    local secondUnit = isvalid(second) and second:GetComponent("script.BattleUnit") or nil
    local tankBody = isvalid(tank) and tank:GetComponent("KinematicbodyComponent") or nil
    check(isvalid(tankUnit) and isvalid(firstUnit) and isvalid(secondUnit) and isvalid(tankBody),
        "prepared native bodies and BattleUnits are available")
    if not isvalid(tankUnit) or not isvalid(firstUnit) or not isvalid(secondUnit) or not isvalid(tankBody) then return end

    local tankStart = getPosition(tank)
    local firstSerial = firstUnit.DamageTakenSerial
    local secondSerial = secondUnit.DamageTakenSerial
    releaseClockAndCheck("contact scene setup")
    local firstContact = waitFor(function() return firstUnit.DamageTakenSerial > firstSerial end, 1.2, 0.05)
    check(firstContact, "native contact reaches the first target")
    if not firstContact then return end
    check(firstUnit.Hp == 120 and secondUnit.Hp == 160, "contact area reaches only the overlapping target")
    local afterFirst = getPosition(tank)
    check(math.abs(afterFirst.x - tankStart.x) < 0.001 and math.abs(afterFirst.y - tankStart.y) < 0.001,
        "tank does not recoil from its native contact")

    -- Contact the second defender later so its cooldown expires after the first defender's cooldown.
    setPosition(first, 0.2, 0)
    wait(0.8)
    setPosition(second, 0.4, 0)
    local secondContact = waitFor(function() return secondUnit.DamageTakenSerial > secondSerial end, 0.8, 0.05)
    check(secondContact, "native contact later reaches the second target")
    if not secondContact then return end
    setPosition(second, 0.4, 0)
    check(firstUnit.Hp == 120 and secondUnit.Hp == 120,
        "per-target cooldown blocks the first target while accepting the newly contacted second target")

    local firstSecondContact = waitFor(function() return firstUnit.DamageTakenSerial >= firstSerial + 2 end, 1.6, 0.05)
    check(firstSecondContact, "the first target cooldown expires independently")
    if not firstSecondContact then return end
    check(firstUnit.Hp == 80 and secondUnit.Hp == 120 and secondUnit.DamageTakenSerial == secondSerial + 1,
        "first target can be hit again while the second target remains on cooldown")

    local secondSecondContact = waitFor(function() return secondUnit.DamageTakenSerial >= secondSerial + 2 end, 1.6, 0.05)
    check(secondSecondContact, "the later second-target cooldown expires independently")
    if not secondSecondContact then return end
    check(firstUnit.Hp == 80 and secondUnit.Hp == 80,
        "both targets take their second 40-damage contact without shared cooldown state")

    local boundaryTankX = session.ArenaMaxX - 0.6
    tankBody:SetWorldPosition(Vector2(boundaryTankX, 0))
    setPosition(first, session.ArenaMaxX - 0.1, 0)
    setPosition(second, session.ArenaMaxX - 0.2, 0)
    local firstThirdContact = waitFor(function() return firstUnit.DamageTakenSerial >= firstSerial + 3 end, 1.6, 0.05)
    check(firstThirdContact, "boundary contact reaches the first target after its own cooldown")
    if not firstThirdContact then return end
    check(firstUnit.Hp == 40 and secondUnit.Hp == 80 and secondUnit.DamageTakenSerial == secondSerial + 2,
        "boundary contact preserves independent target cooldowns")

    local secondThirdContact = waitFor(function() return secondUnit.DamageTakenSerial >= secondSerial + 3 end, 1.6, 0.05)
    check(secondThirdContact, "boundary contact reaches the second target after its own cooldown")
    if not secondThirdContact then return end
    wait(0.15)
    local firstAtBoundary = getPosition(first)
    local secondAtBoundary = getPosition(second)
    local tankAtBoundary = getPosition(tank)
    check(firstUnit.Hp == 40 and secondUnit.Hp == 40, "third native contact leaves both targets alive for boundary inspection")
    check(math.abs(firstAtBoundary.x - session.ArenaMaxX) < 0.05
        and math.abs(secondAtBoundary.x - session.ArenaMaxX) < 0.05,
        "native knockback clamps both enemy bodies at the arena boundary")
    check(firstAtBoundary.x <= session.ArenaMaxX + 0.001 and secondAtBoundary.x <= session.ArenaMaxX + 0.001,
        "neither enemy body crosses the arena boundary")
    check(math.abs(tankAtBoundary.x - boundaryTankX) < 0.001,
        "tank remains fixed while its targets are knocked back at the boundary")

    local resultReached = waitFor(function() return session.Phase == "RESULT" end, 2.8, 0.05)
    check(resultReached and session.Result == "WIN", "real lethal contacts naturally settle the full roster as WIN")
    if not resultReached then return end
    check(firstUnit.Hp == 0 and secondUnit.Hp == 0 and firstUnit.DamageTakenSerial == firstSerial + 4
        and secondUnit.DamageTakenSerial == secondSerial + 4,
        "four native HitEvent contacts eliminate both registered enemy units")
    check(session.PlayerAlive == 1 and session.EnemyAlive == 0
        and session.InitialPlayerAlive == 1 and session.InitialEnemyAlive == 2,
        "result counters reflect the prepared roster and actual deaths")

    local resultSerial = tankUnit.AttackSerial
    local resultEventSerial = session.EventSerial
    local tankResultPosition = getPosition(tank)
    local firstResultPosition = getPosition(first)
    local secondResultPosition = getPosition(second)
    check(firstUnit.CurrentTargetName == "" and secondUnit.CurrentTargetName == ""
        and tankUnit.CurrentTargetName == "", "RESULT clears all unit targets")
    check(not tankUnit.KnockbackActive and not firstUnit.KnockbackActive and not secondUnit.KnockbackActive,
        "RESULT clears accepted knockback work")
    wait(2.2)
    local tankAfterResult = getPosition(tank)
    local firstAfterResult = getPosition(first)
    local secondAfterResult = getPosition(second)
    check(session.Phase == "RESULT" and session.Result == "WIN" and session.EventSerial == resultEventSerial,
        "result state and event history remain unchanged on real frames")
    check(tankUnit.AttackSerial == resultSerial and firstUnit.Hp == 0 and secondUnit.Hp == 0,
        "RESULT prevents new attacks and health changes")
    check(math.abs(tankAfterResult.x - tankResultPosition.x) < 0.001
        and math.abs(firstAfterResult.x - firstResultPosition.x) < 0.001
        and math.abs(secondAfterResult.x - secondResultPosition.x) < 0.001,
        "RESULT prevents further body movement")
    check(not tankUnit.KnockbackActive and not firstUnit.KnockbackActive and not secondUnit.KnockbackActive,
        "no knockback resumes after RESULT")

    local reacquired = session:BeginManualSimulation()
    check(reacquired, "completed tank probe can reacquire the released manual clock")
    if reacquired then session:EndManualSimulation() end
end)

if manualClockOwned and session ~= nil then
    local cleanupOk, cleanupDetail = pcall(function() session:EndManualSimulation() end)
    manualClockOwned = false
    if not cleanupOk then check(false, "error cleanup releases the manual clock: " .. tostring(cleanupDetail)) end
end
if not runOk then check(false, "probe raised: " .. tostring(runDetail)) end
if failures == 0 then log("[M1][TankProbe] PASS")
else log_error("[M1][TankProbe] FAILURES=" .. tostring(failures)) end
