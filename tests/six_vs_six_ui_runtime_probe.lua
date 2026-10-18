-- Fresh Play, context=client. Uses connected UI events and production RPCs.
-- Observes renderer events; never supplies animation durations or changes combat state.
local failures = 0
local bindings = {}
local records = {}
local observer = 0
local finished = false
local map = _EntityService:GetEntityByPath("/maps/map01")
local adapter = isvalid(map) and map:GetComponent("script.BattleDeploymentInput") or nil

local function check(condition, message)
    if condition then log("[VRF][SixVsSixUI][PASS] " .. message)
    else failures = failures + 1; log_error("[VRF][SixVsSixUI][FAIL] " .. message) end
end

local function finish()
    if finished then return end
    finished = true
    if observer ~= 0 then _TimerService:ClearTimer(observer) end
    for _, binding in ipairs(bindings) do
        if isvalid(binding.entity) then binding.entity:DisconnectEvent(binding.eventType, binding.callback) end
    end
    if failures == 0 then log("[VRF][SixVsSixUI] PASS")
    else log_error("[VRF][SixVsSixUI] FAILURES=" .. tostring(failures)) end
end

local function later(action, delay)
    _TimerService:SetTimerOnce(function()
        if finished then return end
        local ok, detail = pcall(action)
        if not ok then check(false, "probe raised: " .. tostring(detail)); finish() end
    end, delay)
end

local function bind(entity, eventType, action)
    table.insert(bindings, { entity = entity, eventType = eventType,
        callback = entity:ConnectEvent(eventType, action) })
end

