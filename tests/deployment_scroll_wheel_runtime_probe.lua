-- Maker Play, context=client, formal catalog and 18 cards; reference resolution 1920x1080.
-- After dispatch, use maker_mouse_input: move once to (600,150), then 13 scroll
-- events with delta=-0.2 and a 250ms wait after each. Do not move between events.
-- Override expectedEvents to 38 to replay the longer original reproduction.
-- For upward input, set startAtBottom=true and send delta=+0.2 instead.
-- The native wheel advances 30 UI pixels per delta unit in this Maker version.
local expectedEvents = 13
local startAtBottom = false
local map = _EntityService:GetEntityByPath("/maps/template")
local ui = isvalid(map) and map:GetComponent("script.BattleDeploymentInput") or nil
if not isvalid(ui) or not ui.optionsReady or ui.optionsBuilding or #ui.optionCards ~= 18
    or ui.session.Phase ~= "DEPLOYMENT" then
    log_error("[VRF][DeploymentWheel] FAIL: expected 18 ready cards in deployment")
    return
end

local layout = ui.optionContainer.ScrollLayoutGroupComponent
local range = ui:GetMonsterOptionsScrollRange()
layout:ResetScrollPosition(UITransformAxis.Vertical)
if startAtBottom then
    layout:SetScrollNormalizedPosition(UITransformAxis.Vertical, 1)
end
local function positionFromTop()
    return layout:GetScrollNormalizedPosition().y
end

-- Reset readback settles on the next frame. Use the requested start, so a
-- preceding probe's scroll offset cannot contaminate this measurement.
local start = startAtBottom and 1 or 0
local received = 0
local totalDelta = 0
local finished = false
local eventCallback = nil
local timeoutId = nil

local function finish()
    if finished then return end
    finished = true
    _InputService:DisconnectEvent(MouseScrollEvent, eventCallback)
    if timeoutId ~= nil then _TimerService:ClearTimer(timeoutId) end
    local actualPixels = (positionFromTop() - start) * range
    local expectedPixels = totalDelta * 30
    if received == expectedEvents and math.abs(expectedPixels) > 0 and math.abs(actualPixels - expectedPixels) < 0.5 then
        log("[VRF][DeploymentWheel] PASS events=" .. tostring(received) .. " pixels=" .. tostring(actualPixels))
    else
        log_error("[VRF][DeploymentWheel] FAIL events=" .. tostring(received) .. " pixels=" .. tostring(actualPixels)
            .. " expected=" .. tostring(expectedPixels))
    end
end

eventCallback = _InputService:ConnectEvent(MouseScrollEvent, function(event)
    received = received + 1
    totalDelta = totalDelta - event.ScrollDelta
    if received == expectedEvents then _TimerService:SetTimerOnce(finish, 0.2) end
end)
timeoutId = _TimerService:SetTimerOnce(finish, 30)
log("[VRF][DeploymentWheel] READY events=" .. tostring(expectedEvents))
