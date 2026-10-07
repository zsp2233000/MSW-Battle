-- Run in a fresh Maker Play test after the original MonsterData.csv bytes are restored and refreshed.
-- Execute the complete file in context=server_main; STOP after reading the terminal verdict.
local failures = 0
local function check(condition, message)
    if condition then log("[M1][CatalogRestoreProbe][PASS] " .. message)
    else failures = failures + 1; log_error("[M1][CatalogRestoreProbe][FAIL] " .. message) end
end

local runOk, runDetail = pcall(function()
    local map = _EntityService:GetEntityByPath("/maps/map01")
    local session = isvalid(map) and map:GetComponent("script.BattleSession") or nil
    local catalog = isvalid(map) and map:GetComponent("script.MonsterCatalog") or nil
    check(isvalid(map) and isvalid(session) and isvalid(catalog), "map, BattleSession, and restored catalog are available")
    if not isvalid(map) or not isvalid(session) or not isvalid(catalog) then return end

    local tank = catalog:GetProfile("monster_tank")
    local variant = catalog:GetProfile("probe_tank_variant")
    local options = catalog:GetDeploymentOptions()
    check(tank ~= nil and tank.MonsterId == "monster_tank" and tank.MonsterName == "Tank"
        and tank.MonsterType == "TANK", "original tank profile is restored")
    check(variant == nil, "temporary variant MonsterId is absent after restoration")
    check(#options == 3, "formal deployment catalog contains only the three production rows")
    check(session.Phase == "DEPLOYMENT" and session.PlayerAlive == 0,
        "fresh formal catalog verification starts from the production deployment state")
end)

if not runOk then check(false, "probe raised: " .. tostring(runDetail)) end
if failures == 0 then log("[M1][CatalogRestoreProbe] PASS")
else log_error("[M1][CatalogRestoreProbe] FAILURES=" .. tostring(failures)) end
