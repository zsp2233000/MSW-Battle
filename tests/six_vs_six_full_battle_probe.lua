-- Run in a fresh Maker Play test with context=server_main.
-- Observe the production roster; observe a complete natural battle and terminal state.
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
if session.Phase == "DEPLOYMENT" then
    for index, monsterId in ipairs(roster) do session:TryDeployMonster(monsterId, positions[index]) end
    session:TryStartBattle()
end
check(session.InitialPlayerAlive == 6 and session.InitialEnemyAlive == 6 and session:IsBattleActive(),
    "mixed six-versus-six battle is active")

local rosterRecords = {}
for _, entity in ipairs(map.Children:ToTable()) do
    local unit = entity:GetComponent("script.BattleUnit")
    if isvalid(unit) then
        table.insert(rosterRecords, { entity = entity, unit = unit, faction = unit.Faction, monsterId = unit.MonsterId })
    end
end
check(#rosterRecords == 12, "observer captures all twelve production roster members")
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
    for index, record in ipairs(rosterRecords) do
        local entity = record.entity
        local unit = record.unit
        local label = record.faction .. " " .. record.monsterId .. " #" .. tostring(index)
        if isvalid(unit) then
            local position = entity:GetComponent("TransformComponent").WorldPosition
            terminal[index] = { hp = unit.Hp, attacks = unit.AttackSerial, x = position.x, y = position.y }
            check(unit.CurrentTargetName == "" and unit.CombatState == "RESULT_STOP",
                label .. " has stopped targeting and movement")
        else
            check(false, label .. " remains inspectable after RESULT")
        end
    end

    _TimerService:SetTimerOnce(function()
        for index, record in ipairs(rosterRecords) do
            local entity = record.entity
            local unit = record.unit
            local before = terminal[index]
            local label = record.faction .. " " .. record.monsterId .. " #" .. tostring(index)
            if isvalid(unit) and before ~= nil then
                local position = entity:GetComponent("TransformComponent").WorldPosition
                check(unit.Hp == before.hp and unit.AttackSerial == before.attacks and
                    position.x == before.x and position.y == before.y,
                    label .. " has no damage, attacks, or movement after RESULT")
            else
                check(false, label .. " remains inspectable after RESULT")
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
