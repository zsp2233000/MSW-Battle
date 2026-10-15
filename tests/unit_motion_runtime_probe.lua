-- Fresh Maker Play, server_main. Observe motion through the controlled BattleSession seam.
local session = nil
local clockOwned = false
local failures = 0
local function check(condition, message)
    if condition then log("[VRF][UnitMotion][PASS] " .. message)
    else failures = failures + 1; log_error("[VRF][UnitMotion][FAIL] " .. message) end
end
local function row(id, name, x, y, overrides)
    return { monsterId = id, name = name, position = Vector3(x, y, 0), overrides = overrides }
end
local function quiet(extra)
    local profile = { MoveSpeed = 0, AttackDamage = 0, AttackRange = 0,
        RetargetIntervalSeconds = 0.5, AttackIntervalSeconds = 100 }
    for key, value in pairs(extra or {}) do profile[key] = value end
    return profile
end
local function actor(name)
    local entity = _EntityService:GetEntityByPath("/maps/map01/" .. name)
    return entity, entity:GetComponent("script.BattleUnit")
end
local function place(entity, x, y)
    entity.KinematicbodyComponent:SetWorldPosition(Vector2(x, y))
end
local function advance(elapsed)
    -- Yield between controlled steps so the Maker command runner remains responsive.
    wait(0.05)
    session:AdvanceForTest(elapsed)
end
local function scene(players, enemies, callback)
    if not session:BeginManualSimulation() then error("manual clock unavailable") end
    clockOwned = true
    if not session:PrepareBattleForTest(players, enemies) then error("scene rejected") end
    if not session:TryStartBattle() then error("battle did not start") end
    callback()
    if clockOwned then session:EndManualSimulation(); clockOwned = false end
end
local function nativeShot(attacker, target)
    attacker:DriveAttack(target, true)
    attacker:AdvanceAttack(0.02)
    advance(1 / 60)
end

local ok, detail = pcall(function()
    local map = _EntityService:GetEntityByPath("/maps/map01")
    session = isvalid(map) and map:GetComponent("script.BattleSession") or nil
    if not isvalid(session) then error("BattleSession unavailable") end

    scene({ row("monster_warrior", "MotionSource", 0, 0, quiet()),
        row("monster_warrior", "MotionAlly", 0.1, 0, quiet()) }, {
        row("monster_warrior", "MotionFirst", -2, 0, quiet()),
        row("monster_warrior", "MotionSecond", 2, 0, quiet()),
    }, function()
        local source, unit = actor("MotionSource")
        local first = actor("MotionFirst")
        local second = actor("MotionSecond")
        advance(0.01)
        check(unit.CurrentTargetName == first.Name, "first acquisition excludes self and allies and uses roster order for exact ties")
        place(second, 1, 0)
        advance(0.4)
        check(unit.CurrentTargetName == first.Name, "profile retarget interval postpones a nearer enemy")
        advance(0.11)
        check(unit.CurrentTargetName == second.Name, "profile retarget interval selects the nearer enemy when due")
        first:SetEnable(false)
        second:SetEnable(false)
        advance(0.01)
        check(unit.CurrentTargetName == "" and unit:GetCurrentTarget() == nil and unit.CombatState == "IDLE",
            "no target clears acquisition and stops pursuit without forcing a result")
        local velocity = source.KinematicbodyComponent.MoveVelocity
        check(velocity.x == 0 and velocity.y == 0 and session.Result == "", "no target leaves native velocity stopped")
    end)

    for _, interval in ipairs({ 0, 0.5 }) do
        scene({ row("monster_warrior", "PauseSource", 0, 0, quiet({ RetargetIntervalSeconds = interval })) }, {
            row("monster_shooter", "PauseAttacker", 2, 0, quiet({ AttackDamage = 1,
                AttackRange = 4, ImpactDelaySeconds = 0.01 })),
            row("monster_warrior", "PauseNearer", 3, 0, quiet()),
        }, function()
            local source, unit = actor("PauseSource")
            local attackerEntity, attacker = actor("PauseAttacker")
            local nearer = actor("PauseNearer")
            attacker.AttackRange = 0
            attacker:DriveAttack(source, true) -- Consume the enemy opening delay.
            advance(session.EnemyOpeningDelay + 0.02)
            nativeShot(attacker, source)
            check(unit.Hp == 219 and unit.CombatState == "ON_HIT", "native damage starts profile hit stop")
            place(nearer, 1, 0)
            advance(0.19)
            check(unit.CurrentTargetName == attackerEntity.Name and unit.CombatState == "ON_HIT",
                "hit stop pauses acquisition and pursuit")
            advance(0.02)
            if interval == 0 then
                check(unit.CurrentTargetName == nearer.Name and unit.CombatState ~= "ON_HIT",
                    "hit stop expiration resumes retargeting in the same step")
            else
                advance(0.2)
                check(unit.CurrentTargetName == attackerEntity.Name,
                    "hit stop does not consume the remaining retarget interval")
                advance(0.2)
                check(unit.CurrentTargetName == nearer.Name, "retarget countdown resumes after hit stop")
            end
        end)
    end

    scene({ row("monster_shooter", "LockedSource", 0, 0, quiet({ AttackDamage = 30,
        AttackRange = 4, RetargetIntervalSeconds = 0, ImpactDelaySeconds = 0.3 })) }, {
        row("monster_warrior", "LockedFirst", 2, 0, quiet()),
        row("monster_warrior", "LockedNearer", 3, 0, quiet()),
    }, function()
        local source, unit = actor("LockedSource")
        local firstEntity, first = actor("LockedFirst")
        local nearerEntity, nearer = actor("LockedNearer")
        advance(0.01)
        check(unit.AttackSerial == 1 and unit.CurrentTargetName == firstEntity.Name, "acquisition hands an in-range attack to composition")
        place(nearerEntity, 1, 0)
        advance(0.31)
        check(unit.CurrentTargetName == nearerEntity.Name and first.Hp == 190 and nearer.Hp == 220,
            "retargeting leaves the accepted attack locked to its original target")
    end)
end)
if clockOwned and isvalid(session) then
    local released, releaseDetail = pcall(function() session:EndManualSimulation() end)
    clockOwned = false
    if not released then check(false, "clock cleanup: " .. tostring(releaseDetail)) end
end
if not ok then check(false, "probe raised: " .. tostring(detail)) end
if failures == 0 then log("[VRF][UnitMotion] PASS")
else log_error("[VRF][UnitMotion] FAILURES=" .. tostring(failures)) end
