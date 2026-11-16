-- Run in a fresh Maker Play test with context=client, after the lobby is ready (formationlobby, idle, formation loaded).
-- Opens the monster dex through its lobby entry's connected ButtonClickEvent, selects each pixie through its list row and plays
-- the attack trial: the hit effect must land at the hit point lifted by the registered offset (0.4 world units = 0.4 * pixels per unit),
-- an unregistered monster's hit effect stays on the ground line, and the details list shows the 特效偏移 row.
-- Require the final [VRF][EffectOffsetDexProbe] PASS line. Nothing is queued, stored or edited.
local failures = 0
local function check(condition, message)
    if condition then log("[VRF][EffectOffsetDexProbe][PASS] " .. message)
    else failures = failures + 1; log_error("[VRF][EffectOffsetDexProbe][FAIL] " .. message) end
end
local function await(predicate, seconds)
    for _ = 1, math.floor((seconds or 10) / 0.05) do
        if predicate() then return true end
        wait(0.05)
    end
    return predicate()
end
local dex = _MonsterDex
local function click(entity) entity:SendEvent(ButtonClickEvent()) end
local function selectById(monsterId)
    for index, row in ipairs(dex._T.rows) do
        if row.monsterId == monsterId then
            for _, view in ipairs(dex._T.rowViews) do
                if view.monsterId == monsterId then click(view.entity); return row end
            end
        end
    end
    return nil
end
local function eventSeen(name)
    for _, event in ipairs(dex._T.events) do if event.name == name then return true end end
    return false
end
local ok, detail = pcall(function()
    click(dex.lobbyButton.Entity)
    check(await(function() return dex._T.loadState == "READY" and dex._T.battleZoom ~= nil end, 10), "the book opens with rows and the battle camera")
    for _, id in ipairs({ "monster_sun_pixie", "monster_moon_pixie", "monster_star_pixie", "monster_warrior" }) do
        local row = selectById(id)
        check(row ~= nil and dex._T.selectedId == id, id .. " is selected through its list row")
        if row ~= nil then
            local registered = id ~= "monster_warrior"
            local text = dex.detailLayout.Entity:GetChildByName("Detail_effectOffset", false):GetChildByName("Value", false).TextGUIRendererComponent.Text
            check(registered == (row.hitEffectOffsetY > 0), id .. " row publishes hit offset y=" .. tostring(row.hitEffectOffsetY))
            check(registered == (text ~= dex.UnsetText), id .. " 特效偏移 row reads: " .. text)
            local geometry = dex:StageGeometry(row)
            click(dex.attackButton.Entity)
            check(await(function() return eventSeen("HIT_EFFECT") end, 8), id .. " the hit effect plays")
            local box = dex.hitEffectSprite.Entity.UITransformComponent
            local lift = (box.anchoredPosition.y - geometry.footY) / geometry.pixelsPerUnit
            check(math.abs(lift - row.hitEffectOffsetY) < 0.01, id .. " hit effect lift " .. string.format("%.3f", lift) .. " world units equals its offset " .. tostring(row.hitEffectOffsetY))
            check(math.abs(box.anchoredPosition.x - geometry.hitX) < 1, id .. " hit effect keeps the hit point x (no sideways shift)")
            await(function() return dex._T.action == "IDLE" end, 5)
        end
    end
    click(dex.closeButton.Entity)
end)
if not ok then failures = failures + 1; log_error("[VRF][EffectOffsetDexProbe][FAIL] " .. tostring(detail)) end
if failures == 0 then log("[VRF][EffectOffsetDexProbe] PASS") else log_error("[VRF][EffectOffsetDexProbe] FAIL failures=" .. tostring(failures)) end
