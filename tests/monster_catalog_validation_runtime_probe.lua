-- Fresh formal Play, context=server_main. Tests the real catalog row boundary.
-- CSV row adapters vary input cells; production parsing, resources, and validation run unchanged.
local failures = 0
local function check(condition, message)
    if condition then log("[VRF][CatalogValidation][PASS] " .. message)
    else failures = failures + 1; log_error("[VRF][CatalogValidation][FAIL] " .. message) end
end
local ok, detail = pcall(function()
    local map = _EntityService:GetEntityByPath("/maps/template")
    local catalog = isvalid(map) and map:GetComponent("script.MonsterCatalog") or nil
    check(isvalid(catalog), "formal catalog is available")
    if not isvalid(catalog) then return end
    local dataset = _DataService:GetTable("MonsterData")
    local rows = {}
    for index = 1, dataset:GetRowCount() do
        local row = dataset:GetRow(index)
        rows[row:GetItem("MonsterId")] = row
    end
    local function reset()
        check(catalog:Load("MonsterData", {}, { battleunit = true }), "formal CSV reloads after each validation case")
    end
    local function parse(sourceId, overrides)
        reset()
        local source = rows[sourceId]
        local row = { GetItem = function(_, field)
            if overrides[field] ~= nil then return overrides[field] end
            if field == "MonsterId" then return "probe_validation" end
            return source:GetItem(field)
        end }
        return catalog:ParseRow(row, 1)
    end
    for _, case in ipairs({
        { "missing MonsterId", { MonsterId = "" }, "missing MonsterId" },
        { "duplicate MonsterId", { MonsterId = "monster_tank" }, "duplicate MonsterId" },
        { "illegal type", { MonsterType = "INVALID" }, "invalid MonsterType" },
    }) do
        check(parse("monster_tank", case[2]) == nil and string.find(catalog.ErrorMessage, case[3], 1, true) ~= nil,
            case[1] .. " is rejected with its diagnostic")
    end
    for _, field in ipairs({ "MaxHp", "MoveSpeed", "AttackDamageMin", "AttackDamageMax", "AttackIntervalSeconds", "AttackRange", "AttackRangeY",
        "RetargetIntervalSeconds", "HitStopDurationSeconds", "KnockbackDistance" }) do
        check(parse("monster_tank", { [field] = "" }) == nil and string.find(catalog.ErrorMessage, field, 1, true) ~= nil,
            "blank required numeric " .. field .. " is rejected")
        check(parse("monster_tank", { [field] = "invalid" }) == nil, "nonnumeric " .. field .. " is rejected")
    end
    check(parse("monster_tank", { MaxHp = "1.5" }) == nil, "fractional HP is rejected")
    for _, field in ipairs({ "AttackDamageMin", "AttackDamageMax" }) do
        for _, value in ipairs({ "0", "-1", "1.5", "1e999" }) do
            check(parse("monster_tank", { [field] = value }) == nil, field .. " rejects " .. value)
        end
    end
    check(parse("monster_tank", { AttackDamageMin = "13", AttackDamageMax = "12" }) == nil,
        "reversed damage interval is rejected")
    local fixed = parse("monster_tank", { AttackDamageMin = "9", AttackDamageMax = "9" })
    check(fixed ~= nil and fixed.AttackDamageMin == 9 and fixed.AttackDamageMax == 9,
        "equal endpoints are a valid fixed-damage interval")
    check(parse("monster_tank", { MoveSpeed = "1e999" }) == nil, "nonfinite speed is rejected")
    for _, value in ipairs({ "0", "-0.1", "1e999" }) do
        check(parse("monster_tank", { AttackRangeY = value }) == nil, "AttackRangeY rejects " .. value)
    end
    local verticalRange = parse("monster_tank", { AttackRangeY = "0.125" })
    check(verticalRange ~= nil and verticalRange.AttackRangeY == 0.125, "positive AttackRangeY is preserved")
    for _, id in ipairs({ "monster_tank", "monster_warrior", "monster_shooter" }) do
        check(parse(id, { AttackDamageFrame = "" }) == nil, id .. " rejects blank impact frame")
        check(parse(id, { AttackAnimationRUID = "" }) == nil, id .. " rejects blank attack animation")
        check(parse(id, { AttackDamageFrame = "0" }) == nil, id .. " rejects zero impact frame")
        check(parse(id, { AttackDamageFrame = "99999" }) == nil, id .. " rejects an impact frame beyond the actual clip")
    end
    local renamed = parse("monster_tank", { MonsterName = "RenamedOnly" })
    local blankEffect = parse("monster_tank", { AttackEffectRUID = "" })
    check(blankEffect ~= nil and blankEffect.AttackEffectRUID == "", "blank attack effect is optional")
    local effectRUID = rows.monster_warrior:GetItem("HitEffectRUID")
    local attackEffect = parse("monster_tank", { AttackEffectRUID = effectRUID })
    check(attackEffect ~= nil and attackEffect.AttackEffectRUID == effectRUID, "attack effect preserves its animation clip")
    check(parse("monster_tank", { AttackEffectRUID = rows.monster_warrior:GetItem("AttackSoundRUID") }) == nil,
        "attack effect rejects audio resources")
    check(renamed ~= nil and renamed.MonsterName == "RenamedOnly" and renamed.MonsterType == "TANK",
        "name edits do not select a different combat type")
    local reused = parse("monster_tank", { MonsterName = "SharedResources" })
    check(reused ~= nil and reused.StandAnimationRUID == catalog:GetProfile("monster_tank").StandAnimationRUID,
        "a different identity accepts the same actual resource RUIDs")
    reset()
    for _, expected in ipairs({
        { "monster_tank", 400, 0.4, 8, 5, 0.65, 12 },
        { "monster_warrior", 220, 1, 20, 3, 0.6, 30 },
        { "monster_shooter", 120, 0.8, 32, 2, 4, 48 },
    }) do
        local profile = catalog:GetProfile(expected[1])
        check(profile.MaxHp == expected[2] and profile.MoveSpeed == expected[3] and profile.AttackDamageMin == expected[4]
            and profile.AttackDamageMax == expected[7]
            and profile.AttackIntervalSeconds == expected[5] and profile.AttackRange == expected[6],
            expected[1] .. " loads the current formal CSV's independent numeric values")
    end
end)
if not ok then check(false, "probe raised: " .. tostring(detail)) end
if failures == 0 then log("[VRF][CatalogValidation] PASS")
else log_error("[VRF][CatalogValidation] FAILURES=" .. tostring(failures)) end