local function watchDeaths()
    for _, entity in ipairs(map.Children:ToTable()) do
        local unit = entity:GetComponent("script.BattleUnit")
        if isvalid(unit) then
            local record = { entity = entity, unit = unit, started = false, completed = false, sawFinal = false }
            table.insert(records, record)
            bind(entity, SpriteAnimPlayerStartEvent, function(event)
                if unit.IsDead and entity.SpriteRendererComponent.SpriteRUID == unit.DeathAnimationRUID then
                    record.started = true
                    record.player = event.AnimPlayer
                    check(entity.Visible, entity.Name .. " remains visible at die playback start")
                end
            end)
            bind(entity, SpriteAnimPlayerChangeFrameEvent, function(event)
                if not record.started or event.AnimPlayer ~= record.player or event.ReversePlaying then return end
                if event.TotalFrameCount > 1 and event.FrameIndex == event.TotalFrameCount - 1 then record.sawFinal = true end
                if event.FrameIndex == 0 and record.sawFinal then record.completed = true end
            end)
            bind(entity, SpriteAnimPlayerEndFrameEvent, function(event)
                if not record.started or event.AnimPlayer ~= record.player or event.ReversePlaying
                    or event.TotalFrameCount ~= 1 then return end
                if record.sawFinal then record.completed = true else record.sawFinal = true end
            end)
            bind(entity, SpriteAnimPlayerEndEvent, function(event)
                if record.started and event.AnimPlayer == record.player then record.completed = true end
            end)
        end
    end
    check(#records == 12, "client observes twelve production units")
    observer = _TimerService:SetTimerRepeat(function()
        if finished then return end
        for _, record in ipairs(records) do
            if record.started and not record.completed and not record.entity.Visible and not record.earlyHide then
                record.earlyHide = true
                check(false, record.entity.Name .. " hid before a complete renderer playback")
            end
        end
    end, 0.02)
end

local roster = { "monster_tank", "monster_tank", "monster_warrior", "monster_warrior", "monster_shooter", "monster_shooter" }
local positions = { Vector3(-4.4, 1, 0), Vector3(-4.4, 0, 0), Vector3(-4.4, -1, 0),
    Vector3(-4.4, -2, 0), Vector3(-4.4, -3, 0), Vector3(-3.4, -1, 0) }
local cards = {}

local function observeResult(elapsed)
    if adapter.session.Phase ~= "RESULT" and elapsed < 45 then
        later(function() observeResult(elapsed + 1) end, 1)
        return
    end
    check(adapter.session.Phase == "RESULT", "UI-started six-versus-six battle reaches RESULT within 45 seconds")
    if adapter.session.Phase ~= "RESULT" then finish(); return end
    later(function()
        local result = adapter.session.Result
        local win, lose, draw = adapter.resultWin.Enable, adapter.resultLose.Enable, adapter.resultDraw.Enable
        check((win and 1 or 0) + (lose and 1 or 0) + (draw and 1 or 0) == 1
            and ((result == "WIN" and win) or (result == "LOSE" and lose) or (result == "DRAW" and draw)),
            "exactly the matching delivered result entity is enabled")
        local resultCount = 0
        for event in string.gmatch(adapter.session.EventHistory, "[^;]+") do
            if string.match(event, "^RESULT:") then resultCount = resultCount + 1 end
        end
        check(resultCount == 1, "client receives exactly one RESULT signal")
        local dead = 0
        for _, record in ipairs(records) do
            if record.unit.IsDead then
                dead = dead + 1
                check(record.started and record.completed and not record.earlyHide and not record.entity.Visible,
                    record.entity.Name .. " hides only after native die playback completes")
            end
        end
        check(dead > 0, "natural battle exercises death presentation")
        finish()
    end, 2)
end

local function deploy(index)
    if index > #roster then
        adapter:HandleBattlefieldClick(Vector3(-2, 0, 0))
        later(function()
            check(adapter.session.PlayerAlive == 6, "seventh UI deployment is rejected")
            watchDeaths()
            adapter.startButton:SendEvent(ButtonClickEvent(adapter.startButton))
            later(function()
                check(adapter.session.InitialPlayerAlive == 6 and adapter.session.InitialEnemyAlive == 6,
                    "connected start-button event starts six against six")
                check(not adapter.optionContainer.Enable and not adapter.startButton.Enable, "deployment controls close after start")
                observeResult(0)
            end, 0.5)
        end, 0.5)
        return
    end
    local card = cards[roster[index]]
    if card == nil then check(false, "required card missing"); finish(); return end
    card.entity:SendEvent(ButtonClickEvent(card.entity))
    check(adapter.selectedMonsterId == roster[index], "card event selects " .. roster[index])
    adapter:HandleBattlefieldClick(positions[index])
    later(function()
        local entity = _EntityService:GetEntityByPath("/maps/map01/M1_Player_" .. tostring(index))
        local unit = isvalid(entity) and entity:GetComponent("script.BattleUnit") or nil
        check(adapter.session.PlayerAlive == index and isvalid(unit) and unit.MonsterId == roster[index],
            "UI deployment " .. tostring(index) .. " binds the selected MonsterId")
        deploy(index + 1)
    end, 0.5)
end

local function boot(attempt)
    if not isvalid(adapter) then check(false, "deployment adapter unavailable"); finish(); return end
    if (not adapter.optionsReady or adapter.optionsBuilding) and attempt < 100 then later(function() boot(attempt + 1) end, 0.1); return end
    if adapter.optionsReady and not adapter.optionsBuilding then adapter:SetPreviewCardCount(0) end
    check(adapter.optionsReady and #adapter.optionCards == 3, "formal catalog supplies three named cards")
    if not adapter.optionsReady then finish(); return end
    for index, card in ipairs(adapter.optionCards) do
        local option = adapter.optionData[index]
        cards[card.monsterId] = card
        check(card.entity:GetChildByName("MonsterName", true).TextGUIRendererComponent.Text == option[2]
            and card.monsterId == option[1], "displayed name and MonsterId come from the same catalog row")
    end
    check(adapter.session.Phase == "DEPLOYMENT" and adapter.session.PlayerAlive == 0, "UI flow begins with zero deployed units")
    adapter.startButton:SendEvent(ButtonClickEvent(adapter.startButton))
    later(function()
        check(adapter.session.Phase == "DEPLOYMENT", "connected start event rejects zero units")
        deploy(1)
    end, 0.5)
end

later(function() boot(0) end, 0.1)
