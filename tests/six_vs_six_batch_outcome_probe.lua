-- Run in Maker Play with context=server_main.
-- Replace the completed match with two isolated production units, then resolve simultaneous final hits.
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

session:EnterResult("WIN")
session:ClearUnits()
local player = session:SpawnMonster("monster_tank", "M1_BatchPlayer", "PLAYER", Vector3(-4, 0, 0))
local enemy = session:SpawnMonster("monster_tank", "M1_BatchEnemy", "ENEMY", Vector3(2, 0, 0))
check(isvalid(player) and isvalid(enemy), "two production units spawn for the batch fixture")
if not isvalid(player) or not isvalid(enemy) then return end

session.PlayerAlive = 1
session.EnemyAlive = 1
session._T.initialized = false -- Keep live OnUpdate out of the deterministic batch fixture.
session.Phase = "BATTLE"
session.Result = ""
session._T.resultEntered = false
session:QueueDamage(player, 10000, nil)
session:QueueDamage(enemy, 10000, nil)
session:ResolveDamageBatch()
check(session.Phase == "BATTLE" and session.Result == "" and
    session.PlayerAlive == 0 and session.EnemyAlive == 0,
    "both factions die in one batch before result evaluation")
local beforeResultSerial = session.EventSerial
session:EvaluateResult()
check(session.Phase == "RESULT" and session.Result == "DRAW",
    "DRAW follows the completed damage batch")
check(session.EventSerial == beforeResultSerial + 1, "DRAW publishes exactly one result")
session:EnterResult("WIN")
check(session.Result == "DRAW" and session.EventSerial == beforeResultSerial + 1,
    "DRAW cannot be overwritten")

if failures == 0 then
    log("[M1][SixVsSixBatch] PASS")
else
    log_error("[M1][SixVsSixBatch] FAILURES=" .. tostring(failures))
end
