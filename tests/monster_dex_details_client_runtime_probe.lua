-- Run in a fresh Maker Play test with context=client, after the lobby is ready (formationlobby, idle, formation loaded).
-- Opens the monster dex through its lobby entry's connected ButtonClickEvent, then selects every data-table monster through
-- its list row's connected ButtonClickEvent and compares every resource-detail row (label, value text, colour) with the
-- row the server published. Expected texts are spelled out here independently of MonsterDex's own formatting.
-- Nothing is queued, stored or edited; the book is closed again at the end.
local failures = 0
local function check(condition, message)
    if condition then log("[VRF][MonsterDexDetailsProbe][PASS] " .. message)
    else failures = failures + 1; log_error("[VRF][MonsterDexDetailsProbe][FAIL] " .. message) end
end

local function await(predicate, seconds)
    for _ = 1, math.floor((seconds or 10) / 0.1) do
        if predicate() then return true end
        wait(0.1)
    end
    return predicate()
end

local UNSET = "未設定"
local GROUPS = {
    { group = "idle", header = "待機", rows = { { "stand", "待機動畫" } } },
    { group = "move", header = "移動", rows = { { "move", "移動動畫" } } },
    { group = "attack", header = "攻擊", rows = { { "attackAnimation", "攻擊動畫" }, { "attackEffect", "出手特效" }, { "hitEffect", "命中特效" },
        { "projectile", "投射物" }, { "attackSound", "出手音效" }, { "attackEffectFrame", "出手特效影格" }, { "hitFrame", "命中影格" },
        { "attackDuration", "攻擊動畫長度" }, { "projectileSpeed", "投射物速度" } } },
    { group = "hurt", header = "受傷", rows = { { "hurtAnimation", "受傷動畫" }, { "hurtSound", "受傷音效" } } },
    { group = "die", header = "死亡", rows = { { "dieAnimation", "死亡動畫" }, { "dieSound", "死亡音效" } } },
}
local RUID_FIELDS = {
    stand = "standRuid", move = "moveRuid", attackAnimation = "attackRuid", attackEffect = "attackEffectRuid", hitEffect = "hitEffectRuid",
    projectile = "projectileRuid", attackSound = "attackSoundRuid", hurtAnimation = "hurtRuid", hurtSound = "hurtSoundRuid",
    dieAnimation = "dieRuid", dieSound = "dieSoundRuid",
}
local EXPECTED_CHILDREN = 20

-- What a row must read for one published dex row: the text and whether it is a real value (not the unset text).
local function expectedValue(key, row)
    local field = RUID_FIELDS[key]
    if field ~= nil then
        local ruid = row[field] or ""
        if ruid == "" then return UNSET, false end
        return ruid, true
    end
    if key == "attackEffectFrame" then
        if (row.attackEffectRuid or "") == "" then return UNSET, false end
        return "第 " .. string.format("%d", row.attackEffectFrame) .. " 格 (" .. string.format("%.2f", row.attackEffectDelay) .. " 秒)", true
    elseif key == "hitFrame" then
        return "第 " .. string.format("%d", row.attackDamageFrame) .. " 格 (" .. string.format("%.2f", row.impactDelay) .. " 秒)", true
    elseif key == "attackDuration" then
        return string.format("%.2f", row.attackDuration) .. " 秒", true
    elseif key == "projectileSpeed" then
        if (row.projectileRuid or "") == "" then return UNSET, false end
        return string.format("%.2f", row.projectileSpeed) .. " 世界單位/秒", true
    end
    return nil, false
end

local dex = _MonsterDex
local function click(entity) entity:SendEvent(ButtonClickEvent()) end
local function sameColor(a, b) return math.abs(a.r - b.r) < 0.01 and math.abs(a.g - b.g) < 0.01 and math.abs(a.b - b.b) < 0.01 and math.abs(a.a - b.a) < 0.01 end
local function uiRows()
    local rows = {}
    for _, child in ipairs(dex.listLayout.Entity.Children:ToTable()) do
        if string.sub(child.Name, 1, 4) == "Row_" and child.Enable then table.insert(rows, child) end
    end
    return rows
end
local function detailEntity(name) return dex.detailLayout.Entity:GetChildByName(name, false) end
local function valueOf(key)
    local row = detailEntity("Detail_" .. key)
    return row:GetChildByName("Value", false).TextGUIRendererComponent
end

