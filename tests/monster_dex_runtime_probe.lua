-- Run in a fresh Maker Play test with context=server_main, after `template` reaches DEPLOYMENT.
-- Part A: MonsterCatalog:GetDexRows equals the MonsterData table (order, fields, blanks) and the validated profile.
-- Part B (ADR 0008 drift guard): for every catalog monster, one real attack on a manual clock produces
-- attack start / attack effect request / hit timings that match the dex row's three delays (within one step);
-- a projectile arrives after distance / speed. Require the final [VRF][MonsterDexProbe] PASS line.
local map = nil
local session = nil
local failures = 0
local manualClockOwned = false
local STEP = 0.05
local TOLERANCE = STEP + 0.000001
local HORIZON = 8

local function check(condition, message)
    if condition then log("[VRF][MonsterDexProbe][PASS] " .. message)
    else failures = failures + 1; log_error("[VRF][MonsterDexProbe][FAIL] " .. message) end
end

local function blankToEmpty(value)
    if value == nil then return "" end
    return value
end

local function partA(catalog, rows)
    local dataset = _DataService:GetTable(session.MonsterDataSetName)
    check(dataset ~= nil, "MonsterData table is readable")
    local count = dataset:GetRowCount()
    check(#rows == count, "one dex row per data row (rows=" .. tostring(#rows) .. ", data=" .. tostring(count) .. ")")
    local textColumns = {
        monsterName = "MonsterName", standRuid = "StandAnimationRUID", moveRuid = "MoveAnimationRUID",
        attackRuid = "AttackAnimationRUID", hurtRuid = "HurtAnimationRUID", dieRuid = "DieAnimationRUID",
        attackEffectRuid = "AttackEffectRUID", hitEffectRuid = "HitEffectRUID", attackSoundRuid = "AttackSoundRUID",
        hurtSoundRuid = "HurtSoundRUID", dieSoundRuid = "DieSoundRUID", projectileRuid = "ProjectileRUID",
    }
    local numberColumns = {
        attackEffectFrame = "AttackEffectFrame", attackDamageFrame = "AttackDamageFrame", attackRange = "AttackRange",
    }
    for index = 1, count do
        local source = dataset:GetRow(index)
        local row = rows[index]
        local id = source:GetItem("MonsterId")
        check(row ~= nil and row.monsterId == id and row.order == index, "row " .. index .. " keeps table order (" .. tostring(id) .. ")")
        if row ~= nil then
            for key, column in pairs(textColumns) do
                check(row[key] == blankToEmpty(source:GetItem(column)), id .. " " .. key .. " equals column " .. column)
            end
            for key, column in pairs(numberColumns) do
                check(row[key] == tonumber(source:GetItem(column)), id .. " " .. key .. " equals column " .. column)
            end
            local speed = source:GetItem("ProjectileSpeed")
            local expectedSpeed = (speed == nil or speed == "") and 0 or tonumber(speed)
            check(row.projectileSpeed == expectedSpeed, id .. " projectileSpeed equals its column or 0")
            local profile = session:GetMonsterProfile(id)
            check(profile ~= nil and row.attackEffectDelay == profile.AttackEffectDelaySeconds
                and row.impactDelay == profile.ImpactDelaySeconds and row.attackDuration == profile.AttackAnimationDurationSeconds,
                id .. " delays are the profile's precomputed values")
            check(type(row.scaleX) == "number" and row.scaleX > 0 and type(row.scaleY) == "number" and row.scaleY ~= 0
                and type(row.bodyOffsetX) == "number" and type(row.bodyOffsetY) == "number", id .. " has model scale and body centre")
            check(row.maxHp == nil and row.attackDamageMin == nil and row.attackDamageMax == nil and row.level == nil,
                id .. " carries no level-dependent combat numbers")
        end
    end
    -- Deployment options are unchanged: still ordered by MonsterId, not by table order.
    local options = catalog:GetDeploymentOptions()
    check(#options == count, "deployment options list every monster")
    for index = 2, #options do
        check(options[index - 1].monsterId < options[index].monsterId, "deployment option " .. index .. " stays sorted by MonsterId")
    end
    -- Rows are fresh copies: mutating one reply must not change the next.
    local again = catalog:GetDexRows()
    again[1].monsterName = "mutated"
    check(catalog:GetDexRows()[1].monsterName == rows[1].monsterName, "dex rows are rebuilt on every request")
end

local function row(monsterId, name, x, overrides)
    return { monsterId = monsterId, name = name, position = Vector3(x, 0, 0), overrides = overrides }
end

local function measure(dexRow, monsterType)
    local distance = monsterType == "SHOOTER" and 2.5 or 0.5
    local prepared = session:PrepareBattleForTest(
        { row(dexRow.monsterId, "Dex_Attacker", -distance / 2, {
            MoveSpeed = 0, AttackDamageMin = 1, AttackDamageMax = 1, AttackIntervalSeconds = 100, RetargetIntervalSeconds = 0.05,
        }) },
        { row("monster_warrior", "Dex_Target", distance / 2, {
            MaxHp = 100000, MoveSpeed = 0, AttackDamageMin = 0, AttackDamageMax = 0, RetargetIntervalSeconds = 0, AttackIntervalSeconds = 100,
        }) }
    )
    if not prepared or not session:TryStartBattle() then return nil end
    local attacker = _EntityService:GetEntityByPath("/maps/template/Dex_Attacker")
    local target = _EntityService:GetEntityByPath("/maps/template/Dex_Target")
    if not isvalid(attacker) or not isvalid(target) then return nil end
    local unit = attacker:GetComponent("script.BattleUnit")
    local attack = attacker:GetComponent("script.BattleAttackComposition")
    local defender = target:GetComponent("script.BattleUnit")
    local hasBall = dexRow.projectileRuid ~= ""
    local at = { duration = unit.AttackAnimationDuration }
    local elapsed = 0
    while elapsed < HORIZON do
        session:AdvanceForTest(STEP)
        elapsed = elapsed + STEP
        if at.start == nil and unit.AttackSerial >= 1 then at.start = elapsed end
        if at.effect == nil and attack:GetAttackEffectRequestCount() >= 1 then at.effect = elapsed end
        if hasBall then
            if at.launch == nil and attack:GetProjectileCount() > 0 then
                at.launch = elapsed
                local from = attack:GetBodyCenter(attacker)
                local to = attack:GetBodyCenter(target)
                at.distance = math.sqrt((to.x - from.x) ^ 2 + (to.y - from.y) ^ 2)
            end
            if at.launch ~= nil and at.arrive == nil and attack:GetProjectileCount() == 0 and defender.DamageTakenSerial >= 1 then at.arrive = elapsed end
        elseif at.hit == nil and defender.DamageTakenSerial >= 1 then
            at.hit = elapsed
        end
        if at.start ~= nil and at.poiseEnd == nil and not unit.AttackPoiseActive then at.poiseEnd = elapsed end
        local resolved = hasBall and at.arrive ~= nil or (not hasBall and at.hit ~= nil)
        if resolved and at.poiseEnd ~= nil then break end
    end
    at.effectRequests = attack:GetAttackEffectRequestCount()
    return at
end

local function partB(rows)
    for _, dexRow in ipairs(rows) do
        local profile = session:GetMonsterProfile(dexRow.monsterId)
        local at = measure(dexRow, profile.MonsterType)
        check(at ~= nil and at.start ~= nil, dexRow.monsterId .. " started one real attack")
        if at ~= nil and at.start ~= nil then
            if dexRow.attackEffectRuid == "" then
                check(at.effectRequests == 0, dexRow.monsterId .. " has no attack effect and requests none")
            else
                check(at.effect ~= nil and math.abs((at.effect - at.start) - dexRow.attackEffectDelay) <= TOLERANCE,
                    dexRow.monsterId .. " attack effect requested after " .. tostring(dexRow.attackEffectDelay)
                    .. " (observed " .. tostring(at.effect and at.effect - at.start) .. ")")
            end
            check(at.poiseEnd ~= nil and math.abs((at.poiseEnd - at.start) - dexRow.attackDuration) <= TOLERANCE
                and math.abs(at.duration - dexRow.attackDuration) <= 0.000001,
                dexRow.monsterId .. " attack animation lasts " .. tostring(dexRow.attackDuration)
                .. " (observed " .. tostring(at.poiseEnd and at.poiseEnd - at.start) .. ")")
            if dexRow.projectileRuid == "" then
                check(at.hit ~= nil and math.abs((at.hit - at.start) - dexRow.impactDelay) <= TOLERANCE,
                    dexRow.monsterId .. " hits after " .. tostring(dexRow.impactDelay)
                    .. " (observed " .. tostring(at.hit and at.hit - at.start) .. ")")
            else
                check(at.launch ~= nil and math.abs((at.launch - at.start) - dexRow.impactDelay) <= TOLERANCE,
                    dexRow.monsterId .. " launches after " .. tostring(dexRow.impactDelay)
                    .. " (observed " .. tostring(at.launch and at.launch - at.start) .. ")")
                local expected = at.distance and at.distance / dexRow.projectileSpeed
                check(at.arrive ~= nil and expected ~= nil and math.abs((at.arrive - at.launch) - expected) <= TOLERANCE,
                    dexRow.monsterId .. " arrives after distance / speed = " .. tostring(expected)
                    .. " (observed " .. tostring(at.arrive and at.launch and at.arrive - at.launch) .. ")")
            end
        end
    end
end

local runOk, runDetail = pcall(function()
    map = _EntityService:GetEntityByPath("/maps/template")
    session = isvalid(map) and map:GetComponent("script.BattleSession") or nil
    local catalog = isvalid(map) and map:GetComponent("script.MonsterCatalog") or nil
    if not isvalid(session) or not isvalid(catalog) or catalog.IsLoaded ~= true then
        check(false, "template session and a loaded catalog are available")
        return
    end
    local rows = catalog:GetDexRows()
    partA(catalog, rows)
    manualClockOwned = session:BeginManualSimulation()
    check(manualClockOwned, "probe acquires the manual clock")
    if not manualClockOwned then return end
    partB(rows)
end)

if manualClockOwned and session ~= nil then
    local cleanupOk, cleanupDetail = pcall(function() session:EndManualSimulation() end)
    manualClockOwned = false
    if not cleanupOk then check(false, "cleanup releases the manual clock: " .. tostring(cleanupDetail)) end
end
if not runOk then check(false, "probe raised: " .. tostring(runDetail)) end
if failures == 0 then log("[VRF][MonsterDexProbe] PASS")
else log_error("[VRF][MonsterDexProbe] FAILURES=" .. tostring(failures)) end
