-- Run in a fresh Maker Play test with context=server_main, after `template` reaches DEPLOYMENT.
-- Verifies the data-driven projectile: damage waits for arrival, flight time follows ProjectileSpeed,
-- cancelling the shooter discards a ball in flight, and the instant shooter still spawns no ball.
local map = nil
local session = nil
local failures = 0
local manualClockOwned = false
local STEP = 0.05

local function check(condition, message)
    if condition then log("[VRF][ProjectileProbe][PASS] " .. message)
    else failures = failures + 1; log_error("[VRF][ProjectileProbe][FAIL] " .. message) end
end

local function row(monsterId, name, position, overrides)
    overrides = overrides or {}
    return { monsterId = monsterId, name = name, position = position, overrides = overrides }
end

local function prepare(shooterId)
    local prepared = session:PrepareBattleForTest(
        { row(shooterId, "Proj_Shooter", Vector3(-1.5, 0, 0), {
            MoveSpeed = 0, AttackDamageMin = 30, AttackDamageMax = 30, AttackIntervalSeconds = 100,
            RetargetIntervalSeconds = 0.05,
        }) },
        { row("monster_warrior", "Proj_Target", Vector3(1.5, 0, 0), {
            MaxHp = 100, MoveSpeed = 0, AttackDamageMin = 0, AttackDamageMax = 0,
            RetargetIntervalSeconds = 0, AttackIntervalSeconds = 100,
        }) }
    )
    if not prepared then return nil end
    if not session:TryStartBattle() then return nil end
    local shooter = _EntityService:GetEntityByPath("/maps/template/Proj_Shooter")
    local target = _EntityService:GetEntityByPath("/maps/template/Proj_Target")
    if not isvalid(shooter) or not isvalid(target) then return nil end
    return {
        shooter = shooter,
        target = target,
        unit = shooter:GetComponent("script.BattleUnit"),
        defender = target:GetComponent("script.BattleUnit"),
        attack = shooter:GetComponent("script.BattleAttackComposition"),
    }
end

-- Step the manual clock until the shooter has a ball in flight; returns elapsed seconds or nil.
local function stepUntilLaunch(scene, limit)
    local elapsed = 0
    while elapsed < limit do
        if scene.attack:GetProjectileCount() > 0 then return elapsed end
        session:AdvanceForTest(STEP)
        elapsed = elapsed + STEP
    end
    if scene.attack:GetProjectileCount() > 0 then return elapsed end
    return nil
end

local runOk, runDetail = pcall(function()
    map = _EntityService:GetEntityByPath("/maps/template")
    session = isvalid(map) and map:GetComponent("script.BattleSession") or nil
    if not isvalid(map) or not isvalid(session) then
        check(false, "map and BattleSession are available")
        return
    end
    manualClockOwned = session:BeginManualSimulation()
    check(manualClockOwned, "probe acquires the manual clock")
    if not manualClockOwned then return end

    local profile = session:GetMonsterProfile("monster_moon_pixie")
    check(profile ~= nil and profile.ProjectileRUID ~= "" and profile.ProjectileSpeed == 5,
        "catalog publishes the moon pixie ball clip and speed 5")
    local instant = session:GetMonsterProfile("monster_shooter")
    check(instant ~= nil and instant.ProjectileRUID == "" and instant.ProjectileSpeed == 0,
        "the original shooter keeps an instant strike")

    -- Case 1: damage waits for the ball to arrive.
    local scene = prepare("monster_moon_pixie")
    check(scene ~= nil and isvalid(scene.unit) and isvalid(scene.defender) and isvalid(scene.attack),
        "moon pixie and stationary target are prepared")
    if scene == nil then return end
    local launchedAfter = stepUntilLaunch(scene, 3)
    check(launchedAfter ~= nil, "the impact frame launches a ball")
    if launchedAfter == nil then return end
    check(scene.unit.AttackSerial == 1, "one attack started")
    check(scene.defender.Hp == 100 and scene.defender.DamageTakenSerial == 0,
        "launch alone deals no damage")
    local distance = (function()
        local from = scene.attack:GetBodyCenter(scene.shooter)
        local to = scene.attack:GetBodyCenter(scene.target)
        return math.sqrt((to.x - from.x) ^ 2 + (to.y - from.y) ^ 2)
    end)()
    local flight = 0
    local damagedWhileFlying = false
    while scene.attack:GetProjectileCount() > 0 and flight < 3 do
        session:AdvanceForTest(STEP)
        flight = flight + STEP
        if scene.attack:GetProjectileCount() > 0 and scene.defender.Hp ~= 100 then damagedWhileFlying = true end
    end
    check(not damagedWhileFlying, "the target is untouched while the ball is in flight")
    local expected = distance / 5
    check(math.abs(flight - expected) <= 0.15,
        "flight time follows distance / speed (expected " .. tostring(expected) .. ", observed " .. tostring(flight) .. ")")
    check(scene.defender.Hp == 70 and scene.defender.DamageTakenSerial == 1,
        "arrival applies exactly one 30 damage hit through the native pipeline")

    -- Case 2: cancelling the shooter discards a ball in flight without damage.
    scene = prepare("monster_moon_pixie")
    check(scene ~= nil, "second scene is prepared")
    if scene == nil then return end
    check(stepUntilLaunch(scene, 3) ~= nil, "second scene launches a ball")
    scene.attack:Cancel()
    check(scene.attack:GetProjectileCount() == 0, "Cancel discards the ball in flight")
    -- Cancel also clears the interval, so the shooter may start a fresh attack; stay inside the 0.85 s
    -- impact delay of that new attack while still outlasting the cancelled ball's 0.62 s flight.
    for _ = 1, 14 do session:AdvanceForTest(STEP) end
    check(scene.attack:GetProjectileCount() == 0 and scene.defender.Hp == 100 and scene.defender.DamageTakenSerial == 0,
        "a cancelled ball never damages the target")

    -- Case 3: an instant shooter never creates a ball.
    scene = prepare("monster_shooter")
    check(scene ~= nil, "instant shooter scene is prepared")
    if scene == nil then return end
    local sawBall = false
    for _ = 1, 60 do
        session:AdvanceForTest(STEP)
        if scene.attack:GetProjectileCount() > 0 then sawBall = true end
    end
    check(not sawBall and scene.defender.DamageTakenSerial >= 1,
        "the instant shooter damages without a projectile")
end)

if manualClockOwned and session ~= nil then
    local cleanupOk, cleanupDetail = pcall(function() session:EndManualSimulation() end)
    manualClockOwned = false
    if not cleanupOk then check(false, "cleanup releases the manual clock: " .. tostring(cleanupDetail)) end
end
if not runOk then check(false, "probe raised: " .. tostring(runDetail)) end
if failures == 0 then log("[VRF][ProjectileProbe] PASS")
else log_error("[VRF][ProjectileProbe] FAILURES=" .. tostring(failures)) end
