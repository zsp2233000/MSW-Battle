-- Client after the leveled scene, or in a real matched room. Observe production actors only.
local ok, detail = pcall(function()
    local player = _UserService.LocalPlayer
    local map = player.CurrentMap
    local units = map:GetChildComponentsByTypeName("script.BattleUnit", false)
    local view = map:GetComponent("script.BattleView")
    assert(#units > 0, "battle units required")
    local factions = {}
    for _, unit in ipairs(units) do
        local display = unit.Entity
        if isvalid(view) and view:HasParticipants() then
            display = view:GetVisual(unit.Entity)
            assert(isvalid(display), "matched visual exists")
            local sourceLabel = unit.Entity:GetChildByName("NameTag")
            local sourceTag = isvalid(sourceLabel) and sourceLabel.NameTagComponent or nil
            assert(not isvalid(sourceTag) or not sourceTag.Enable, "authoritative name tag is hidden")
        end
        local label = display:GetChildByName("NameTag")
        assert(isvalid(label) and label.Parent == display, "shared authored name tag child " .. display.Name)
        local tag = label.NameTagComponent
        assert(isvalid(tag) and tag.Enable == (not unit.IsDead), "name tag visibility " .. display.Name)
        assert(tag.Name == "Lv." .. tostring(unit.Level) .. " " .. unit.MonsterName, "exact name tag " .. display.Name)
        assert(tag.FontSize > 0 and tag.OffsetY < 0, "authored size and below-foot position")
        local fontSize, offsetY = tag.FontSize, tag.OffsetY
        local ruid, color, bold, fontOffset = tag.NameTagRUID.DataId, tag.FontColor, tag.Bold, tag.FontOffset
        tag.FontSize = fontSize + 0.125
        tag.OffsetY = offsetY - 0.125
        tag.Name = "probe refresh"
        unit:UpdateNameTag(display)
        local preserved = math.abs(tag.FontSize - fontSize - 0.125) < 0.00001
            and math.abs(tag.OffsetY - offsetY + 0.125) < 0.00001
            and tag.NameTagRUID.DataId == ruid and tag.FontColor == color and tag.Bold == bold and tag.FontOffset == fontOffset
        tag.FontSize = fontSize; tag.OffsetY = offsetY
        assert(preserved and tag.Name == "Lv." .. tostring(unit.Level) .. " " .. unit.MonsterName,
            "name refresh preserves authored and inspector-tuned appearance " .. display.Name)
        factions[unit.Faction] = true
    end
    assert(factions.PLAYER and factions.ENEMY, "both factions have name tags")
    log("[VRF][MonsterLevelClient] PASS count=" .. tostring(#units))
end)
if not ok then log_error("[VRF][MonsterLevelClient] FAIL " .. tostring(detail)) end
