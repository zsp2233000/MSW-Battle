-- Fresh Maker Play, server_main.
-- The editor draws the attack range preview from the numbers MonsterCatalog publishes (#60). This proves those numbers
-- describe the very rectangle a facing-right unit attacks with: GetAttackShape is the combat shape, nothing is re-derived.
local failures = 0
local function check(ok, message)
    if ok then log("[M1][RangePreviewProbe][PASS] " .. message)
    else failures = failures + 1; log_error("[M1][RangePreviewProbe][FAIL] " .. message) end
end
local function near(a, b) return math.abs(a - b) < 0.0001 end
local function row(id, name, x, y)
    return { monsterId = id, name = name, position = Vector3(x, y, 0), overrides = { MoveSpeed = 0, AttackDamageMin = 0,
        AttackDamageMax = 0, RetargetIntervalSeconds = 0, AttackIntervalSeconds = 100 } }
end
local session, clockOwned = nil, false
local runOk, runDetail = pcall(function()
    local map = _EntityService:GetEntityByPath("/maps/template")
    session = isvalid(map) and map:GetComponent("script.BattleSession") or nil
    local catalog = isvalid(map) and map:GetComponent("script.MonsterCatalog") or nil
    if not isvalid(session) or not isvalid(catalog) then error("BattleSession or MonsterCatalog unavailable") end
    local options = catalog:GetDeploymentOptions()
    check(#options >= 3, "the catalog publishes every monster")
    local players = {}
    for index, option in ipairs(options) do
        check(option.attackRangeY ~= nil and option.attackRangeY > 0 and option.bodyOffsetX ~= nil and option.bodyOffsetY ~= nil,
            option.monsterId .. " publishes AttackRangeY and the body centre")
        table.insert(players, row(option.monsterId, "Shape" .. index, -3 + (index - 1) * 1.5, 0))
    end
    clockOwned = session:BeginManualSimulation()
    if not clockOwned then error("manual clock unavailable") end
    if not session:PrepareBattleForTest(players, { row("monster_warrior", "FarEnemy", 5, 0) }) or not session:TryStartBattle() then
        error("scene rejected")
    end
    for index, option in ipairs(options) do
        local entity = _EntityService:GetEntityByPath("/maps/template/Shape" .. index)
        local attack = isvalid(entity) and entity:GetComponent("script.BattleAttackComposition") or nil
        check(isvalid(attack), option.monsterId .. " has its combat attack")
        if isvalid(attack) then
            local foot = entity.TransformComponent.WorldPosition
            local shape = attack:GetAttackShape(1)
            check(near(shape.Size.x, option.attackRange) and near(shape.Size.y, option.attackRangeY * 2),
                option.monsterId .. " published size is the combat rectangle size")
            check(near(shape.Position.x - shape.Size.x / 2, foot.x - option.bodyOffsetX) and near(shape.Position.y, foot.y + option.bodyOffsetY),
                option.monsterId .. " published body centre starts the combat rectangle facing right")
        end
    end
end)
if clockOwned and isvalid(session) then session:EndManualSimulation() end
if not runOk then check(false, "probe raised: " .. tostring(runDetail)) end
if failures == 0 then log("[M1][RangePreviewProbe] PASS") else log_error("[M1][RangePreviewProbe] FAILURES=" .. tostring(failures)) end
