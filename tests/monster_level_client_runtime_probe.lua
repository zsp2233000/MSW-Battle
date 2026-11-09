-- Client after the leveled scene, or in a real matched room. Observe production actors only.
local ok, detail = pcall(function()
    local player = _UserService.LocalPlayer
    local map = player.CurrentMap
    local units = map:GetChildComponentsByTypeName("script.BattleUnit", false)
    local view = map:GetComponent("script.BattleView")
    assert(#units > 0, "battle units required")
    local factions = {}
    local style = player.NameTagComponent
    for _, unit in ipairs(units) do
        local display = unit.Entity
        if isvalid(view) and view:HasParticipants() then
            display = view:GetVisual(unit.Entity)
            assert(isvalid(display), "matched visual exists")
            local sourceTag = unit.Entity.NameTagComponent
            assert(not isvalid(sourceTag) or not sourceTag.Enable, "authoritative name tag is hidden")
        end
        local tag = display.NameTagComponent
        assert(isvalid(tag) and tag.Enable == (not unit.IsDead), "name tag visibility " .. display.Name)
        assert(tag.Name == "Lv." .. tostring(unit.Level) .. " " .. unit.MonsterName, "exact name tag " .. display.Name)
        assert(math.abs(tag.OffsetY + 0.2) < 0.00001, "name tag below actor feet")
        assert(tag.NameTagRUID.DataId == style.NameTagRUID.DataId and tag.FontSize == style.FontSize
            and tag.FontColor == style.FontColor and tag.Bold == style.Bold and tag.FontOffset == style.FontOffset,
            "player name style " .. display.Name)
        factions[unit.Faction] = true
    end
    assert(factions.PLAYER and factions.ENEMY, "both factions have name tags")
    log("[VRF][MonsterLevelClient] PASS count=" .. tostring(#units))
end)
if not ok then log_error("[VRF][MonsterLevelClient] FAIL " .. tostring(detail)) end
