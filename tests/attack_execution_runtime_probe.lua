-- Run in a fresh Maker Play test with context=server_main.
-- Exercise real attack composition and full BattleSession steps; no private timer assertions.
local map = _EntityService:GetEntityByPath("/maps/map01")
local session = map:GetComponent("script.BattleSession")
local failures, sequence = 0, 0
local fixtures = {}
local function check(condition, message)
    if condition then log("[AttackExecutionProbe][PASS] " .. message)
    else failures = failures + 1; log_error("[AttackExecutionProbe][FAIL] " .. message) end
end
local function profile(monsterId)
    local copy = {}
    for key, value in pairs(session:GetMonsterProfile(monsterId)) do copy[key] = value end
    copy.MoveSpeed = 0
    copy.ImpactDelaySeconds = 0.18
    copy.AttackIntervalSeconds = 0.8
    return copy
end
local function spawn(monsterId, faction, x, y)
    sequence = sequence + 1
    local data = profile(monsterId)
    local entity = session:SpawnConfiguredUnit(data.ModelId, "AttackProbe_" .. sequence, faction, data, Vector3(x, y, 0))
    table.insert(fixtures, entity)
    local unit = entity:GetComponent("script.BattleUnit")
    unit.AttackRange = 0 -- Stop automatic engagement; the test submits intent through the public module.
    return entity, unit, entity:GetComponent("script.BattleAttackComposition"), data
end
local function cleanup()
    for _, entity in ipairs(fixtures) do
        entity:GetComponent("script.BattleUnit"):CancelAttack()
        entity:Destroy()
    end
    fixtures = {}
end
local function flush()
    session:AdvanceForTest(0.001) -- Full production step resolves accepted native HitEvents.
end
local function pair(monsterId)
    local actor, actorUnit, attack, data = spawn(monsterId, "PLAYER", -1, 0)
    local target, targetUnit = spawn("monster_warrior", "ENEMY", -0.5, 0)
    return actor, actorUnit, attack, data, target, targetUnit
end
if session.BeginManualSimulation == nil then
    log_error("[AttackExecutionProbe][FAIL] manual clock interface is missing")
    return
