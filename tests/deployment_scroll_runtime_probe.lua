-- Fresh Maker Play, context=client, formal catalog, no deployed player units.
-- Drives connected UI events and native layout; does not simulate drag gestures.
local map = _EntityService:GetEntityByPath("/maps/template")
local ui = isvalid(map) and map:GetComponent("script.BattleDeploymentInput") or nil
local originalPreviewCount = nil
local finished = false
local oldCards = {}
local horizontalPosition = nil
local firstRowWorldY = nil

local function finish(ok, detail)
    if finished then return end
    finished = true
    if isvalid(ui) and originalPreviewCount ~= nil and not ui.optionsBuilding
        and ui.optionsReady and ui.PreviewCardCount ~= originalPreviewCount then
        ui:SetPreviewCardCount(originalPreviewCount)
    end
    if ok then log("[VRF][DeploymentScroll] PASS")
    else log_error("[VRF][DeploymentScroll] FAIL: " .. tostring(detail)) end
end

local function expect(value, message)
    if not value then error(message) end
    log("[VRF][DeploymentScroll][PASS] " .. message)
end

local function step(action)
    if finished then return end
    local ok, detail = pcall(action)
    if not ok then finish(false, detail) end
end

local function later(action)
    _TimerService:SetTimerOnce(function() step(action) end, 0.2)
end

local function waitForCards(count, action, attempt)
    attempt = attempt or 0
    step(function()
        expect(isvalid(ui), "deployment UI adapter exists")
        if ui.optionsReady and not ui.optionsBuilding and #ui.optionCards == count then
            later(action)
        elseif attempt < 150 then
            later(function() waitForCards(count, action, attempt + 1) end)
        else
            error("timed out waiting for " .. tostring(count) .. " cards")
        end
    end)
end

local function verifyDeployment()
    expect(ui.session.PlayerAlive == 0, "display toggles do not deploy units")
    expect(math.abs(ui.optionContainer.ScrollLayoutGroupComponent:GetScrollNormalizedPosition().y) < 0.001,
        "restoring 18 cards returns the vertical list to its first row")
    local card = ui.optionCards[18]
    card.entity:SendEvent(ButtonClickEvent(card.entity))
    ui:HandleBattlefieldClick(Vector3(-4, 0, 0))
    later(function()
        local entity = _EntityService:GetEntityByPath("/maps/template/M1_Player_1")
        local unit = isvalid(entity) and entity:GetComponent("script.BattleUnit") or nil
        expect(ui.session.PlayerAlive == 1 and isvalid(unit) and unit.MonsterId == card.monsterId,
            "last test card deploys its original server catalog MonsterId")
        ui:HandleBattlefieldRemovalClick(Vector3(-4, 0, 0))
        later(function()
            expect(ui.session.PlayerAlive == 0, "test deployment is removed through the connected removal action")
            expect(ui.session.Phase == "DEPLOYMENT", "probe leaves the battle in deployment")
            finish(true)
        end)
    end)
end

