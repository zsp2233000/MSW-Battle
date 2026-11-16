-- Fresh formal Play, context=server_main. Effect offsets (EffectOffsetData): the shipped table resolves onto profiles and dex rows,
-- an unregistered effect reads zero, and bad table data is rejected (fake dataset adapters feed the production parser).
-- Require the final [VRF][EffectOffsetProbe] PASS line.
local failures = 0
local function check(condition, message)
    if condition then log("[VRF][EffectOffsetProbe][PASS] " .. message)
    else failures = failures + 1; log_error("[VRF][EffectOffsetProbe][FAIL] " .. message) end
end
local SUN_HIT = "3298e817110d49bb9306e7c0daf84645"
local UNREGISTERED = "00000000000000000000000000000000"
local function fake(rows, withColumns)
    return {
        GetRowCount = function() return #rows end,
        GetColumn = function(_, name) if withColumns == false then return nil end return name end,
        GetRow = function(_, index)
            local row = rows[index]
            return { GetItem = function(_, field) return row[field] end }
        end,
    }
end
local ok, detail = pcall(function()
    local map = _EntityService:GetEntityByPath("/maps/template")
    local catalog = isvalid(map) and map:GetComponent("script.MonsterCatalog") or nil
    check(isvalid(catalog), "formal catalog is available")
    if not isvalid(catalog) then return end
    check(catalog:Load("MonsterData", {}, { battleunit = true }), "formal tables load together")
    local sun = catalog:GetEffectOffset(SUN_HIT)
    check(sun.x == 0 and sun.y > 0, "a registered RUID yields a nonzero offset y=" .. tostring(sun.y))
    local none = catalog:GetEffectOffset(UNREGISTERED)
    check(none.x == 0 and none.y == 0, "an unregistered RUID yields zero")
    check(catalog:GetEffectOffset("").y == 0, "a blank RUID yields zero")
    for _, id in ipairs({ "monster_moon_pixie", "monster_sun_pixie", "monster_star_pixie" }) do
        local profile = catalog:GetProfile(id)
        check(profile.HitEffectOffsetY > 0 and profile.HitEffectOffsetX == 0, id .. " profile carries its hit effect offset y=" .. tostring(profile.HitEffectOffsetY))
        check(profile.AttackEffectOffsetY == 0 and profile.ProjectileOffsetY == 0, id .. " attack effect and ball stay unshifted")
    end
    check(catalog:GetProfile("monster_tank").HitEffectOffsetY == 0, "a monster without a registered effect stays at zero")
    local dexRow = nil
    for _, row in ipairs(catalog:GetDexRows()) do if row.monsterId == "monster_sun_pixie" then dexRow = row end end
    check(dexRow ~= nil and dexRow.hitEffectOffsetY == catalog:GetProfile("monster_sun_pixie").HitEffectOffsetY, "the dex row publishes the resolved hit offset")
    check(dexRow ~= nil and dexRow.attackEffectOffsetX == 0 and dexRow.projectileOffsetY == 0, "the dex row publishes the other offsets")

    -- Table shape: missing or empty is fine, unused RUIDs are ignored.
    check(catalog:LoadEffectOffsetsFrom(nil) == true and catalog:GetEffectOffset(SUN_HIT).y == 0, "a missing table is not an error and clears every offset")
    check(catalog:LoadEffectOffsetsFrom(fake({})) == true, "an empty table is not an error")
    check(catalog:LoadEffectOffsetsFrom(fake({ { EffectRUID = UNREGISTERED, OffsetX = "1", OffsetY = "-2" } })) == true
        and catalog:GetEffectOffset(UNREGISTERED).x == 1 and catalog:GetEffectOffset(UNREGISTERED).y == -2, "an unused RUID is accepted and negative offsets are kept")
    -- A ball and an attack effect resolve through the same table.
    local probe = { AttackEffectRUID = UNREGISTERED, HitEffectRUID = "", ProjectileRUID = UNREGISTERED }
    catalog:ResolveProfileOffsets(probe)
    check(probe.AttackEffectOffsetX == 1 and probe.ProjectileOffsetY == -2 and probe.HitEffectOffsetX == 0, "attack effect and ball resolve by their own RUID")

    -- Bad data fails the whole table.
    local cases = {
        { "duplicate RUID", { { EffectRUID = SUN_HIT, OffsetX = "0", OffsetY = "1" }, { EffectRUID = SUN_HIT, OffsetX = "0", OffsetY = "2" } }, "duplicate EffectRUID" },
        { "blank RUID", { { EffectRUID = "", OffsetX = "0", OffsetY = "1" } }, "invalid EffectRUID" },
        { "short RUID", { { EffectRUID = "abc", OffsetX = "0", OffsetY = "1" } }, "invalid EffectRUID" },
        { "non-hex RUID", { { EffectRUID = "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz", OffsetX = "0", OffsetY = "1" } }, "invalid EffectRUID" },
        { "non-numeric X", { { EffectRUID = SUN_HIT, OffsetX = "left", OffsetY = "1" } }, "invalid numeric value" },
        { "blank Y", { { EffectRUID = SUN_HIT, OffsetX = "0", OffsetY = "" } }, "invalid numeric value" },
        { "infinite Y", { { EffectRUID = SUN_HIT, OffsetX = "0", OffsetY = "1e999" } }, "invalid numeric value" },
    }
    for _, case in ipairs(cases) do
        catalog.ErrorMessage = ""
        check(catalog:LoadEffectOffsetsFrom(fake(case[2])) == false and string.find(catalog.ErrorMessage, case[3], 1, true) ~= nil, case[1] .. " is rejected: " .. catalog.ErrorMessage)
    end
    catalog.ErrorMessage = ""
    check(catalog:LoadEffectOffsetsFrom(fake({ { EffectRUID = SUN_HIT } }, false)) == false, "a table missing its columns is rejected")

    -- Restore the formal state and make sure a corrupt table also fails a full Load.
    catalog.ErrorMessage = ""
    check(catalog:Load("MonsterData", {}, { battleunit = true }), "formal tables reload cleanly")
    check(catalog:GetEffectOffset(SUN_HIT).y > 0, "formal offsets are back after the reload")
    check(catalog:LoadEffectOffsetsFrom(fake({ { EffectRUID = "bad", OffsetX = "0", OffsetY = "0" } })) == false, "a bad table returns false (Load propagates this result)")
    -- A really absent table is not an error either.
    check(_DataService:GetTable("NoSuchEffectTable") == nil, "an absent table reads nil")
    catalog.EffectOffsetDataSetName = "NoSuchEffectTable"
    check(catalog:Load("MonsterData", {}, { battleunit = true }) and catalog:GetEffectOffset(SUN_HIT).y == 0, "a load without the offset table succeeds with zero offsets")
    catalog.EffectOffsetDataSetName = "EffectOffsetData"
    catalog.ErrorMessage = ""
    check(catalog:Load("MonsterData", {}, { battleunit = true }) and catalog.IsLoaded, "the formal load recovers")
end)
if not ok then failures = failures + 1; log_error("[VRF][EffectOffsetProbe][FAIL] " .. tostring(detail)) end
if failures == 0 then log("[VRF][EffectOffsetProbe] PASS") else log_error("[VRF][EffectOffsetProbe] FAIL failures=" .. tostring(failures)) end
