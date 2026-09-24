-- Run in Maker Play with context=client_main after the monster cards appear.
local map = _EntityService:GetEntityByPath("/maps/map01")
local adapter = isvalid(map) and map:GetComponent("script.BattleDeploymentInput") or nil
if not isvalid(adapter) then
    log_error("[M1][DeploymentUIProbe][FAIL] input adapter unavailable")
    return
end

local failures = 0
local function check(condition, message)
    if condition then
        log("[M1][DeploymentUIProbe][PASS] " .. message)
    else
        failures = failures + 1
        log_error("[M1][DeploymentUIProbe][FAIL] " .. message)
    end
end

check(adapter.optionsReady and #adapter.optionCards == #adapter.optionData and #adapter.optionCards > 0,
    "each server catalog row creates one selectable card")
check(isvalid(adapter.optionTemplate) and adapter.optionTemplate.Enable == false,
    "template itself is not a selectable monster")

for index, option in ipairs(adapter.optionData) do
    local card = adapter.optionCards[index]
    if card == nil or not isvalid(card.entity) then
        check(false, "card " .. tostring(index) .. " exists")
        break
    end
    local nameEntity = card.entity:GetChildByName("MonsterName", true)
    local portraitEntity = card.entity:GetChildByName("Portrait", true)
    local label = isvalid(nameEntity) and nameEntity:GetComponent("TextGUIRendererComponent") or nil
    local portrait = isvalid(portraitEntity) and portraitEntity:GetComponent("SpriteGUIRendererComponent") or nil
    check(card.monsterId == option[1] and isvalid(label) and label.Text == option[2],
        "card " .. tostring(index) .. " keeps MonsterId and MonsterName from one row")
    check(isvalid(portrait) and portrait.ImageRUID ~= nil and portrait.ImageRUID.DataId == option[3],
        "card " .. tostring(index) .. " uses its row's StandAnimationRUID")
    adapter:SelectMonsterCard(option[1], card.glow)
    local enabledGlows = 0
    for _, candidate in ipairs(adapter.optionCards) do
        if isvalid(candidate.glow) and candidate.glow.Enable == true then enabledGlows = enabledGlows + 1 end
    end
    check(adapter.selectedMonsterId == option[1] and enabledGlows == 1 and isvalid(card.glow) and card.glow.Enable == true,
        "selecting card " .. tostring(index) .. " moves the persistent glow")
end

if failures == 0 then
    log("[M1][DeploymentUIProbe] PASS")
else
    log_error("[M1][DeploymentUIProbe] FAILURES=" .. tostring(failures))
end