-- Compare every detail row on screen with the published row; returns the number of mismatches and how many rows read unset.
local function compareAll(row, label)
    local mismatches, unset = 0, 0
    -- The two hidden templates stay in the list next to the cloned rows.
    local children = dex.detailLayout.Entity.Children:ToTable()
    local shown, hidden = 0, 0
    for _, child in ipairs(children) do
        if child.Enable then shown = shown + 1 else hidden = hidden + 1 end
    end
    check(shown == EXPECTED_CHILDREN and hidden == 2 and #children == EXPECTED_CHILDREN + 2,
        label .. ": the list keeps " .. tostring(EXPECTED_CHILDREN) .. " shown rows plus its 2 hidden templates (" .. tostring(shown) .. "/" .. tostring(hidden) .. ")")
    local touchRows = 0
    for _, child in ipairs(children) do
        if child.Enable and child.UITouchReceiveComponent ~= nil then touchRows = touchRows + 1 end
    end
    check(touchRows == EXPECTED_CHILDREN, label .. ": every shown detail row swallows the touch so the list cannot be drag-scrolled (" .. tostring(touchRows) .. ")")
    local snapshotDetails = dex:GetSnapshot().details
    local at = 0
    for _, group in ipairs(GROUPS) do
        local header = detailEntity("Header_" .. group.group)
        if not (isvalid(header) and header.TextGUIRendererComponent.Text == group.header) then mismatches = mismatches + 1 end
        for _, spec in ipairs(group.rows) do
            at = at + 1
            local key, labelText = spec[1], spec[2]
            local expected, isSet = expectedValue(key, row)
            local entity = detailEntity("Detail_" .. key)
            local value = isvalid(entity) and valueOf(key) or nil
            local shownLabel = isvalid(entity) and entity:GetChildByName("Label", false).TextGUIRendererComponent.Text or nil
            local ok = value ~= nil and shownLabel == labelText and value.Text == expected
                and sameColor(value.FontColor, isSet and dex.DetailValueColor or dex.DetailUnsetColor)
                and snapshotDetails[at] ~= nil and snapshotDetails[at].key == key and snapshotDetails[at].value == expected
            if not ok then
                mismatches = mismatches + 1
                log_error("[VRF][MonsterDexDetailsProbe] " .. label .. " row " .. key .. " shows '" .. tostring(value ~= nil and value.Text or nil)
                    .. "' label '" .. tostring(shownLabel) .. "' expected '" .. tostring(expected) .. "'")
            end
            if not isSet then unset = unset + 1 end
        end
    end
    check(mismatches == 0, label .. ": every header, label, value and colour matches the dex row")
    check(#snapshotDetails == EXPECTED_CHILDREN - #GROUPS, label .. ": the snapshot lists every resource row (" .. tostring(#snapshotDetails) .. ")")
    return unset
end

-- Scrolls the detail list to its end and back. The request is repeated for a few seconds so a slow first layout cannot fail
-- the check spuriously, like a user dragging or using the wheel; a list that never scrolls still fails.
local function scrollToEnd()
    return await(function()
        dex.detailLayout:SetScrollNormalizedPosition(UITransformAxis.Vertical, 1)
        wait(0.1)
        return dex.detailLayout:GetScrollNormalizedPosition().y > 0.9
    end, 8)
end
local function checkScrolls(label)
    check(scrollToEnd(), label)
    dex.detailLayout:SetScrollNormalizedPosition(UITransformAxis.Vertical, 0)
    wait(0.3)
end

local ok, detail = pcall(function()
    check(await(function()
        return isvalid(_UserService.LocalPlayer) and _UserService.LocalPlayer.CurrentMapName == "formationlobby"
            and _MatchFlowInput:AllowsFormationActions() and isvalid(dex.lobbyButton) and dex.lobbyButton.Enable
    end, 40), "the lobby is ready and the dex entry is usable")

    -- Before the first open the rows exist but carry no monster text.
    check(#dex.detailLayout.Entity.Children:ToTable() == 2 and not dex.headerTemplate.Enable and not dex.detailTemplate.Enable,
        "before the first reply the list holds only its two hidden templates")

    click(dex.lobbyButton.Entity)
    check(await(function() return dex:GetSnapshot().open and dex:GetSnapshot().loadState == "READY" end), "the entry opens the book and the rows arrive")
    local latest = _MonsterDexService:GetLatest()
    local rows = uiRows()
    check(latest ~= nil and #latest > 0 and #rows == #latest, "one list row per published monster (" .. tostring(#rows) .. ")")

    -- Placement: the details occupy the lower part of the right page, below the stage area.
    wait(0.5)
    checkScrolls("the detail list scrolls on the very first opening")

    local right = dex.detailLayout.Entity.Parent
    local view = dex.detailLayout.Entity.UITransformComponent
    check(right.Name == "RightPage" and view.anchoredPosition.y < -right.UITransformComponent.RectSize.y * 0.45, "the detail list sits in the lower half of the right page")
    check(-view.anchoredPosition.y + view.RectSize.y <= right.UITransformComponent.RectSize.y and view.anchoredPosition.x + view.RectSize.x <= right.UITransformComponent.RectSize.x, "the detail list stays inside the right page")

    -- Coverage classes seen across the table.
    local withProjectile, withoutProjectile, withMissingOptional = 0, 0, 0
    local totalUnset = 0
    local previous = nil
    for index, row in ipairs(latest) do
        click(rows[index])
        local snapshot = dex:GetSnapshot()
        check(snapshot.selectedMonsterId == row.monsterId, "selected " .. row.monsterName)
        local unset = compareAll(row, row.monsterName)
        totalUnset = totalUnset + unset
        if (row.projectileRuid or "") ~= "" then withProjectile = withProjectile + 1 else withoutProjectile = withoutProjectile + 1 end
        local missing = false
        for _, field in pairs({ "attackEffectRuid", "hitEffectRuid", "projectileRuid", "attackSoundRuid", "hurtSoundRuid", "dieSoundRuid" }) do
            if (row[field] or "") == "" then missing = true end
        end
        if missing then withMissingOptional = withMissingOptional + 1 end
        if (row.projectileRuid or "") == "" then
            check(valueOf("projectile").Text == UNSET and valueOf("projectileSpeed").Text == UNSET, row.monsterName .. ": no projectile reads 未設定 for the ball and its speed")
        else
            check(valueOf("projectile").Text == row.projectileRuid and #valueOf("projectile").Text == 32 and valueOf("projectileSpeed").Text ~= UNSET,
                row.monsterName .. ": a projectile shows its full RUID and speed")
        end
        -- The attack timing rows always come from the published delays.
        check(valueOf("attackDuration").Text ~= UNSET and valueOf("hitFrame").Text ~= UNSET, row.monsterName .. ": hit frame and attack length are always shown")
        previous = row
    end
    check(withProjectile >= 1, "the table covers monsters with a projectile (" .. tostring(withProjectile) .. ")")
    check(withoutProjectile >= 1, "the table covers monsters without a projectile (" .. tostring(withoutProjectile) .. ")")
    check(withMissingOptional >= 1 and totalUnset >= 1, "the table covers monsters missing optional resources (" .. tostring(withMissingOptional) .. ", unset rows " .. tostring(totalUnset) .. ")")

    -- Switching back and forth updates every text, never leaving the previous monster's values behind.
    local first, last = latest[1], latest[#latest]
    click(rows[#latest]); compareAll(last, "switch to last")
    click(rows[1]); compareAll(first, "switch back to first")
    click(rows[1]); compareAll(first, "re-selecting keeps the same details")

    -- Overflow: more content than the view, so it scrolls; switching monsters returns to the top.
    local content = 0
    for _, child in ipairs(dex.detailLayout.Entity.Children:ToTable()) do
        if child.Enable then content = content + child.UITransformComponent.RectSize.y end
    end
    local viewHeight = dex.detailLayout.Entity.UITransformComponent.RectSize.y
    check(content > viewHeight, "the rows overflow the detail view (" .. tostring(content) .. " > " .. tostring(viewHeight) .. ") so it scrolls")
    check(scrollToEnd(), "the detail list scrolls to its end after switching monsters")
    click(rows[2])
    check(await(function() return dex.detailLayout:GetScrollNormalizedPosition().y < 0.1 end, 3), "choosing another monster scrolls the details back to the top")
    compareAll(latest[2], "after scrolling and switching")

    -- Close and reopen: the selection and its details are still shown.
    click(dex.closeButton.Entity)
    check(not dex:GetSnapshot().open, "the close button hides the book")
    click(dex.lobbyButton.Entity)
    check(await(function() return dex:GetSnapshot().open and dex:GetSnapshot().loadState == "READY" end), "the book reopens")
    wait(0.5)
    checkScrolls("the detail list scrolls again after reopening")
    local selected = dex:GetSelectedRow()
    check(selected ~= nil and selected.monsterId == latest[2].monsterId, "the previous selection is kept")
    compareAll(latest[2], "after reopening")
end)
if not ok then check(false, "probe raised: " .. tostring(detail)) end
if isvalid(dex) and dex:GetSnapshot().open then dex:Close() end
if failures == 0 then log("[VRF][MonsterDexDetailsProbe] PASS")
else log_error("[VRF][MonsterDexDetailsProbe] FAILURES=" .. tostring(failures)) end
