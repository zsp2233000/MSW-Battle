-- Fresh Maker Play, server_main. The legacy filename is retained for existing probe runners.
local session = nil
local clockOwned = false
local failures = 0
local function check(ok, message)
    if ok then log("[M1][TankProbe][PASS] " .. message)
    else failures = failures + 1; log_error("[M1][TankProbe][FAIL] " .. message) end
end
local function row(id, name, x, y, extra)
    local profile = { MoveSpeed = 0, AttackDamageMin = 0, AttackDamageMax = 0,
        RetargetIntervalSeconds = 0, AttackIntervalSeconds = 100 }
    for k, v in pairs(extra or {}) do profile[k] = v end
    return { monsterId = id, name = name, position = Vector3(x, y, 0), overrides = profile }
end
local function actor(name)
    local entity = _EntityService:GetEntityByPath("/maps/template/" .. name)
    return entity, entity:GetComponent("script.BattleUnit")
end
local function prepare(players, enemies)
    if clockOwned then session:EndManualSimulation(); clockOwned = false end
    clockOwned = session:BeginManualSimulation()
    if not clockOwned then error("manual clock unavailable") end
    if not session:PrepareBattleForTest(players, enemies) or not session:TryStartBattle() then error("scene rejected") end
end
local function place(entity, x, y)
    entity.KinematicbodyComponent:SetWorldPosition(Vector2(x, y))