local function verifyOriginalCatalog()
    expect(#ui.catalogOptions == 3 and #ui.optionData == 3, "original catalog remains three entries")
    expect(ui.selectedMonsterId == "", "toggle clears selection")
    for _, entity in ipairs(oldCards) do expect(not isvalid(entity), "old test-card entity is destroyed") end
    for index, card in ipairs(ui.optionCards) do
        expect(card.entity:GetChildByName("MonsterName", true).TextGUIRendererComponent.Text == ui.catalogOptions[index][2],
            "original card keeps its unmodified catalog name")
    end
    local layout = ui.optionContainer.ScrollLayoutGroupComponent
    -- A scroll fraction alone cannot prove visibility when every card fits.
    -- Check the actual first-row position as well.
    expect(ui:GetMonsterOptionsScrollRange() == 0
        and math.abs(ui.optionCards[1].entity.UITransformComponent.WorldPosition.y - firstRowWorldY) < 0.1,
        "restoring the catalog keeps the original cards in the visible first row")
    ui.previewToggle:SendEvent(ButtonClickEvent(ui.previewToggle))
    waitForCards(18, verifyDeployment)
end

local function verifyPageBack()
    local layout = ui.optionContainer.ScrollLayoutGroupComponent
    expect(math.abs(layout:GetScrollNormalizedPosition().y - 0.5) < 0.001, "native vertical scroll moves away from the bottom")
    for _, card in ipairs(ui.optionCards) do table.insert(oldCards, card.entity) end
    ui.previewToggle:SendEvent(ButtonClickEvent(ui.previewToggle))
    waitForCards(3, verifyOriginalCatalog)
end

local function verifyEnd()
    local layout = ui.optionContainer.ScrollLayoutGroupComponent
    expect(layout:GetScrollNormalizedPosition().y > 0.999, "native vertical scroll reaches the last row")
    layout:SetScrollNormalizedPosition(UITransformAxis.Vertical, 0.5)
    later(verifyPageBack)
end

local function verifyPageForward()
    local layout = ui.optionContainer.ScrollLayoutGroupComponent
    expect(math.abs(layout:GetScrollNormalizedPosition().y - 0.5) < 0.001, "native vertical scroll advances through the list")
    expect(math.abs(layout:GetScrollNormalizedPosition().x - horizontalPosition) < 0.001,
        "moving down leaves the horizontal scroll position unchanged")
    layout:SetScrollNormalizedPosition(UITransformAxis.Vertical, 1)
    later(verifyEnd)
end

local function verifySelection()
    local card = ui.optionCards[18]
    expect(ui.selectionText.TextGUIRendererComponent.Text == card.monsterName,
        "selected label names the clicked copy rather than the first card sharing its MonsterId")
    local glowing = 0
    for _, candidate in ipairs(ui.optionCards) do
        if isvalid(candidate.glow) and candidate.glow.Enable then glowing = glowing + 1 end
    end
    expect(glowing == 1 and card.glow.Enable, "only the clicked test card is selected")
    ui.optionContainer.ScrollLayoutGroupComponent:ResetScrollPosition(UITransformAxis.Vertical)
    later(function()
        expect(math.abs(ui.optionContainer.ScrollLayoutGroupComponent:GetScrollNormalizedPosition().y) < 0.001,
            "native vertical scroll resets to the top")
        firstRowWorldY = ui.optionCards[1].entity.UITransformComponent.WorldPosition.y
        ui.optionContainer.ScrollLayoutGroupComponent:SetScrollNormalizedPosition(UITransformAxis.Vertical, 0.5)
        later(verifyPageForward)
    end)
end

local function verifyCards()
    expect(#ui.catalogOptions == 3 and #ui.optionCards == 18 and #ui.optionData == 18,
        "18 displayed test cards preserve the three-entry server catalog")
    local originals = {}
    for _, option in ipairs(ui.catalogOptions) do originals[option[1]] = option end
    for index, card in ipairs(ui.optionCards) do
        local source = originals[card.monsterId]
        expect(source ~= nil and ui.optionData[index][3] == source[3], "test card reuses an existing identity and portrait")
    end
    local first = ui.optionCards[1].entity.UITransformComponent
    local last = ui.optionCards[18].entity.UITransformComponent
    local layout = ui.optionContainer.ScrollLayoutGroupComponent
    expect(layout.Type == LayoutGroupType.Grid and layout.Constraint == GridLayoutConstraint.FixedColumnCount
        and layout.ConstraintCount == 5 and layout.StartAxis == GridLayoutAxis.Horizontal
        and layout.StartCorner == GridLayoutCorner.UpperLeft,
        "native grid fills five columns before starting the next row")
    expect(ui.deploymentPanel.UITransformComponent.RectSize.x == 1240
        and ui.optionContainer.UITransformComponent.RectSize.x == 812,
        "deployment panel and viewport widths are resized for five cards")
    for index, card in ipairs(ui.optionCards) do
        local position = card.entity.UITransformComponent.anchoredPosition
        local column = (index - 1) % 5
        local row = math.floor((index - 1) / 5)
        expect(math.abs(position.x - first.anchoredPosition.x - column * (layout.CellSize.x + layout.GridSpacing.x)) < 0.1
            and math.abs(position.y - first.anchoredPosition.y + row * (layout.CellSize.y + layout.GridSpacing.y)) < 0.1,
            "card " .. tostring(index) .. " occupies its expected column and row")
    end
    local requiredWidth = 5 * layout.CellSize.x + 4 * layout.GridSpacing.x
        + layout.Padding.left + layout.Padding.right + layout.ScrollBarThickness
    expect(requiredWidth <= ui.optionContainer.UITransformComponent.RectSize.x,
        "five complete cards fit beside the vertical scrollbar without horizontal overflow")
    expect(math.abs(last.anchoredPosition.y - first.anchoredPosition.y) > ui.optionContainer.UITransformComponent.RectSize.y,
        "four native grid rows overflow the viewport vertically")
    expect(layout.VerticalScrollBarDirection == VerticalScrollBarDirection.BottomToTop,
        "vertical scrollbar starts with its handle at the top")
    local receiver = ui.optionContainer.SpriteGUIRendererComponent
    expect(isvalid(receiver) and receiver.RaycastTarget and receiver.Color.a == 0,
        "the fixed viewport receives wheel input across transparent gaps")
    horizontalPosition = layout:GetScrollNormalizedPosition().x
    expect(layout.UseScroll and layout.ScrollBarVisible == ScrollBarVisibility.AutoHide and layout.ScrollBarThickness == 14,
        "native scrollbar is configured to appear on overflow")
    ui.optionCards[18].entity:SendEvent(ButtonClickEvent(ui.optionCards[18].entity))
    later(verifySelection)
end

local function boot(attempt)
    step(function()
        expect(isvalid(ui), "deployment UI adapter exists")
        if (not ui.optionsReady or ui.optionsBuilding) and attempt < 150 then
            later(function() boot(attempt + 1) end)
            return
        end
        expect(ui.optionsReady and not ui.optionsBuilding and ui.session.Phase == "DEPLOYMENT", "catalog is ready in deployment")
        expect(ui.session.PlayerAlive == 0, "fresh probe starts without deployed player units")
        originalPreviewCount = ui.PreviewCardCount
        ui:SetPreviewCardCount(18)
        waitForCards(18, verifyCards)
    end)
end

boot(0)
