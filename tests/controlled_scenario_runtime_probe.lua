-- Run in a fresh Maker Play test, context=server_main.
-- Exercises the public controlled-scene API; no private BattleSession state is read.
local map = nil
local session = nil
local failures = 0
local function check(condition, message)
    if condition then log("[M1][ControlledScenarioProbe][PASS] " .. message)
    else failures = failures + 1; log_error("[M1][ControlledScenarioProbe][FAIL] " .. message) end
end

local runOk, runDetail = pcall(function()
map = _EntityService:GetEntityByPath("/maps/map01")
session = isvalid(map) and map:GetComponent("script.BattleSession") or nil
check(isvalid(map) and isvalid(session), "map and BattleSession are available")
if not isvalid(session) then return end

local function row(monsterId, name, position, overrides)
    return { monsterId = monsterId, name = name, position = position, overrides = overrides }
end

local function quietProfile()
    return {
        MoveSpeed = 0,
        AttackDamage = 0,
        AttackRange = 0,
        RetargetIntervalSeconds = 0,
        ImpactDelaySeconds = 0,
        AttackIntervalSeconds = 100,
    }
end

local function tankContactProfile(damage)
    local result = quietProfile()
    result.AttackDamage = damage
    return result
end

local function capturePublicState(includeSnapshotSerial)
    local values = {
        session.Phase,
        session.Result,
        session.PlayerAlive,
        session.EnemyAlive,
        session.InitialPlayerAlive,
        session.InitialEnemyAlive,
        session.ConfigurationError,
        session.SessionGeneration,
    }
    if includeSnapshotSerial ~= false then values[#values + 1] = session.SnapshotSerial end
    values[#values + 1] = session.EventSerial
    local remainingValues = {
        session.LastEvent,
        session.LastEventSourceName,
        session.LastEventTargetName,
        session.LastEventAmount,
        session.EventHistory,
        session:GetDebugSnapshot(),
        session:GetUnitSnapshots(),
    }
    for _, value in ipairs(remainingValues) do values[#values + 1] = value end
    local parts = {}
    for index, value in ipairs(values) do parts[index] = tostring(value) end
    return table.concat(parts, "\31")
end

local function manualCase(label, callback, expectThrow)
    local acquired = session:BeginManualSimulation()
    if not acquired then
        check(false, label .. " checks and acquires the manual clock")
        return false
    end

    local ok, detail = pcall(callback)
    local releaseOk, releaseDetail = pcall(function() session:EndManualSimulation() end)
    if not releaseOk then check(false, label .. " clock release raised: " .. tostring(releaseDetail)) end
    if expectThrow == true then
        check(not ok, label .. " throwing case releases its owned clock")
        return not ok
    end
    if not ok then
        check(false, label .. " raised: " .. tostring(detail))
        return false
    end
    return true
end

local function rejectUnchanged(label, playerRoster, enemyRoster)
    local before = capturePublicState()
    local accepted = session:PrepareBattleForTest(playerRoster, enemyRoster)
    check(accepted == false and capturePublicState() == before, label)
end

local function numberedRoster(count, prefix, monsterId)
    local roster = {}
    for index = 1, count do
        roster[index] = row(monsterId, prefix .. tostring(index), Vector3(0, 0, 0), quietProfile())
    end
    return roster
end

log("[M1][ControlledScenarioProbe] Vector3 runtime type=" .. tostring(type(Vector3(0, 0, 0))))

-- The method must not acquire the clock itself or mutate the current fixed deployment.
local noClockOk, noClockDetail = pcall(function()
    local before = capturePublicState(false)
    local accepted = session:PrepareBattleForTest(
        { row("monster_tank", "NoClockPlayer", Vector3(-4, 0, 0)) },
        { row("monster_warrior", "NoClockEnemy", Vector3(2, 0, 0)) }
    )
    check(accepted == false and capturePublicState(false) == before,
        "preparation without a manual clock preserves the scene")
    local acquired = session:BeginManualSimulation()
    check(acquired, "preparation without a manual clock leaves the clock available")
    if acquired then session:EndManualSimulation() end
end)
if not noClockOk then check(false, "no-clock checks raised: " .. tostring(noClockDetail)) end

manualCase("valid 1v1 scene", function()
    local playerSource = session:GetMonsterProfile("monster_warrior")
    local enemySource = session:GetMonsterProfile("monster_shooter")
    local generation = session.SessionGeneration
    local eventSerial = session.EventSerial
    local snapshotSerial = session.SnapshotSerial
    local accepted = session:PrepareBattleForTest(
        { row("monster_warrior", "Issue15_ProfilePlayer", Vector3(-0.5, 0, 0), {
            MonsterName = "Probe Assault",
            MaxHp = 333,
            AttackDamage = 0,
            MoveSpeed = 0,
            AttackRange = 2,
            RetargetIntervalSeconds = 0,
            ImpactDelaySeconds = 0,
            AttackIntervalSeconds = 2.5,
        }) },
        { row("monster_shooter", "Issue15_ProfileEnemy", Vector3(0.5, 0, 0), {
            MonsterName = "Probe Shooter",
            MaxHp = 444,
            AttackDamage = 0,
            MoveSpeed = 0,
            AttackRange = 2,
            RetargetIntervalSeconds = 0,
            ImpactDelaySeconds = 0,
            AttackIntervalSeconds = 2.5,
        }) }
    )
    check(accepted, "valid 1v1 scene is prepared")
    check(session.Phase == "DEPLOYMENT" and session.PlayerAlive == 1 and session.EnemyAlive == 1
        and session.InitialPlayerAlive == 0 and session.InitialEnemyAlive == 1,
        "valid scene counts and initial counts are correct")
    check(session.SessionGeneration == generation + 1 and session.EventSerial == eventSerial
        and session.SnapshotSerial == snapshotSerial + 1 and session.LastEvent == ""
        and session.EventHistory == "",
        "scene generation increments once while event history and monotonic serials are preserved")

    local playerEntity = _EntityService:GetEntityByPath("/maps/map01/Issue15_ProfilePlayer")
    local enemyEntity = _EntityService:GetEntityByPath("/maps/map01/Issue15_ProfileEnemy")
    local playerUnit = isvalid(playerEntity) and playerEntity:GetComponent("script.BattleUnit") or nil
    local enemyUnit = isvalid(enemyEntity) and enemyEntity:GetComponent("script.BattleUnit") or nil
    check(isvalid(playerUnit) and playerUnit.Faction == "PLAYER" and playerUnit.MonsterId == "monster_warrior"
        and playerUnit.UnitKind == playerSource.MonsterType and playerUnit.MonsterName == "Probe Assault"
        and playerUnit.MaxHp == 333 and playerUnit.Hp == 333 and playerUnit.AttackDamage == 0
        and playerUnit.MoveSpeed == 0 and playerUnit.AttackRange == 2 and playerUnit.RetargetInterval == 0
        and playerUnit.ImpactDelay == 0 and playerUnit.AttackInterval == 2.5
        and playerUnit.StandAnimationRUID == playerSource.StandAnimationRUID,
        "player profile overrides apply while catalog identity and animation data stay authoritative")
    check(isvalid(enemyUnit) and enemyUnit.Faction == "ENEMY" and enemyUnit.MonsterId == "monster_shooter"
        and enemyUnit.UnitKind == enemySource.MonsterType and enemyUnit.MonsterName == "Probe Shooter"
        and enemyUnit.MaxHp == 444 and enemyUnit.Hp == 444 and enemyUnit.AttackDamage == 0
        and enemyUnit.MoveSpeed == 0 and enemyUnit.AttackRange == 2 and enemyUnit.RetargetInterval == 0
        and enemyUnit.ImpactDelay == 0 and enemyUnit.AttackInterval == 2.5
        and enemyUnit.StandAnimationRUID == enemySource.StandAnimationRUID,
        "enemy faction and profile are selected from its roster")
    local playerAfter = session:GetMonsterProfile("monster_warrior")
    check(playerAfter.MonsterName == playerSource.MonsterName and playerAfter.MaxHp == playerSource.MaxHp
        and playerAfter.AttackDamage == playerSource.AttackDamage,
        "test overrides do not mutate catalog profiles")
    check(session:TryStartBattle() and session.InitialPlayerAlive == 1 and session.InitialEnemyAlive == 1,
        "TryStartBattle records the prepared 1v1 counts")
    session:AdvanceForTest(0.05)
    check(playerUnit.AttackSerial > 0 and enemyUnit.AttackSerial == 0,
        "enemy opening delay remains active after test-scene preparation")
end)

manualCase("zero-player scene cannot start", function()
    check(session:PrepareBattleForTest({}, {
        row("monster_warrior", "Issue15_ZeroEnemy", Vector3(2, 0, 0), quietProfile()),
    }), "zero-player scene is prepared")
    check(session.Phase == "DEPLOYMENT" and session.PlayerAlive == 0 and session.EnemyAlive == 1
        and session.InitialPlayerAlive == 0 and session.InitialEnemyAlive == 1,
        "zero-player scene cannot start and keeps its enemy count")
    check(not session:TryStartBattle() and session.Phase == "DEPLOYMENT" and session.PlayerAlive == 0,
        "zero-player scene cannot start")
end)

manualCase("overlapping deployment positions", function()
    check(session:PrepareBattleForTest(
        { row("monster_tank", "Issue15_OverlapPlayer", Vector3(0, 0, 0), quietProfile()) },
        { row("monster_warrior", "Issue15_OverlapEnemy", Vector3(0, 0, 0), quietProfile()) }
    ), "overlapping deployment positions are accepted")
    check(session.PlayerAlive == 1 and session.EnemyAlive == 1,
        "overlapping positions retain both roster entries")
end)

manualCase("arena boundary position", function()
    check(session:PrepareBattleForTest(
        { row("monster_tank", "Issue15_BoundaryPlayer", Vector3(-5.5, 1.5, 0), quietProfile()) },
        { row("monster_warrior", "Issue15_BoundaryEnemy", Vector3(3.5, -3.5, 0), quietProfile()) }
    ), "arena boundary position is accepted outside normal deployment limits")
    check(session.PlayerAlive == 1 and session.EnemyAlive == 1 and session.Phase == "DEPLOYMENT",
        "arena-boundary scene remains in deployment")
end)

manualCase("invalid input preserves the active public state and pending work", function()
    check(session:PrepareBattleForTest(
        { row("monster_tank", "Issue15_StablePlayer", Vector3(-0.4, 0, 0), tankContactProfile(9)) },
        { row("monster_warrior", "Issue15_StableEnemy", Vector3(0, 0, 0), quietProfile()) }
    ), "stable baseline scene is prepared")
    check(session:TryStartBattle(), "stable baseline enters battle")
    local playerEntity = _EntityService:GetEntityByPath("/maps/map01/Issue15_StablePlayer")
    local enemyEntity = _EntityService:GetEntityByPath("/maps/map01/Issue15_StableEnemy")
    local playerUnit = isvalid(playerEntity) and playerEntity:GetComponent("script.BattleUnit") or nil
    local enemyUnit = isvalid(enemyEntity) and enemyEntity:GetComponent("script.BattleUnit") or nil
    check(isvalid(playerUnit) and isvalid(enemyUnit), "stable baseline units are queryable")
    if not isvalid(playerUnit) or not isvalid(enemyUnit) then return end

    local hpBeforePendingHit = enemyUnit.Hp
    local damageSerialBeforePendingHit = enemyUnit.DamageTakenSerial
    local playerUnit = playerEntity:GetComponent("script.BattleUnit")
    playerUnit:DriveAttack(enemyEntity, true)
    check(enemyUnit.Hp == hpBeforePendingHit,
        "native tank contact stages hit-event damage before the next complete session step")

    rejectUnchanged("unknown MonsterId in a later row preserves the full prior scene",
        { row("monster_tank", "Issue15_ValidBeforeBad", Vector3(-1, 0, 0), quietProfile()) },
        {
            row("monster_warrior", "Issue15_ValidEnemyBeforeBad", Vector3(0, 0, 0), quietProfile()),
            row("missing_monster", "Issue15_UnknownEnemy", Vector3(1, 0, 0), quietProfile()),
        })
    rejectUnchanged("unknown MonsterId", { row("missing_monster", "Issue15_UnknownPlayer", Vector3(-1, 0, 0)) },
        { row("monster_warrior", "Issue15_UnknownIdEnemy", Vector3(0, 0, 0)) })
    rejectUnchanged("zero-enemy roster", { row("monster_tank", "Issue15_ZeroEnemyPlayer", Vector3(-1, 0, 0)) }, {})
    rejectUnchanged("duplicate team name", { row("monster_tank", "Issue15_Duplicate", Vector3(-1, 0, 0)) },
        { row("monster_warrior", "Issue15_Duplicate", Vector3(0, 0, 0)) })
    rejectUnchanged("empty row name", { row("monster_tank", "   ", Vector3(-1, 0, 0)) },
        { row("monster_warrior", "Issue15_EmptyNameEnemy", Vector3(0, 0, 0)) })
    rejectUnchanged("slash in row name", { row("monster_tank", "Issue15/Bad", Vector3(-1, 0, 0)) },
        { row("monster_warrior", "Issue15_SlashEnemy", Vector3(0, 0, 0)) })
    rejectUnchanged("seventh unit player limit", numberedRoster(7, "Issue15_TooManyPlayer", "monster_tank"),
        { row("monster_warrior", "Issue15_TooManyEnemy", Vector3(0, 0, 0)) })
    rejectUnchanged("seventh unit enemy limit", { row("monster_tank", "Issue15_TooManyPlayerEnemy", Vector3(0, 0, 0)) },
        numberedRoster(7, "Issue15_TooManyEnemy", "monster_warrior"))
    rejectUnchanged("invalid arena coordinates", { row("monster_tank", "Issue15_NanX", Vector3(0 / 0, 0, 0)) },
        { row("monster_warrior", "Issue15_NanXEnemy", Vector3(0, 0, 0)) })
    rejectUnchanged("infinite arena coordinate", { row("monster_tank", "Issue15_InfY", Vector3(0, math.huge, 0)) },
        { row("monster_warrior", "Issue15_InfYEnemy", Vector3(0, 0, 0)) })
    rejectUnchanged("out-of-arena coordinate", { row("monster_tank", "Issue15_Outside", Vector3(-5.5001, 0, 0)) },
        { row("monster_warrior", "Issue15_OutsideEnemy", Vector3(0, 0, 0)) })
    rejectUnchanged("nonzero Z coordinate", { row("monster_tank", "Issue15_BadZ", Vector3(0, 0, 0.001)) },
        { row("monster_warrior", "Issue15_BadZEnemy", Vector3(0, 0, 0)) })
    rejectUnchanged("position must be a Vector3", { row("monster_tank", "Issue15_NotVector", { x = 0, y = 0, z = 0 }) },
        { row("monster_warrior", "Issue15_NotVectorEnemy", Vector3(0, 0, 0)) })
    rejectUnchanged("foreign userdata is rejected as a position", { row("monster_tank", "Issue15_ForeignUserdata", map) },
        { row("monster_warrior", "Issue15_ForeignUserdataEnemy", Vector3(0, 0, 0)) })
    rejectUnchanged("unknown profile override", { row("monster_tank", "Issue15_UnknownOverride", Vector3(0, 0, 0), { ModelId = "battleunit" }) },
        { row("monster_warrior", "Issue15_UnknownOverrideEnemy", Vector3(1, 0, 0)) })

    local invalidOverrides = {
        { MonsterName = "   " },
        { MaxHp = 0 },
        { MaxHp = 1.5 },
        { MaxHp = math.huge },
        { AttackDamage = -1 },
        { AttackDamage = 1.5 },
        { MoveSpeed = -0.1 },
        { MoveSpeed = 0 / 0 },
        { AttackRange = -1 },
        { RetargetIntervalSeconds = -1 },
        { RetargetIntervalSeconds = math.huge },
        { ImpactDelaySeconds = -1 },
        { ImpactDelaySeconds = math.huge },
        { AttackIntervalSeconds = 0 },
        { AttackIntervalSeconds = -1 },
        { AttackIntervalSeconds = math.huge },
        { AttackIntervalSeconds = "1" },
    }
    for index, overrides in ipairs(invalidOverrides) do
        rejectUnchanged("invalid numeric overrides " .. tostring(index),
            { row("monster_tank", "Issue15_BadOverride" .. tostring(index), Vector3(-1, 0, 0), overrides) },
            { row("monster_warrior", "Issue15_BadOverrideEnemy" .. tostring(index), Vector3(0, 0, 0)) })
    end

    session:AdvanceForTest(0.01)
    check(enemyUnit.Hp == hpBeforePendingHit - 9 and enemyUnit.DamageTakenSerial == damageSerialBeforePendingHit + 1
        and enemyUnit.KnockbackActive,
        "validation failures preserve native pending damage and knockback until a complete session step")
end)

manualCase("scene switch discards queued old-scene work", function()
    check(session:PrepareBattleForTest(
        { row("monster_tank", "Issue15_OldPlayer", Vector3(-0.4, 0, 0), tankContactProfile(17)) },
        { row("monster_warrior", "Issue15_OldEnemy", Vector3(0, 0, 0), quietProfile()) }
    ), "old scene is prepared")
    check(session:TryStartBattle(), "old scene starts before work is queued")
    local oldPlayer = _EntityService:GetEntityByPath("/maps/map01/Issue15_OldPlayer")
    local oldEnemy = _EntityService:GetEntityByPath("/maps/map01/Issue15_OldEnemy")
    check(isvalid(oldPlayer) and isvalid(oldEnemy), "old scene units are available")
    if not isvalid(oldPlayer) or not isvalid(oldEnemy) then return end

    local oldEnemyUnit = oldEnemy:GetComponent("script.BattleUnit")
    local oldPlayerUnit = oldPlayer:GetComponent("script.BattleUnit")
    oldPlayerUnit:DriveAttack(oldEnemy, true)
    check(oldEnemyUnit.Hp == oldEnemyUnit.MaxHp,
        "native tank HitEvent stages old-scene damage before a complete session step")
    local generation = session.SessionGeneration
    local eventSerial = session.EventSerial
    check(session:PrepareBattleForTest(
        { row("monster_warrior", "Issue15_NewPlayer", Vector3(-4, 0, 0), quietProfile()) },
        { row("monster_shooter", "Issue15_NewEnemy", Vector3(3, 0, 0), quietProfile()) }
    ), "new scene replaces the active roster")
    check(session.SessionGeneration == generation + 1 and session.EventSerial == eventSerial
        and session.Phase == "DEPLOYMENT" and session.PlayerAlive == 1 and session.EnemyAlive == 1
        and session.InitialPlayerAlive == 0 and session.InitialEnemyAlive == 1
        and session.EventHistory == "" and session.LastEvent == "",
        "scene switch clears history and advances generation without resetting event serial")
    check(not isvalid(_EntityService:GetEntityByPath("/maps/map01/Issue15_OldPlayer"))
        and not isvalid(_EntityService:GetEntityByPath("/maps/map01/Issue15_OldEnemy"))
        and string.find(session:GetUnitSnapshots(), "Issue15_Old", 1, true) == nil,
        "old roster is destroyed before new unit snapshots are published")

    local newPlayer = _EntityService:GetEntityByPath("/maps/map01/Issue15_NewPlayer")
    local newEnemy = _EntityService:GetEntityByPath("/maps/map01/Issue15_NewEnemy")
    local newPlayerUnit = isvalid(newPlayer) and newPlayer:GetComponent("script.BattleUnit") or nil
    local newEnemyUnit = isvalid(newEnemy) and newEnemy:GetComponent("script.BattleUnit") or nil
    check(isvalid(newPlayerUnit) and isvalid(newEnemyUnit), "new roster can be queried by public entity path")
    if not isvalid(newPlayerUnit) or not isvalid(newEnemyUnit) then return end
    local hpBefore = newEnemyUnit.Hp
    check(session:TryStartBattle(), "new scene starts explicitly")
    local serialBeforeWait = session.SnapshotSerial
    wait(0.15)
    check(session.SnapshotSerial == serialBeforeWait and newEnemyUnit.Hp == hpBefore,
        "new scene logic remains paused while the owned manual clock is held")
    local positionBefore = newEnemy.TransformComponent.WorldPosition
    session:AdvanceForTest(0.03)
    local positionAfter = newEnemy.TransformComponent.WorldPosition
    check(session.SnapshotSerial > serialBeforeWait and newEnemyUnit.Hp == hpBefore
        and positionAfter.x == positionBefore.x and positionAfter.y == positionBefore.y,
        "only explicit AdvanceForTest advances the new scene and old damage or knockback cannot leak")
end)

manualCase("throwing case", function()
    error("intentional controlled-scene probe exception")
end, true)
local reacquireOk, reacquireDetail = pcall(function()
    local acquired = session:BeginManualSimulation()
    check(acquired, "throwing case releases its owned clock so it can be reacquired")
    if acquired then session:EndManualSimulation() end
end)
if not reacquireOk then check(false, "clock reacquisition check raised: " .. tostring(reacquireDetail)) end
end)

if not runOk then check(false, "probe raised: " .. tostring(runDetail)) end

if failures == 0 then
    log("[M1][ControlledScenarioProbe] PASS")
else
    log_error("[M1][ControlledScenarioProbe] FAILURES=" .. tostring(failures))
end
