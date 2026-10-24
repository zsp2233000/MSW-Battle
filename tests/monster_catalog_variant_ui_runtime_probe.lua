-- Fresh Play with the guarded variantStats fixture, context=client.
local map = _EntityService:GetEntityByPath("/maps/template")
local ui = isvalid(map) and map:GetComponent("script.BattleDeploymentInput") or nil
local failures = 0
local function check(value, message)
    if value then log("[VRF][VariantUI][PASS] " .. message)
    else failures = failures + 1; log_error("[VRF][VariantUI][FAIL] " .. message) end
end
local function run(attempt)
    if isvalid(ui) and (not ui.optionsReady or ui.optionsBuilding) and attempt < 100 then
        _TimerService:SetTimerOnce(function() run(attempt + 1) end, 0.1)
        return
    end
    local ok, detail = pcall(function()
        check(isvalid(ui) and ui.optionsReady, "temporary catalog produces client cards")
        if not isvalid(ui) or not ui.optionsReady then return end
        ui:SetPreviewCardCount(0)
        local names = {}
        for _, card in ipairs(ui.optionCards) do
            names[card.monsterId] = card.entity:GetChildByName("MonsterName", true).TextGUIRendererComponent.Text
            card.entity:SendEvent(ButtonClickEvent(card.entity))
            check(ui.selectedMonsterId == card.monsterId, "connected card event selects " .. card.monsterId)
        end
        check(#ui.optionCards == 4 and names.monster_tank == "RenamedTank" and names.probe_tank_variant == "VariantTank",
            "same-type cards show independent names and retain stable IDs after rename")
    end)
    if not ok then check(false, "probe raised: " .. tostring(detail)) end
    if failures == 0 then log("[VRF][VariantUI] PASS")
    else log_error("[VRF][VariantUI] FAILURES=" .. tostring(failures)) end
end
run(0)
