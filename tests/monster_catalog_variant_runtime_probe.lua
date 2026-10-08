-- Fresh Play with the guarded variantStats fixture, context=server_main.
local failures = 0
local clockOwned = false
local session = nil
local function check(condition, message)
    if condition then log("[VRF][CatalogVariant][PASS] " .. message)
    else failures = failures + 1; log_error("[VRF][CatalogVariant][FAIL] " .. message) end
end
local ok, detail = pcall(function()
    local map = _EntityService:GetEntityByPath("/maps/map01")
    session = isvalid(map) and map:GetComponent("script.BattleSession") or nil
    check(isvalid(session), "formal session loads the temporary catalog")
    if not isvalid(session) then return end
    local primary = session:GetMonsterProfile("monster_tank")
    local variant = session:GetMonsterProfile("probe_tank_variant")
    check(primary ~= nil and variant ~= nil, "two same-type identities load independently")
    if primary == nil or variant == nil then return end
    check(primary.MonsterName == "RenamedTank" and primary.MaxHp == 500 and primary.AttackDamage == 40,
        "rename preserves the original ID and combat data")
    check(variant.MonsterName == "VariantTank" and variant.MonsterType == "TANK" and variant.MaxHp == 650
        and variant.MoveSpeed == 0.7 and variant.AttackDamage == 25 and variant.AttackIntervalSeconds == 1.3
        and variant.AttackRange == 0.8 and variant.ContactCooldownSeconds == 1.3,
        "variant loads independently configured numeric values")
    check(primary.StandAnimationRUID == variant.StandAnimationRUID and primary.DieAnimationRUID == variant.DieAnimationRUID,
        "same-type monsters reuse actual resources")
    check(session:TryDeployMonster("monster_tank", Vector3(-4.4, 1, 0))
        and session:TryDeployMonster("probe_tank_variant", Vector3(-3.4, 1, 0)),
        "both identities deploy through the official command")
    local primaryUnit = _EntityService:GetEntityByPath("/maps/map01/M1_Player_1"):GetComponent("script.BattleUnit")
    local variantUnit = _EntityService:GetEntityByPath("/maps/map01/M1_Player_2"):GetComponent("script.BattleUnit")
    check(primaryUnit.MaxHp == 500 and primaryUnit.AttackDamage == 40 and variantUnit.MaxHp == 650
        and variantUnit.AttackDamage == 25 and variantUnit.MoveSpeed == 0.7
        and variantUnit.AttackInterval == 1.3 and variantUnit.AttackRange == 0.8,
        "deployed same-type units retain distinct numeric values")
    clockOwned = session:BeginManualSimulation()
    check(clockOwned, "probe owns the controlled simulation clock")
    if not clockOwned then return end
    check(session:PrepareBattleForTest({
        { monsterId = "monster_tank", name = "Primary", position = Vector3(-1, 0, 0) },
        { monsterId = "probe_tank_variant", name = "Variant", position = Vector3(-1, 0.2, 0) },
    }, { { monsterId = "monster_tank", name = "SharedIdEnemy", position = Vector3(-0.5, 0.1, 0) } }),
        "controlled scene uses two player identities and the original ID on the enemy faction")
    local attacker = _EntityService:GetEntityByPath("/maps/map01/Primary"):GetComponent("script.BattleUnit")
    local second = _EntityService:GetEntityByPath("/maps/map01/Variant"):GetComponent("script.BattleUnit")
    local target = _EntityService:GetEntityByPath("/maps/map01/SharedIdEnemy")
    local defender = target:GetComponent("script.BattleUnit")
    check(session:TryStartBattle(), "controlled variant scene starts")
    attacker:DriveAttack(target, true)
    second:DriveAttack(target, true)
    session:AdvanceForTest(0.01)
    check(defender.Hp == 435 and defender.DamageTakenSerial == 2,
        "native contact hits apply independently configured 40 and 25 damage without modifiers")
end)
if clockOwned and isvalid(session) then session:EndManualSimulation() end
if not ok then check(false, "probe raised: " .. tostring(detail)) end
if failures == 0 then log("[VRF][CatalogVariant] PASS")
else log_error("[VRF][CatalogVariant] FAILURES=" .. tostring(failures)) end
