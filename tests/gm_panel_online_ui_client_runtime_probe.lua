-- client. Run with EXPECT_OTHER before adding a virtual player (false), after
-- arrival (true), in another room (true), and after kicking that player (false).
local EXPECT_OTHER = false
local OTHER = 'GM8802'
assert(Environment:IsMakerPlay(), 'Maker only')
local gm = _GMPanel
local myCode = _UserService.LocalPlayer.PlayerComponent.ProfileCode
local function await(predicate, label)
    for _ = 1, 150 do if predicate() then return end wait(0.1) end
    error(label .. ': ' .. gm.statusText.Text)
end
local function clickable(button) return isvalid(button) and button.Enable and button.Entity.EnabledInHierarchy end
local function click(button)
    assert(clickable(button), 'visible clickable control')
    button.Entity:SendEvent(ButtonClickEvent())
end
local function playerRow(profile)
    for _, row in ipairs(gm.onlineLayout.Entity.Children:ToTable()) do
        if row.EnabledInHierarchy and row.Name:sub(1, 9) == 'GMPlayer_'
            and row.TextGUIRendererComponent.Text:find('（' .. profile .. '）', 1, true) then return row end
    end
end
local function levelSnapshot(profile)
    if not gm.statusText.Text:find(profile, 1, true) or not gm.listLayout.Entity.EnabledInHierarchy
        or not clickable(gm.saveButton) then return nil end
    local values = {}
    for _, row in ipairs(gm.listLayout.Entity.Children:ToTable()) do
        if row.EnabledInHierarchy and row.Name:sub(1, 6) == 'GMRow_' then
            table.insert(values, row:GetChildByName('Name').TextGUIRendererComponent.Text
                .. ':' .. row:GetChildByName('LevelInput').TextGUIRendererInputComponent.Text
                .. ':' .. row:GetChildByName('ExperienceInput').TextGUIRendererInputComponent.Text)
        end
    end
    if #values == 0 then return nil end
    table.sort(values)
    return gm.statusText.Text .. '\n' .. table.concat(values, '\n')
end

await(function() return clickable(gm.lobbyButton) end, 'GM entry')
click(gm.lobbyButton)
await(function() return clickable(gm.onlineButton) end, 'initial target loaded')
click(gm.onlineButton)
await(function() return playerRow(myCode) and clickable(gm.onlineButton) end, 'online list includes self')
click(gm.onlineButton)
await(function() return playerRow(myCode) and clickable(gm.onlineButton) end, 'refresh completes')
assert((playerRow(OTHER) ~= nil) == EXPECT_OTHER, 'refresh reflects online virtual player')
local code = EXPECT_OTHER and OTHER or myCode
click(playerRow(code).ButtonComponent)
local selected
await(function() selected = levelSnapshot(code) return selected ~= nil end, 'select online player')
assert(gm.targetInput.Text == code and not gm.onlineLayout.Entity.EnabledInHierarchy, 'selection populates target')
gm.targetInput.Text = code
click(gm.loadButton)
local typed
await(function() typed = levelSnapshot(code) return typed ~= nil end, 'type same code manually')
assert(typed == selected, 'selection and manual load render the same result')
click(gm.closeButton)
log('[VRF][GMPanelOnlineUIProbe] PASS refresh; self; select equals live load; present=' .. tostring(EXPECT_OTHER))
