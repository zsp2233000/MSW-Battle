-- Execute in a fresh Maker Play test with context=server_main during deployment.
-- Keeps the formal six-player deployment against the map's six fixed enemies as the integration check.
local map = nil
local session = nil
local failures = 0
local manualClockOwned = false

local function check(condition, message)
    if condition then log("[M1][SixVsSixProbe][PASS] " .. message)
    else failures = failures + 1; log_error("[M1][SixVsSixProbe][FAIL] " .. message) end
end

local function releaseClockAndCheck()
    if not manualClockOwned then return end
    session:EndManualSimulation()
    manualClockOwned = false
    local reacquired = session:BeginManualSimulation()
    check(reacquired, "six-versus-six setup releases the manual clock")
    if reacquired then session:EndManualSimulation() end
end

local runOk, runDetail = pcall(function()
    map = _EntityService:GetEntityByPath("/maps/map01")
    session = isvalid(map) and map:GetComponent("script.BattleSession") or nil
    if not isvalid(map) or not isvalid(session) then
        check(false, "map and BattleSession are available")
        return
    end
    local acquired = session:BeginManualSimulation()
    check(acquired, "formal deployment probe acquires the manual clock")
    if not acquired then return end
    manualClockOwned = true

    local roster = { "monster_tank", "monster_tank", "monster_warrior", "monster_warrior", "monster_shooter", "monster_shooter" }
    local positions = {
        Vector3(-4.4, 1, 0), Vector3(-4.4, 0, 0), Vector3(-4.4, -1, 0),
        Vector3(-4.4, -2, 0), Vector3(-4.4, -3, 0), Vector3(-3.4, -1, 0),
    }
    check(session.Phase == "DEPLOYMENT", "formal six-versus-six roster starts from deployment")
    for index, monsterId in ipairs(roster) do
        local deployed = session:TryDeployMonster(monsterId, positions[index])
        check(deployed, "official deployment accepts player " .. tostring(index))
        if not deployed then return end
    end

    local started = session:TryStartBattle()
    check(started, "six deployed players start through the formal session command")
    if not started then return end
    check(session.InitialPlayerAlive == 6 and session.InitialEnemyAlive == 6
        and session.PlayerAlive == 6 and session.EnemyAlive == 6,
        "formal six-player roster starts against all six fixed enemies")
    check(session:IsBattleActive(), "the complete twelve-unit roster enters BATTLE")

    local snapshots = session:GetUnitSnapshots()
    for index = 1, 6 do
        check(string.find(snapshots, "M1_Player_" .. tostring(index), 1, true) ~= nil,
            "snapshot contains deployed player " .. tostring(index))
    end
    for _, name in ipairs({ "M1_EnemyTank", "M1_EnemyTank2", "M1_EnemyAssault", "M1_EnemyAssault2", "M1_EnemyShooter", "M1_EnemyShooter2" }) do
        check(string.find(snapshots, name, 1, true) ~= nil, "snapshot contains fixed enemy " .. name)
    end
    for _, monsterId in ipairs({ "monster_tank", "monster_warrior", "monster_shooter" }) do
        check(string.find(snapshots, "monsterId=" .. monsterId, 1, true) ~= nil,
            "snapshot preserves official identity " .. monsterId)
    end

    releaseClockAndCheck()
    wait(0.2)
    check(session.Phase == "BATTLE" and session.InitialPlayerAlive == 6 and session.InitialEnemyAlive == 6,
        "the formal roster remains active on live Maker frames")
end)

if manualClockOwned and session ~= nil then
    local cleanupOk, cleanupDetail = pcall(function() session:EndManualSimulation() end)
    manualClockOwned = false
    if not cleanupOk then check(false, "error cleanup releases the manual clock: " .. tostring(cleanupDetail)) end
end
if not runOk then check(false, "probe raised: " .. tostring(runDetail)) end
if failures == 0 then log("[M1][SixVsSixProbe] PASS")
else log_error("[M1][SixVsSixProbe] FAILURES=" .. tostring(failures)) end
