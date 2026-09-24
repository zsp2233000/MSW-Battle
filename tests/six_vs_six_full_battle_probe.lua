-- Run in Maker Play with context=server_main during deployment.
-- Leave the production roster untouched; observe a complete natural battle and its terminal state.
local map = _EntityService:GetEntityByPath("/maps/map01")
local session = isvalid(map) and map:GetComponent("script.BattleSession") or nil
local failures = 0

local function check(condition, message)
    if condition then
        log("[M1][SixVsSixFullBattle][PASS] " .. message)
    else
        failures = failures + 1
        log_error("[M1][SixVsSixFullBattle][FAIL] " .. message)
    end
end

if not isvalid(session) then
    log_error("[M1][SixVsSixFullBattle][FAIL] BattleSession unavailable")
    return
end

local roster = { "monster_tank", "monster_tank", "monster_warrior", "monster_warrior", "monster_shooter", "monster_shooter" }
local positions = { Vector3(-4.4, 1, 0), Vector3(-4.4, 0, 0), Vector3(-4.4, -1, 0), Vector3(-4.4, -2, 0), Vector3(-4.4, -3, 0), Vector3(-3.4, -1, 0) }
for index, monsterId in ipairs(roster) do session:TryDeployMonster(monsterId, positions[index]) end
session:TryStartBattle()

check(session.InitialPlayerAlive == 6 and session.InitialEnemyAlive == 6 and session:IsBattleActive(),
    "mixed six-versus-six starts after deployment")

local rosterNames = {
    "M1_Player_1", "M1_Player_2", "M1_Player_3", "M1_Player_4",
    "M1_Player_5", "M1_Player_6", "M1_EnemyTank", "M1_EnemyTank2",
    "M1_EnemyAssault", "M1_EnemyAssault2", "M1_EnemyShooter", "M1_EnemyShooter2",
}
local elapsed = 0

local function observe()
    if session.Phase ~= "RESULT" and elapsed < 45 then
        elapsed = elapsed + 1
        _TimerService:SetTimerOnce(observe, 1)
        return
    end

    check(session.Phase == "RESULT" and
        (session.Result == "WIN" or session.Result == "LOSE" or session.Result == "DRAW"),
        "natural battle reaches one result within 45 seconds")
    if session.Phase ~= "RESULT" then
        log_error("[M1][SixVsSixFullBattle] FAILURES=" .. tostring(failures))
        return
    end

    check(session:DetermineResult(session.PlayerAlive, session.EnemyAlive) == session.Result,
        "result matches final alive counts")
    local _, resultEvents = string.gsub(session.EventHistory, "RESULT:::", "")
    check(resultEvents == 1, "exactly one RESULT event is published")

    local terminal = {}
    for _, name in ipairs(rosterNames) do
        local entity = _EntityService:GetEntityByPath("/maps/map01/" .. name)
        local unit = isvalid(entity) and entity:GetComponent("script.BattleUnit") or nil
        if isvalid(unit) then
            local position = entity:GetComponent("TransformComponent").WorldPosition
            terminal[name] = { hp = unit.Hp, attacks = unit.AttackSerial, x = position.x, y = position.y }
            check(unit.CurrentTargetName == "" and unit.CombatState == "RESULT_STOP",
                name .. " has stopped targeting and movement")
        else
            check(false, name .. " remains inspectable after RESULT")
        end
    end

    _TimerService:SetTimerOnce(function()
        for _, name in ipairs(rosterNames) do
            local entity = _EntityService:GetEntityByPath("/maps/map01/" .. name)
            local unit = isvalid(entity) and entity:GetComponent("script.BattleUnit") or nil
            local before = terminal[name]
            if isvalid(unit) and before ~= nil then
                local position = entity:GetComponent("TransformComponent").WorldPosition
                check(unit.Hp == before.hp and unit.AttackSerial == before.attacks and
                    position.x == before.x and position.y == before.y,
                    name .. " has no damage, attacks, or movement after RESULT")
            else
                check(false, name .. " remains inspectable after RESULT")
            end
        end
        if failures == 0 then
            log("[M1][SixVsSixFullBattle] PASS")
        else
            log_error("[M1][SixVsSixFullBattle] FAILURES=" .. tostring(failures))
        end
    end, 1)
end

_TimerService:SetTimerOnce(observe, 1)
