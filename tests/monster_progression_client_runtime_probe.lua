-- Maker client with the authored formation UI loaded; no scene or storage writes.
local cards = {}
local originalMax = _MonsterProgression.MaxLevel
local ok, detail = pcall(function()
    for _, path in ipairs({ "Editor/Catalog/Template", "Editor/Intel", "CardTooltip" }) do
        local template = _FormationLobby:Ui(path)
        assert(isvalid(template), "authored progress display required: " .. path)
        local card = template:Clone("ProgressionReviewCard")
        card:SetEnable(false)
        table.insert(cards, card)
    end
    local textChecks = 0
    local function check(card, level, experience, label, value, ratio)
        local option = { level = level, experience = experience }
        assert(_FormationCatalogCards:ProgressLabel(option) == label, "progress label " .. label)
        _FormationCatalogCards:RenderProgress(card, option)
        local bar = card:GetChildByName("ExperienceBar")
        local track = bar:GetChildByName("Track")
        local fill = track:GetChildByName("Fill")
        local text = bar:GetChildByName("Value")
        if isvalid(text) then
            assert(text.TextGUIRendererComponent.Text == value, "experience text " .. value)
            textChecks = textChecks + 1
        end
        assert(math.abs(fill.UITransformComponent.RectSize.x - track.UITransformComponent.RectSize.x * ratio) < 0.001,
            "experience bar ratio " .. tostring(ratio))
        assert(fill.Enable == (ratio > 0), "empty fill visibility")
        assert(card:GetChildByName("LevelBadge").SpriteGUIRendererComponent.ImageRUID.DataId
            == _FormationCatalogCards.LevelIcons[level], "level art")
    end
    for _, card in ipairs(cards) do
        check(card, 1, 0, "Lv.1 0/1", "0/1", 0)
        check(card, 5, 3, "Lv.5 3/5", "3/5", 0.6)
        check(card, 29, 28, "Lv.29 28/29", "28/29", 28/29)
        check(card, 30, 0, "Lv.30 MAX", "MAX", 1)
    end
    -- A different shared cap must reach both label and renderer without a second UI rule.
    _MonsterProgression.MaxLevel = 5
    for _, card in ipairs(cards) do check(card, 5, 0, "Lv.5 MAX", "MAX", 1) end
    assert(_MonsterProgression:ApplyExperience(4, 3, 1).level == 5, "shared cap calculation")
    assert(textChecks == 10, "both authored numeric displays checked in every case")
end)
_MonsterProgression.MaxLevel = originalMax
for _, card in ipairs(cards) do if isvalid(card) then card:Destroy() end end
if ok then log("[VRF][MonsterProgressionClient] PASS catalog/intel/tooltip; labels; bars; MAX; shared cap; CLEANUP_PASS")
else log_error("[VRF][MonsterProgressionClient] FAIL " .. tostring(detail)) end
