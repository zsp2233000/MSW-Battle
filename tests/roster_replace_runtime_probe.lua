-- Run in a fresh Maker Play test, context=server_main, before any deployment or battle started.
-- Dirties the session, then replaces the roster through the Maker test path and the map-placement path;
-- both must leave no residue from the previous roster. Public API only; no private BattleSession state is read.
local map = nil
local session = nil
local failures = 0
local function check(condition, message)
    if condition then log("[M1][RosterReplaceProbe][PASS] " .. message)
    else failures = failures + 1; log_error("[M1][RosterReplaceProbe][FAIL] " .. message) end
end

local function quietProfile()
    return {
        MoveSpeed = 0,
        AttackDamageMin = 0, AttackDamageMax = 0,
        RetargetIntervalSeconds = 0,
        ImpactDelaySeconds = 0,
        AttackIntervalSeconds = 100,
    }
end

local function playerUnit(name)
    return _EntityService:GetEntityByPath("/maps/template/" .. name)
end

local function dirtySession(label)
    -- Deploy two units, start the battle and step it so events, snapshots and the player counter all hold old values.
    check(session:TryDeployMonster("monster_tank", Vector3(-5, 1, 0)) and session:TryDeployMonster("monster_tank", Vector3(-4.4, 1, 0)),
        label .. ": two units deploy")
    check(session.PlayerAlive == 2, label .. ": two player units are registered")
    check(session:TryStartBattle(), label .. ": battle starts")
    session:AdvanceForTest(0.2)
    check(session.Phase == "BATTLE" and session.LastEvent ~= "" and string.find(session.EventHistory, "SESSION_START", 1, true) ~= nil
        and session:GetUnitSnapshots() ~= "", label .. ": session holds old-roster state")
end

local runOk, runDetail = pcall(function()
map = _EntityService:GetEntityByPath("/maps/template")
session = isvalid(map) and map:GetComponent("script.BattleSession") or nil
check(isvalid(map) and isvalid(session), "map and BattleSession are available")
if not isvalid(session) then return end
check(session.Phase == "DEPLOYMENT" and session.PlayerAlive == 0 and session.EnemyAlive == 6,
    "fresh map starts in deployment against six map-placed enemies")
check(session:BeginManualSimulation(), "probe owns the manual clock")

-- Maker test path.
dirtySession("before test-path replacement")
local generation = session.SessionGeneration
local eventSerial = session.EventSerial
check(session:PrepareBattleForTest({}, {
    { monsterId = "monster_warrior", name = "RosterReplace_Enemy", position = Vector3(2, 0, 0), overrides = quietProfile() },
}), "test path accepts a one-enemy roster")
check(session.Phase == "DEPLOYMENT" and session.Result == "" and session.ConfigurationError == ""
    and session.PlayerAlive == 0 and session.EnemyAlive == 1
    and session.InitialPlayerAlive == 0 and session.InitialEnemyAlive == 1,
    "test path: phase, result and counts come from the new roster")
check(session.LastEvent == "" and session.LastEventSourceName == "" and session.LastEventTargetName == ""
    and session.LastEventAmount == 0 and session.EventHistory == "",
    "test path: previous event stream is cleared")
check(session.SessionGeneration == generation + 1 and session.EventSerial == eventSerial,
    "test path: generation advances once and the event serial stays monotonic")
check(not isvalid(playerUnit("M1_Player_1")) and not isvalid(playerUnit("M1_Player_2"))
    and string.find(session:GetUnitSnapshots(), "M1_Player", 1, true) == nil
    and string.find(session:GetUnitSnapshots(), "RosterReplace_Enemy", 1, true) ~= nil
    and string.find(session:GetUnitSnapshots(), "_Unit_", 1, true) == nil,
    "test path: only the new roster is registered and published")
check(session:TryDeployMonster("monster_tank", Vector3(-5, 1, 0)) and isvalid(playerUnit("M1_Player_1")),
    "test path: deployment numbering restarts at one")
check(session:TryRemoveDeployedUnitAt(Vector3(-5, 1, 0)) and session.PlayerAlive == 0,
    "test path: the deployed unit is removed so its position can be reused")

-- Map-placement path.
dirtySession("before map-path replacement")
generation = session.SessionGeneration
eventSerial = session.EventSerial
session:InitializeBattle()
check(session.Phase == "DEPLOYMENT" and session.Result == "" and session.ConfigurationError == ""
    and session.PlayerAlive == 0 and session.EnemyAlive == 6
    and session.InitialPlayerAlive == 0 and session.InitialEnemyAlive == 6,
    "map path: phase, result and counts come from the map placements")
check(session.LastEvent == "DEPLOYMENT_START" and session.EventHistory == "DEPLOYMENT_START:::0"
    and session.EventSerial == eventSerial + 1,
    "map path: only the deployment-start event remains")
check(session.SessionGeneration == generation + 1, "map path: generation advances once")
check(not isvalid(playerUnit("M1_Player_1")) and not isvalid(playerUnit("RosterReplace_Enemy"))
    and string.find(session:GetUnitSnapshots(), "M1_Player", 1, true) == nil
    and string.find(session:GetUnitSnapshots(), "RosterReplace_Enemy", 1, true) == nil,
    "map path: the test roster is gone")
check(session:TryDeployMonster("monster_tank", Vector3(-5, 1, 0)) and isvalid(playerUnit("M1_Player_1")),
    "map path: deployment numbering restarts at one")

-- Leave the template as a fresh deployment for the next probe.
session:InitializeBattle()
check(session.Phase == "DEPLOYMENT" and session.PlayerAlive == 0 and session.EnemyAlive == 6,
    "template restored to a fresh deployment")
end)

if not runOk then check(false, "probe raised: " .. tostring(runDetail)) end
if isvalid(session) then pcall(function() session:EndManualSimulation() end) end

if failures == 0 then
    log("[M1][RosterReplaceProbe] PASS")
else
    log_error("[M1][RosterReplaceProbe] FAILURES=" .. tostring(failures))
end
