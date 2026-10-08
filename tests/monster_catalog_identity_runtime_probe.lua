-- Run only with the temporary MonsterData.csv fixture installed, in a fresh Maker Play test.
-- Execute the complete file in context=server_main after Stop, Refresh, build logs, and Play.
local failures = 0

local function check(condition, message)
    if condition then
        log("[M1][CatalogIdentityProbe][PASS] " .. message)
    else
        failures = failures + 1
        log_error("[M1][CatalogIdentityProbe][FAIL] " .. message)
    end
end

local function sameExceptIdentity(primary, variant)
    for key, value in pairs(primary) do
        if key ~= "MonsterId" and key ~= "MonsterName" and variant[key] ~= value then return false end
    end
    for key, value in pairs(variant) do
        if key ~= "MonsterId" and key ~= "MonsterName" and primary[key] ~= value then return false end
    end
    return true
end

local runOk, runDetail = pcall(function()
    local map = _EntityService:GetEntityByPath("/maps/map01")
    local session = isvalid(map) and map:GetComponent("script.BattleSession") or nil
    local catalog = isvalid(map) and map:GetComponent("script.MonsterCatalog") or nil
    check(isvalid(map) and isvalid(session) and isvalid(catalog), "map, BattleSession, and loaded MonsterCatalog are available")
    if not isvalid(map) or not isvalid(session) or not isvalid(catalog) then return end

    local primaryProfile = catalog:GetProfile("monster_tank")
    local variantProfile = catalog:GetProfile("probe_tank_variant")
    check(primaryProfile ~= nil and variantProfile ~= nil, "both temporary MonsterIds are present in the formally loaded catalog")
    if primaryProfile == nil or variantProfile == nil then return end
    check(primaryProfile.MonsterId == "monster_tank" and primaryProfile.MonsterName == "RenamedTank",
        "renaming preserves the original MonsterId")
    check(variantProfile.MonsterId == "probe_tank_variant" and variantProfile.MonsterName == "VariantTank"
        and variantProfile.MonsterType == primaryProfile.MonsterType and sameExceptIdentity(primaryProfile, variantProfile),
        "the cloned row preserves all combat data while sharing TANK type under a different MonsterId")

    local optionsById = {}
    local options = catalog:GetDeploymentOptions()
    for _, option in ipairs(options) do optionsById[option[1]] = option[2] end
    check(#options == 4 and optionsById.monster_tank == "RenamedTank"
        and optionsById.probe_tank_variant == "VariantTank",
        "official deployment options expose both names as separate catalog identities")

    check(session:TryDeployMonster("monster_tank", Vector3(-4.4, 1, 0)),
        "original MonsterId deploys through TryDeployMonster")
    check(session:TryDeployMonster("probe_tank_variant", Vector3(-3.4, 1, 0)),
        "same-type variant MonsterId deploys independently through TryDeployMonster")
    local primaryEntity = _EntityService:GetEntityByPath("/maps/map01/M1_Player_1")
    local variantEntity = _EntityService:GetEntityByPath("/maps/map01/M1_Player_2")
    local primaryUnit = isvalid(primaryEntity) and primaryEntity:GetComponent("script.BattleUnit") or nil
    local variantUnit = isvalid(variantEntity) and variantEntity:GetComponent("script.BattleUnit") or nil
    check(isvalid(primaryUnit) and isvalid(variantUnit), "both production deployment entities are queryable")
    if isvalid(primaryUnit) and isvalid(variantUnit) then
        check(primaryUnit.MonsterId == "monster_tank" and primaryUnit.MonsterName == "RenamedTank"
            and primaryUnit.UnitKind == "TANK",
            "primary deployed unit keeps the renamed catalog name and stable MonsterId")
        check(variantUnit.MonsterId == "probe_tank_variant" and variantUnit.MonsterName == "VariantTank"
            and variantUnit.UnitKind == "TANK" and primaryUnit.MonsterId ~= variantUnit.MonsterId,
            "variant deployed unit keeps its distinct MonsterId and name under the same MonsterType")
        check(session.PlayerAlive == 2, "both catalog identities are registered as deployed players")
    end
end)

if not runOk then check(false, "probe raised: " .. tostring(runDetail)) end
if failures == 0 then
    log("[M1][CatalogIdentityProbe] PASS")
else
    log_error("[M1][CatalogIdentityProbe] FAILURES=" .. tostring(failures))
end
