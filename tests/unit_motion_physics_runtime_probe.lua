-- Fresh Maker Play, server_main. Native attacks enqueue work; real frames prove displacement.
local session = nil
local map = nil
local clockOwned = false
local failures = 0
local changedTiles = nil
local function check(condition, message)
    if condition then log("[VRF][UnitMotionPhysics][PASS] " .. message)
    else failures = failures + 1; log_error("[VRF][UnitMotionPhysics][FAIL] " .. message) end
end
local function row(id, name, x, y, extra)
    local profile = { MoveSpeed = 0, AttackDamage = 0, AttackRange = 0,
        RetargetIntervalSeconds = 0, AttackIntervalSeconds = 100 }
    for key, value in pairs(extra or {}) do profile[key] = value end
    return { monsterId = id, name = name, position = Vector3(x, y, 0), overrides = profile }
end
local function actor(name)
    local entity = _EntityService:GetEntityByPath("/maps/map01/" .. name)
    return entity, entity:GetComponent("script.BattleUnit")
end
local function release()
    if clockOwned then session:EndManualSimulation(); clockOwned = false end
end
local function prepare(players, enemies)
    release()
    if not session:BeginManualSimulation() then error("manual clock unavailable") end
    clockOwned = true
    if not session:PrepareBattleForTest(players, enemies) then error("scene rejected") end
    if not session:TryStartBattle() then error("battle did not start") end
end
local function step()
    session:AdvanceForTest(1 / 60)
end
local function position(entity)
    local p = entity.TransformComponent.WorldPosition
    return Vector2(p.x, p.y)
end
local function configureAttack(entity, id, damage)
    local profile = session:GetMonsterProfile(id)
    profile.AttackDamage = damage or 0
    profile.AttackIntervalSeconds = 100
    profile.ImpactDelaySeconds = 0.01
    if not entity:GetComponent("script.BattleAttackComposition"):Configure(profile, 0) then error("attack configuration rejected") end
end
local function contact(attackerEntity, attacker)
    configureAttack(attackerEntity, "monster_tank", 1)
    attacker:DriveAttack(nil, false)
    -- Change future intent while preserving the already accepted contact and knockback batch.
    configureAttack(attackerEntity, "monster_shooter", 0)
    step()
end

