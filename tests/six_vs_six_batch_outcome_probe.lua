-- Run in Maker Play with context=server_main.
-- Queue both factions' final accepted hits, then step the complete production batch.
local map = _EntityService:GetEntityByPath("/maps/map01")
local session = isvalid(map) and map:GetComponent("script.BattleSession") or nil
local failures = 0

local function check(condition, message)
    if condition then
        log("[M1][SixVsSixBatch][PASS] " .. message)
    else
        failures = failures + 1
        log_error("[M1][SixVsSixBatch][FAIL] " .. message)
    end
end

if not isvalid(session) then
    log_error("[M1][SixVsSixBatch][FAIL] BattleSession unavailable")
    return
end

local ok, detail = pcall(function()
    session:InitializeBattle()
    session:BeginManualSimulation()
    session:TryDeployMonster("monster_tank", Vector3(-4, 0, 0))
    session:TryStartBattle()
    local player = _EntityService:GetEntityByPath("/maps/map01/M1_Player_1")
    local enemy = _EntityService:GetEntityByPath("/maps/map01/M1_EnemyTank")
    check(isvalid(player) and isvalid(enemy), "production factions spawn for the batch fixture")
    if not isvalid(player) or not isvalid(enemy) then return end

    for _, entity in ipairs(map.Children:ToTable()) do
        local unit = entity:GetComponent("script.BattleUnit")
        if isvalid(unit) then
            unit.MoveSpeed = 0
            session:QueueDamage(entity, 10000, unit.Faction == "PLAYER" and enemy or player)
        end
    end
    session:AdvanceForTest(0.001)
    check(session.Phase == "RESULT" and
        session.PlayerAlive == 0 and session.EnemyAlive == 0,
        "accepted opposing hits survive attacker death in the same complete batch")
    local beforeResultSerial = session.EventSerial
    check(session.Phase == "RESULT" and session.Result == "DRAW",
        "DRAW follows the completed damage batch")
    local resultEvents = 0
    for entry in string.gmatch(session.EventHistory, "[^;]+") do
        if string.sub(entry, 1, 7) == "RESULT:" then resultEvents = resultEvents + 1 end
    end
    check(resultEvents == 1, "DRAW publishes exactly one result")
    session:EnterResult("WIN")
    session:AdvanceForTest(0.1)
    check(session.Result == "DRAW" and session.EventSerial == beforeResultSerial,
        "DRAW cannot be overwritten")
end)
session:EndManualSimulation()
if not ok then check(false, tostring(detail)) end

if failures == 0 then
    log("[M1][SixVsSixBatch] PASS")
else
    log_error("[M1][SixVsSixBatch] FAILURES=" .. tostring(failures))
end
