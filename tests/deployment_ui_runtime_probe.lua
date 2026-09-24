-- Run in Maker Play with context=client after the server catalog creates cards.
-- Drives the same callbacks connected to card, battlefield, and start-button input.
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

local function finish()
    if failures == 0 then
        log("[M1][DeploymentUIProbe] PASS")
    else
        log_error("[M1][DeploymentUIProbe] FAILURES=" .. tostring(failures))
    end
end

check(adapter.optionsReady and #adapter.optionCards == #adapter.optionData and #adapter.optionCards > 0,
    "each server catalog row creates one selectable card")
check(isvalid(adapter.optionTemplate) and adapter.optionTemplate.Enable == false,
    "template itself is not a selectable monster")
check(isvalid(adapter.optionContainer) and adapter.optionContainer.Enable == true and
    isvalid(adapter.startButton) and adapter.startButton.Enable == true,
    "deployment controls are enabled during deployment")

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
    check(type(card.clickAction) == "function", "card " .. tostring(index) .. " retains its connected click action")
    card.clickAction()
    local enabledGlows = 0
    for _, candidate in ipairs(adapter.optionCards) do
        if isvalid(candidate.glow) and candidate.glow.Enable == true then enabledGlows = enabledGlows + 1 end
    end
    check(adapter.selectedMonsterId == option[1] and enabledGlows == 1 and isvalid(card.glow) and card.glow.Enable == true,
        "click action selects card " .. tostring(index) .. " and moves the persistent glow")
end

local selectedCard = adapter.optionCards[1]
if selectedCard == nil or type(adapter.startButtonAction) ~= "function" then
    check(false, "deployment callbacks are available for an end-to-end flow")
    finish()
    return
end

selectedCard.clickAction()
adapter:HandleBattlefieldClick(Vector3(-4, 0, 0))
log("[M1][DeploymentUIProbe] deployment click action sent")

local function startSingleUnitBattle()
    check(adapter.session.Phase == "DEPLOYMENT" and adapter.session.PlayerAlive == 1,
        "client battlefield action deploys one selected unit")
    adapter:HandleBattlefieldClick(Vector3(-4, 0, 0))
    _TimerService:SetTimerOnce(function()
        check(adapter.session.PlayerAlive == 0, "battlefield action removes the deployed unit")
        adapter:HandleBattlefieldClick(Vector3(-4, 0, 0))
        _TimerService:SetTimerOnce(function()
            check(adapter.session.PlayerAlive == 1, "battlefield action redeploys one unit")
            adapter.startButtonAction()
            _TimerService:SetTimerOnce(function()
                check(adapter.session.Phase == "BATTLE" and adapter.session.InitialPlayerAlive == 1,
                    "start-button action starts a one-unit battle")
                check(adapter.optionContainer.Enable == false and adapter.startButton.Enable == false,
                    "deployment controls hide and disable after battle starts")

                local function observeResult(elapsed)
                    if adapter.session.Phase ~= "RESULT" and elapsed < 45 then
                        _TimerService:SetTimerOnce(function() observeResult(elapsed + 1) end, 1)
                        return
                    end
                    check(adapter.session.Phase == "RESULT", "natural one-unit battle reaches a result")
                    if adapter.session.Phase == "RESULT" then
                        local result = adapter.session.Result
                        local win = adapter.resultWin.Enable == true
                        local lose = adapter.resultLose.Enable == true
                        local draw = adapter.resultDraw.Enable == true
                        local visible = (win and 1 or 0) + (lose and 1 or 0) + (draw and 1 or 0)
                        local correct = (result == "WIN" and win) or (result == "LOSE" and lose) or (result == "DRAW" and draw)
                        check(visible == 1 and correct, "natural result enables exactly its matching result entity")
                    end
                    finish()
                end

                observeResult(0)
            end, 0.5)
        end, 0.5)
    end, 0.5)
end

_TimerService:SetTimerOnce(startSingleUnitBattle, 0.5)