local ok, detail = pcall(function()
    map = _EntityService:GetEntityByPath("/maps/map01")
    session = isvalid(map) and map:GetComponent("script.BattleSession") or nil
    if not isvalid(session) then error("BattleSession unavailable") end

    for _, id in ipairs({ "monster_tank", "monster_warrior", "monster_shooter" }) do
        local profile = session:GetMonsterProfile(id)
        local range = profile.AttackRange
        prepare({ row(id, "Pursuer", -4, 0, { MoveSpeed = 1, AttackRange = range }) }, {
            row("monster_warrior", "StationaryTarget", -4 + range + 1, 0),
        })
        local source, unit = actor("Pursuer")
        local target = actor("StationaryTarget")
        target.HitComponent.Enable = false -- Keep the motion fixture stationary during native attack queries.
        local start = position(source)
        release()
        wait(1.6)
        local arrived = position(source)
        check(arrived.x > start.x + 0.8, id .. " pursues on real RectTile frames")
        check(math.abs(position(target).x - arrived.x - range) < 0.06,
            id .. " stops at its configured range")
        wait(0.2)
        check(math.abs(position(source).x - arrived.x) < 0.001, id .. " remains stopped inside range")
        if id == "monster_shooter" then
            target.KinematicbodyComponent:SetWorldPosition(Vector2(arrived.x + 0.3, arrived.y))
            wait(0.2)
            check(math.abs(position(source).x - arrived.x) < 0.001, "shooter does not retreat from a closer target")
        end
    end

    for _, faction in ipairs({ "PLAYER", "ENEMY" }) do
        local attacking = row("monster_warrior", "ColocatedAttacker", 0, 0)
        local receiving = row("monster_warrior", "ColocatedReceiver", 0, 0)
        if faction == "PLAYER" then prepare({ attacking }, { receiving })
        else prepare({ receiving }, { attacking }) end
        local source, attacker = actor("ColocatedAttacker")
        local target, receiver = actor("ColocatedReceiver")
        contact(source, attacker)
        check(receiver.KnockbackActive and receiver.Hp == 219, "native contact accepts a colocated pulse for " .. faction)
        local start = position(target)
        release()
        wait(0.15)
        local after = position(target)
        check((faction == "PLAYER" and after.x > start.x + 0.1)
            or (faction == "ENEMY" and after.x < start.x - 0.1),
            "colocated knockback preserves the " .. faction .. " direction")
        check(not receiver.KnockbackActive and target.KinematicbodyComponent.MoveVelocity.x == 0,
            "completed pulse stops native velocity for " .. faction)
    end

    prepare({ row("monster_warrior", "ZeroFactorAttacker", -0.3, 0) }, {
        row("monster_warrior", "ZeroFactorReceiver", 0, 0),
    })
    local zeroSource, zeroAttacker = actor("ZeroFactorAttacker")
    local zeroTarget, zeroReceiver = actor("ZeroFactorReceiver")
    zeroTarget.KinematicbodyComponent.SpeedFactor = Vector2(0, 1)
    contact(zeroSource, zeroAttacker)
    step()
    release()
    wait(0.1)
    check(not zeroReceiver.KnockbackActive and math.abs(position(zeroTarget).x) < 0.001
        and zeroTarget.KinematicbodyComponent.MoveVelocity.x == 0,
        "zero SpeedFactor cancels the pulse without invalid velocity or displacement")

    prepare({ row("monster_warrior", "LeftPulse", -0.3, 0), row("monster_warrior", "RightPulse", 0.3, 0) }, {
        row("monster_warrior", "PulseReceiver", 0, 0),
    })
    local left, leftUnit = actor("LeftPulse")
    local right, rightUnit = actor("RightPulse")
    local receivingEntity, receivingUnit = actor("PulseReceiver")
    -- The manual clock does not pause physics; hold only this Body while inspecting pulse replacement.
    receivingEntity.KinematicbodyComponent.Enable = false
    contact(left, leftUnit)
    step()
    check(receivingEntity.KinematicbodyComponent.MoveVelocity.x > 12,
        "first pulse sets the expected forward native velocity")
    -- The second native contact overwrites an unfinished first pulse at the same position.
    right.KinematicbodyComponent:SetWorldPosition(Vector2(0.2, 0))
    contact(right, rightUnit)
    step()
    check(receivingUnit.KnockbackActive and receivingEntity.KinematicbodyComponent.MoveVelocity.x < -12,
        "replacement pulse reverses at full speed instead of accumulating displacement")
    check(receivingUnit.CurrentTargetName == right.Name and receivingUnit.CombatState == "MOVE",
        "unfinished knockback still permits normal retargeting and pursuit intent")
    receivingEntity.KinematicbodyComponent.Enable = true
    release()
    wait(0.15)
    check(position(receivingEntity).x < -0.1 and not receivingUnit.KnockbackActive,
        "replacement pulse travels and finishes on real frames")

    -- Reuse the map's existing collidable border tile as a temporary runtime wall.
    local tiles = map:GetChildByName("RectTileMap", true).RectTileMapComponent
    local wall = tiles:GetTile(Vector2Int(15, 0))
    check(wall ~= nil and wall.IsCollidable, "runtime wall fixture uses the existing collidable tile")
    if wall == nil or not wall.IsCollidable then error("collidable tile unavailable") end
    changedTiles = tiles
    tiles:SetTile(wall.Name, Vector2Int(1, 0))
    local wallCenter = tiles:ToWorldPosition(Vector2Int(1, 0))
    local wallEdge = wallCenter.x - tiles.GridSize.x / 2
    prepare({ row("monster_warrior", "WallContact", wallEdge - 0.6, wallCenter.y) }, {
        row("monster_warrior", "WallReceiver", wallEdge - 0.3, wallCenter.y),
    })
    local wallSource, wallAttacker = actor("WallContact")
    local wallTarget, wallReceiver = actor("WallReceiver")
    contact(wallSource, wallAttacker)
    release()
    wait(0.15)
    local stopped = position(wallTarget)
    check(stopped.x >= wallEdge - 0.301 and stopped.x < wallEdge + 0.001 and not wallReceiver.KnockbackActive,
        "knockback stops before entering a collidable tile on real frames")
    prepare({ row("monster_warrior", "WallPursuer", wallEdge - 0.9, wallCenter.y, { MoveSpeed = 1 }) }, {
        row("monster_warrior", "WallGoal", wallEdge + 0.9, wallCenter.y),
    })
    local wallPursuer = actor("WallPursuer")
    release()
    wait(1.4)
    check(position(wallPursuer).x > wallEdge - 0.8 and position(wallPursuer).x < wallEdge + 0.001,
        "straight pursuit respects native tile collision without pathfinding")
    tiles:Reset()
    changedTiles = nil

    prepare({ row("monster_shooter", "PausedReceiver", 0, 0, { AttackRange = 4, AttackDamage = 30,
        ImpactDelaySeconds = 0.04 }) }, {
        row("monster_warrior", "PauseContact", -0.3, 0),
        row("monster_shooter", "PauseHit", 2, 0),
    })
    local pausedEntity, paused = actor("PausedReceiver")
    local contactEntity, contactUnit = actor("PauseContact")
    local hitEntity, hitUnit = actor("PauseHit")
    paused.AttackRange = 0
    paused:DriveAttack(hitEntity, true)
    configureAttack(hitEntity, "monster_shooter", 1)
    hitUnit:DriveAttack(pausedEntity, true)
    hitUnit:AdvanceAttack(0.02)
    contact(contactEntity, contactUnit)
    check(paused.CombatState == "ON_HIT" and paused.KnockbackActive, "hit stop and knockback coexist after native hits")
    local before = position(pausedEntity)
    release()
    wait(0.1)
    check(position(pausedEntity).x > before.x + 0.1 and paused.CombatState == "ON_HIT",
        "knockback travels during hit stop on real frames")
    check(hitUnit.Hp == 90 and hitUnit.DamageTakenSerial == 1,
        "accepted attack reaches impact during hit stop and knockback")

    -- Reconfigure through the existing actor interface while motion is still paused.
    if not session:BeginManualSimulation() then error("reconfiguration clock unavailable") end
    clockOwned = true
    local replacement = session:GetMonsterProfile("monster_warrior")
    replacement.MoveSpeed = 0
    check(paused:Configure("PLAYER", replacement.MonsterName, replacement, 0), "actor reconfiguration succeeds")
    check(paused:GetCurrentTarget() == nil and paused.CurrentTargetName == "" and not paused.KnockbackActive
        and pausedEntity.KinematicbodyComponent.MoveVelocity.x == 0,
        "actor reconfiguration clears old target, hit stop and displacement work")
    step()
    check(paused.CombatState ~= "ON_HIT", "reconfigured actor acquires without an old hit-stop delay")

    prepare({ row("monster_warrior", "LethalContact", -0.3, 0) }, {
        row("monster_warrior", "DyingReceiver", 0, 0, { MaxHp = 1 }),
        row("monster_warrior", "LivingReserve", 3, 0),
    })
    local lethalEntity, lethal = actor("LethalContact")
    local dyingEntity, dying = actor("DyingReceiver")
    contact(lethalEntity, lethal)
    local deathPosition = position(dyingEntity)
    release()
    wait(0.15)
    check(dying.IsDead and not dying.KnockbackActive and dying.CurrentTargetName == ""
        and dying:GetCurrentTarget() == nil and session.Phase == "BATTLE"
        and math.abs(position(dyingEntity).x - deathPosition.x) < 0.001,
        "death clears an accepted pulse and target while the surviving roster remains in battle")
end)
local cleanupOk, cleanupDetail = pcall(release)
if not cleanupOk then check(false, "clock cleanup: " .. tostring(cleanupDetail)) end
if isvalid(changedTiles) then
    local resetOk, resetDetail = pcall(function() changedTiles:Reset() end)
    if not resetOk then check(false, "tile cleanup: " .. tostring(resetDetail)) end
end
if not ok then check(false, "probe raised: " .. tostring(detail)) end
if failures == 0 then log("[VRF][UnitMotionPhysics] PASS")
else log_error("[VRF][UnitMotionPhysics] FAILURES=" .. tostring(failures)) end
