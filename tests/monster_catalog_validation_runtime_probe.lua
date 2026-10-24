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
    for _, field in ipairs({ "MaxHp", "MoveSpeed", "AttackDamage", "AttackIntervalSeconds", "AttackRange",
        "RetargetIntervalSeconds", "HitStopDurationSeconds", "ContactCooldownSeconds", "ContactSizeX", "ContactSizeY", "KnockbackDistance" }) do
        check(parse("monster_tank", { [field] = "" }) == nil and string.find(catalog.ErrorMessage, field, 1, true) ~= nil,
            "blank required numeric " .. field .. " is rejected")
        check(parse("monster_tank", { [field] = "invalid" }) == nil, "nonnumeric " .. field .. " is rejected")
    end
    check(parse("monster_tank", { MaxHp = "1.5" }) == nil, "fractional HP is rejected")
    check(parse("monster_tank", { AttackDamage = "0" }) == nil, "nonpositive damage is rejected")
    check(parse("monster_tank", { MoveSpeed = "1e999" }) == nil, "nonfinite speed is rejected")
    for _, id in ipairs({ "monster_warrior", "monster_shooter" }) do
        local profile = parse(id, { AttackImpactFrame = "" })
        check(profile ~= nil and profile.AttackImpactFrame == 1 and profile.ImpactDelaySeconds == 0,
            id .. " blank impact frame defaults to first-frame impact")
        check(parse(id, { AttackImpactFrame = "0" }) == nil, id .. " rejects zero impact frame")
        check(parse(id, { AttackImpactFrame = "99999" }) == nil, id .. " rejects an impact frame beyond the actual clip")
    end
    local renamed = parse("monster_tank", { MonsterName = "RenamedOnly" })
    check(renamed ~= nil and renamed.MonsterName == "RenamedOnly" and renamed.MonsterType == "TANK",
        "name edits do not select a different combat type")
    local reused = parse("monster_tank", { MonsterName = "SharedResources" })
    check(reused ~= nil and reused.StandAnimationRUID == catalog:GetProfile("monster_tank").StandAnimationRUID,
        "a different identity accepts the same actual resource RUIDs")
    reset()
    for _, expected in ipairs({
        { "monster_tank", 500, 1.1, 40, 2, 0.65 },
        { "monster_warrior", 220, 2, 35, 0.7, 0.6 },
        { "monster_shooter", 120, 0.8, 30, 2, 4 },
    }) do
        local profile = catalog:GetProfile(expected[1])
        check(profile.MaxHp == expected[2] and profile.MoveSpeed == expected[3] and profile.AttackDamage == expected[4]
            and profile.AttackIntervalSeconds == expected[5] and profile.AttackRange == expected[6],
            expected[1] .. " loads the current formal CSV's independent numeric values")
    end
end)
if not ok then check(false, "probe raised: " .. tostring(detail)) end
if failures == 0 then log("[VRF][CatalogValidation] PASS")
else log_error("[VRF][CatalogValidation] FAILURES=" .. tostring(failures)) end