end
local runOk, runDetail = pcall(function()
    local map = _EntityService:GetEntityByPath("/maps/template")
    session = isvalid(map) and map:GetComponent("script.BattleSession") or nil
    if not isvalid(session) then error("BattleSession unavailable") end
    prepare({ row("monster_tank", "Tank", 0, 0, { AttackDamageMin=40, AttackDamageMax=40,
        ImpactDelaySeconds=0.25, AttackIntervalSeconds=3 }) }, {
        row("monster_warrior", "FrontA", 0.5, 0), row("monster_warrior", "FrontB", 0.5, 0.3),
        row("monster_warrior", "Behind", -0.5, 0), row("monster_warrior", "Outside", 2, 0),
    })
    local tank, unit = actor("Tank")
    local first, a = actor("FrontA")
    local second, b = actor("FrontB")
    local _, behind = actor("Behind")
    local outside, c = actor("Outside")
    local effect = session:GetMonsterProfile("monster_warrior").HitEffectRUID
    unit:SetMonsterIdentity(unit.MonsterId, unit.MonsterName, effect)
    unit:DriveAttack(first, false)
    unit:AdvanceAttack(1)
    check(a.Hp == 220 and unit.AttackSerial == 0, "walking contact cannot start an attack or damage a target")
    unit:DriveAttack(outside, true)
    check(unit.AttackSerial == 0, "only an in-range selected target can start a swing")
    unit:DriveAttack(first, true)
    unit:DriveAttack(second, true)
    check(unit.AttackSerial == 1 and unit.AttackPoiseActive, "one swing starts one attack serial and animation poise")
    session:AdvanceForTest(0.24)
    check(a.Hp == 220 and b.Hp == 220, "no damage before the impact frame")
    session:AdvanceForTest(0.02)
    check(a.Hp == 180 and b.Hp == 180 and a.DamageTakenSerial == 1 and b.DamageTakenSerial == 1,
        "impact hits every frontal live enemy exactly once")
    check(behind.Hp == 220 and c.Hp == 220 and unit.AttackSerial == 1,
        "behind and outside targets remain unharmed without extra attack serials")
    check(a.KnockbackActive and b.KnockbackActive and a.CombatState ~= "ON_HIT",
        "each hit knocks back without hit stop")
    check(a.HitEffectSerial == 1 and a.LastHitEffectRUID == effect,
        "configured tank hit effect reaches the defender")
    check(not string.find(session.EventHistory, "TANK_CONTACT", 1, true), "only common attack semantics are published")
    place(outside, 0.6, 0.2)
    unit:DriveAttack(outside, true)
    session:AdvanceForTest(0.02)
    check(c.Hp == 220 and unit.AttackSerial == 1, "new defenders cannot bypass the shared swing interval")

    -- An empty frontal area whiffs, holds its facing and consumes the interval.
    prepare({ row("monster_tank", "WhiffTank", 0, 0, { AttackDamageMin=40, AttackDamageMax=40,
        ImpactDelaySeconds=0.25, AttackIntervalSeconds=10 }) }, { row("monster_warrior", "Escaper", 0.5, 0) })
    tank, unit = actor("WhiffTank")
    first, a = actor("Escaper")
    unit:DriveAttack(first, true)
    local facing = tank.TransformComponent.Scale.x
    place(first, -0.5, 0)
    session:AdvanceForTest(0.3)
    check(a.Hp == 220 and unit.AttackSerial == 1 and tank.TransformComponent.Scale.x == facing,
        "empty frontal sweep whiffs without turning during its animation")
    session:AdvanceForTest(unit.AttackAnimationDuration + 0.01)
    unit:DriveAttack(first, true)
    check(unit.AttackSerial == 1, "whiff consumes the full interval")

    -- A departed selected target does not prevent hitting other enemies at impact.
    prepare({ row("monster_tank", "AreaTank", 0, 0, { AttackDamageMin=40, AttackDamageMax=40,
        ImpactDelaySeconds=0.25 }) }, { row("monster_warrior", "Selected", 0.5, 0),
        row("monster_warrior", "Remaining", 0.5, 0.3) })
    tank, unit = actor("AreaTank")
    first, a = actor("Selected")
    second, b = actor("Remaining")
    unit:DriveAttack(first, true)
    place(first, 2, 0)
    session:AdvanceForTest(0.26)
    check(a.Hp == 220 and b.Hp == 180 and unit.AttackSerial == 1,
        "sweep evaluates current occupants independently of the selected target")

    -- Exercise the configured impact through native HitEvent, without overriding its delay.
    prepare({ row("monster_tank", "FormalTank", 0, 0, { AttackDamageMin=40, AttackDamageMax=40 }) },
        { row("monster_warrior", "FormalTarget", 0.5, 0) })
    tank, unit = actor("FormalTank")
    first, a = actor("FormalTarget")
    local formal = session:GetMonsterProfile("monster_tank")
    first.KinematicbodyComponent.Enable = false
    unit:DriveAttack(first, true)
    unit:AdvanceAttack(formal.ImpactDelaySeconds - 0.001)
    session:AdvanceForTest(0.0001)
    check(formal.AttackDamageFrame == 8 and a.Hp == 220,
        "formal frame 8 leaves HP unchanged before the configured impact")
    unit:AdvanceAttack(0.002)
    session:AdvanceForTest(0.0001)
    check(a.Hp == 180 and a.DamageTakenSerial == 1 and unit.AttackSerial == 1,
        "formal frame 8 applies one native hit at the configured impact")

    -- Use real frames for displacement; the victim keeps its accepted attack and facing.
    -- Only the victim's reach differs. The landing spot after a manual step is not fixed in Maker, so the long reach
    -- spans the arena and keeps the tank in range wherever the victim lands.
    for _, case in ipairs({ { tag = "Short", reach = nil, lands = false },
        { tag = "Long", reach = session.ArenaMaxX - session.ArenaMinX, lands = true } }) do
        prepare({ row("monster_tank", case.tag .. "PushTank", 0, 0, { AttackDamageMin=1, AttackDamageMax=1,
            ImpactDelaySeconds=0.01 }) }, { row("monster_warrior", case.tag .. "AttackingVictim", 0.5, 0,
            { ImpactDelaySeconds=0.5, AttackDamageMin=35, AttackDamageMax=35, AttackRange=case.reach }) })
        tank, unit = actor(case.tag .. "PushTank")
        first, a = actor(case.tag .. "AttackingVictim")
        a:DriveAttack(tank, true)
        a:AdvanceAttack(session.EnemyOpeningDelay + 0.01)
        a:DriveAttack(tank, true)
        local victimFacing = first.TransformComponent.Scale.x
        local startX = first.TransformComponent.WorldPosition.x
        unit:DriveAttack(first, true)
        session:AdvanceForTest(0.02)
        check(a.AttackPoiseActive and a.KnockbackActive and a.AttackSerial == 1 and a.CombatState == "ATTACK",
            case.tag .. " reach: tank pushes attacking victims without cancelling their attack or playing hit reaction")
        session:EndManualSimulation(); clockOwned = false
        wait(0.12)
        check(first.TransformComponent.WorldPosition.x > startX + 0.4 and first.TransformComponent.Scale.x == victimFacing,
            case.tag .. " reach: real body displacement preserves the locked attack facing")
        -- The impact precedes the end of the attack animation, so waiting for the animation end proves the impact was evaluated.
        for _ = 1, 30 do
            if not a.AttackPoiseActive then break end
            wait(0.1)
        end
        if case.lands then
            check(not a.AttackPoiseActive and unit.Hp == unit.MaxHp - 35 and a.AttackSerial == 1,
                "displaced attack still in range hits normally")
        else
            check(not a.AttackPoiseActive and unit.Hp == unit.MaxHp and a.AttackSerial == 1,
                "displaced attack whiffs from its new position")
        end
    end
end)
if clockOwned and isvalid(session) then session:EndManualSimulation() end
if not runOk then check(false, "probe raised: " .. tostring(runDetail)) end
if failures == 0 then log("[M1][TankProbe] PASS")
else log_error("[M1][TankProbe] FAILURES=" .. tostring(failures)) end