end
session:BeginManualSimulation()
local ok, detail = pcall(function()
    session:TryDeployMonster("monster_tank", Vector3(-4, 0, 0))
    session:TryDeployMonster("monster_tank", Vector3(-4, -1, 0))
    session:TryStartBattle()
    for _, entity in ipairs(map.Children:ToTable()) do
        if isvalid(entity:GetComponent("script.BattleUnit")) then entity:SetEnable(false) end
    end
    for _, kind in ipairs({"monster_warrior", "monster_shooter"}) do
        local actor, unit, attack, data, target, defender = pair(kind)
        local decoy, decoyUnit = spawn("monster_warrior", "ENEMY", -0.5, 0.15)
        attack:TryEngage(target, true)
        attack:TryEngage(target, true)
        attack:Advance(0.05)
        flush()
        check(unit.AttackSerial == 1 and defender.Hp == 220, kind .. " starts once and preserves pre-impact HP")
        check(string.find(session.EventHistory, "ATTACK_START:" .. actor.Name, 1, true) ~= nil, kind .. " emits attack start")
        attack:Advance(0.14)
        flush()
        local expectedHp = kind == "monster_warrior" and 185 or 190
        check(defender.Hp == expectedHp, kind .. " applies configured damage through HitEvent")
        check(decoyUnit.Hp == (kind == "monster_warrior" and 185 or 220), kind .. " preserves area versus locked-target policy")
        check(string.find(session.EventHistory, "HIT:" .. actor.Name, 1, true) ~= nil and
            string.find(session.EventHistory, "TARGET_HIT:" .. actor.Name, 1, true) ~= nil and
            string.find(session.EventHistory, "DAMAGE:" .. actor.Name .. ":" .. target.Name, 1, true) ~= nil,
            kind .. " preserves native hit presentation semantics")
        cleanup()
    end
    for _, kind in ipairs({"monster_warrior", "monster_shooter"}) do
        local actor, unit, attack, data, target, defender = pair(kind)
        attack:TryEngage(target, true)
        attack:Advance(0.05)
        attack:Cancel("NORMAL")
        attack:Cancel("NORMAL")
        attack:Advance(0.2)
        flush()
        check(defender.Hp == 220, kind .. " cancellation removes pending damage")
        attack:TryEngage(target, true)
        check(unit.AttackSerial == (kind == "monster_warrior" and 1 or 2), kind .. " preserves ordinary cancellation cooldown")
        cleanup()
    end
    do
        local actor, unit, attack, data, target, defender = pair("monster_shooter")
        attack:TryEngage(target, true)
        attack:Advance(0.05)
        target.KinematicbodyComponent:SetWorldPosition(Vector2(3.5, 0))
        attack:Advance(0.2)
        flush()
        check(defender.Hp == 220, "shooter leaving range cancels a pending hit")
        target.KinematicbodyComponent:SetWorldPosition(Vector2(-0.5, 0))
        attack:TryEngage(target, true)
        check(unit.AttackSerial == 2, "shooter can retry immediately after range cancellation")
        target:SetEnable(false)
        attack:Advance(0.2)
        flush()
        check(defender.Hp == 220, "disabled defender cannot receive a pending hit")
        cleanup()
    end
    do
        local actor, unit, attack, data, target, defender = pair("monster_warrior")
        attack:TryEngage(target, true)
        target.KinematicbodyComponent:SetWorldPosition(Vector2(-0.36, 0))
        attack:Advance(0.2)
        flush()
        check(defender.Hp == 185, "warrior preserves the 0.05 impact range tolerance")
        cleanup()
    end
    for _, kind in ipairs({"monster_warrior", "monster_shooter"}) do
        local actor, unit, attack, data, target, defender = pair(kind)
        attack:TryEngage(target, true)
        attack:Advance(0.05)
        check(attack:Configure(data, 0), kind .. " supports reconfiguration on the same actor")
        attack:Advance(0.2)
        flush()
        check(defender.Hp == 220 and unit.AttackSerial == 1, kind .. " clears old pending work without rewinding observations")
        attack:TryEngage(target, true)
        check(unit.AttackSerial == 2, kind .. " reconfiguration clears old cooldown")
        cleanup()
    end
    do
        local actor, unit, attack, data, target, defender = pair("monster_shooter")
        attack:TryEngage(target, true)
        local warrior = profile("monster_warrior")
        check(attack:Configure(warrior, 0), "same actor can switch native attack adapter")
        attack:Advance(0.2)
        flush()
        check(defender.Hp == 220 and unit.AttackSerial == 1, "adapter switch discards the previous shot")
        attack:TryEngage(target, true)
        attack:Advance(0.2)
        flush()
        check(defender.Hp == 185 and unit.AttackSerial == 2, "replacement adapter alone delivers the next hit")
        cleanup()
    end
    do
        local actor, unit, attack, data, target, defender = pair("monster_shooter")
        attack:TryEngage(target, true)
        local tank = profile("monster_tank")
        check(attack:Configure(tank, 0) and unit.UnitKind == "TANK", "switch to tank updates installed attack classification")
        attack:TryEngage(nil, false)
        flush()
        check(defender.Hp == 180 and defender.KnockbackActive, "reconfigured tank contact retains damage and native knockback")
        check(attack:Configure(data, 0) and unit.UnitKind == "SHOOTER", "switch from tank restores shooter classification")
        target:SetEnable(false)
        local replacement, replacementUnit = spawn("monster_warrior", "ENEMY", -0.5, 0)
        attack:TryEngage(replacement, true)
        attack:Advance(0.2)
        flush()
        check(replacementUnit.Hp == 190 and not replacementUnit.KnockbackActive, "reconfigured shooter delivers hitscan damage without tank knockback")
        cleanup()
    end
    do
        local actor, unit, attack, data, target, defender = pair("monster_shooter")
        attack:TryEngage(target, true)
        check(not attack:Configure({ MonsterType = "INVALID" }, 0), "invalid configuration is rejected explicitly")
        attack:Advance(1)
        attack:TryEngage(target, true)
        flush()
        check(defender.Hp == 220 and unit.AttackSerial == 1, "failed configuration leaves no active attack work")
        local warrior = profile("monster_warrior")
        check(attack:Configure(warrior, 0), "configuration can recover with a different native adapter")
        local decoy, decoyUnit = spawn("monster_warrior", "ENEMY", -0.5, 0.15)
        attack:TryEngage(target, true)
        attack:Advance(0.2)
        flush()
        check(defender.Hp == 185, "recovered configuration delivers the new native damage")
        check(decoyUnit.Hp == 185, "recovered warrior preserves area hits after a rejected shooter configuration")
        cleanup()
    end
    for _, kind in ipairs({"monster_tank", "monster_shooter"}) do
        local actor, unit, attack, data, target, defender = pair(kind)
        if kind == "monster_tank" then
            unit:SetMonsterIdentity(unit.MonsterId, unit.MonsterName, session:GetMonsterProfile("monster_shooter").HitEffectRUID)
            check(unit:GetHitEffectRUID() ~= "", "tank fixture has an assigned hit effect that contact must exclude")
        end
        attack:TryEngage(target, true)
        if kind == "monster_shooter" then attack:Advance(0.2) end
        check(defender.Hp == 220, kind .. " accepted native hit waits for the session batch")
        local replacement = profile(kind == "monster_tank" and "monster_shooter" or "monster_tank")
        attack:Configure(replacement, 0)
        if kind == "monster_shooter" then unit:SetMonsterIdentity(unit.MonsterId, unit.MonsterName, "") end
        actor:SetEnable(false) -- Isolate already accepted work from replacement attack intent.
        flush()
        if kind == "monster_tank" then
            check(defender.Hp == 180 and defender.KnockbackActive and defender.CombatState ~= "ON_HIT" and defender.HitEffectSerial == 0,
                "accepted tank hit retains knockback and excludes hit stop after switching to shooter")
        else
            check(defender.Hp == 190 and not defender.KnockbackActive and defender.CombatState == "ON_HIT" and defender.HitEffectSerial == 1,
                "accepted shooter hit retains hit stop and hit effect after switching to tank")
        end
        cleanup()
    end
    for _, kind in ipairs({"monster_warrior", "monster_shooter"}) do
        local actor, unit, attack, data, target, defender = pair(kind)
        attack:Configure(data, 0.12)
        attack:TryEngage(target, true)
        check(unit.AttackSerial == 0, kind .. " opening lead does not announce attack start")
        attack:Advance(0.12)
        attack:TryEngage(target, true)
        check(unit.AttackSerial == 1, kind .. " opening lead is consumed once")
        cleanup()
    end
    do
        local actor, unit, attack, data, target, defender = pair("monster_shooter")
        data.AttackIntervalSeconds = 0.01
        attack:Configure(data, 0)
        unit.AttackRange = 4 -- A new intent would be eligible without the hit-stop gate.
        attack:TryEngage(target, true)
        session:QueueDamage(actor, 1, target)
        flush()
        local serial = unit.AttackSerial
        session:AdvanceForTest(0.19)
        check(defender.Hp == 190 and unit.AttackSerial == serial, "hit stop blocks new intent while existing pending time continues")
        cleanup()
    end
    do
        local actor, unit, attack, data, target, defender = pair("monster_shooter")
        attack:TryEngage(target, true)
        session:QueueDamage(actor, 10000, target)
        flush()
        attack:Advance(0.2)
        flush()
        check(unit.IsDead and defender.Hp == 220, "attacker death discards an unresolved shot")
        cleanup()
    end
    do
        local actor, unit, attack, data, target, defender = pair("monster_shooter")
        attack:TryEngage(target, true)
        session:QueueDamage(target, 10000, actor)
        flush()
        attack:Advance(0.2)
        flush()
        check(defender.IsDead and defender.DamageTakenSerial == 1, "target death before impact prevents another native hit")
        cleanup()
    end
    do
        local actor, unit, attack, data, target, defender = pair("monster_tank")
        local second, secondUnit = spawn("monster_warrior", "ENEMY", -1.3, 0)
        attack:TryEngage(nil, false)
        flush()
        check(defender.Hp == 180 and secondUnit.Hp == 180 and unit.AttackSerial == 2,
            "tank ignores selected-target range and announces each contact defender")
        attack:TryEngage(target, true)
        flush()
        check(defender.Hp == 180 and secondUnit.Hp == 180, "tank cooldown blocks repeated contact independently")
        local third, thirdUnit = spawn("monster_warrior", "ENEMY", -1, 0.3)
        attack:TryEngage(nil, false)
        flush()
        check(thirdUnit.Hp == 180 and unit.AttackSerial == 3, "another defender is not blocked by earlier tank cooldowns")
        cleanup()
    end
    do
        local actor, unit, attack, data, target, defender = pair("monster_shooter")
        attack:TryEngage(target, true)
        session:EnterResult("WIN")
        attack:Advance(1)
        attack:TryEngage(target, true)
        session:AdvanceForTest(1)
        check(defender.Hp == 220 and unit.AttackSerial == 1, "RESULT discards pending hits and blocks new attacks")
        cleanup()
    end
end)
cleanup()
session:EndManualSimulation()
if not ok then check(false, tostring(detail)) end
log("[AttackExecutionProbe] failures=" .. tostring(failures))
