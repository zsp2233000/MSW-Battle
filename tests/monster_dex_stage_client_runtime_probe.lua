-- Run in a fresh Maker Play test with context=client, after the lobby is ready (formationlobby, idle, formation loaded).
-- Opens the monster dex through its lobby entry's connected ButtonClickEvent, then drives the stage only through the
-- connected list-row and trial-button ButtonClickEvents and reads the stage image (ImageRUID, AnimClipPlayType, scale, flip)
-- and the public snapshot. Expected animation RUIDs come from the server's published rows; the stage scale is
-- 90 canvas pixels per world unit, i.e. a 1920 px canvas across 12.8 / (60 / 100) world units (battle zoom 60, PC view 12.8 wide at 100).
-- Nothing is queued, stored or edited; the book is closed again at the end. Sounds cannot be heard here: the SOUND events record that
-- the sound call was made with the row's RUID, and a blank sound field is simulated on a cached row and restored.
local failures = 0
local function check(condition, message)
    if condition then log("[VRF][MonsterDexStageProbe][PASS] " .. message)
    else failures = failures + 1; log_error("[VRF][MonsterDexStageProbe][FAIL] " .. message) end
end

local function await(predicate, seconds)
    for _ = 1, math.floor((seconds or 10) / 0.05) do
        if predicate() then return true end
        wait(0.05)
    end
    return predicate()
end

local PIXELS_PER_UNIT = 90
local SCALE_TOLERANCE = 0.01
local dex = _MonsterDex
local function click(entity) entity:SendEvent(ButtonClickEvent()) end
local function uiRows()
    local rows = {}
    for _, child in ipairs(dex.listLayout.Entity.Children:ToTable()) do
        if string.sub(child.Name, 1, 4) == "Row_" and child.Enable then table.insert(rows, child) end
    end
    return rows
end
local BUTTONS = { IDLE = "idleButton", MOVE = "moveButton", ATTACK = "attackButton", HURT = "hurtButton", DIE = "dieButton" }
local function trial(action) click(dex[BUTTONS[action]].Entity) end
local FIELDS = { IDLE = "standRuid", MOVE = "moveRuid", ATTACK = "attackRuid", HURT = "hurtRuid", DIE = "dieRuid" }
local SOUNDS = { HURT = "hurtSoundRuid", DIE = "dieSoundRuid" }
local LOOPS = { IDLE = true, MOVE = true, ATTACK = false, HURT = false, DIE = false }

local function sprite() return dex.stageSprite end
local function clipRuid() return sprite().ImageRUID.DataId end
local function isLoop() return sprite().AnimClipPlayType == SpriteAnimClipPlayType.Loop end
local function eventsOf(name)
    local found = {}
    for _, event in ipairs(dex:GetSnapshot().events) do if event.name == name then table.insert(found, event) end end
    return found
end
local function sameColor(a, b) return math.abs(a.r - b.r) < 0.01 and math.abs(a.g - b.g) < 0.01 and math.abs(a.b - b.b) < 0.01 and math.abs(a.a - b.a) < 0.01 end

-- What the stage must show right now for one monster playing one action.
local function stageShows(row, action, label)
    local snapshot = dex:GetSnapshot()
    check(snapshot.action == action, label .. ": snapshot action is " .. action .. " (" .. tostring(snapshot.action) .. ")")
    check(clipRuid() == row[FIELDS[action]] and #clipRuid() == 32, label .. ": the stage plays the " .. action .. " animation of the row")
    check(isLoop() == LOOPS[action], label .. ": " .. action .. (LOOPS[action] and " loops" or " plays once"))
end

local function checkScaleAndFacing(row, label)
    local transform = sprite().Entity.UITransformComponent
    local expectedX = PIXELS_PER_UNIT / 100 * row.scaleX
    local expectedY = PIXELS_PER_UNIT / 100 * row.scaleY
    check(math.abs(transform.UIScale.x - expectedX) < SCALE_TOLERANCE and math.abs(transform.UIScale.y - expectedY) < SCALE_TOLERANCE,
        label .. ": stage scale follows the battle view and the model scale (" .. string.format("%.3f,%.3f", transform.UIScale.x, transform.UIScale.y)
        .. " vs " .. string.format("%.3f,%.3f", expectedX, expectedY) .. ")")
    check(sprite().FlipX == true, label .. ": the monster faces right (art is flipped)")
    check(sprite().Entity.Enable, label .. ": the stage image is shown")
end

local function buttonHighlight(action, label)
    for name, property in pairs(BUTTONS) do
        local color = dex[property].Entity.SpriteGUIRendererComponent.Color
        local expected = name == action and dex.TrialActiveColor or dex.TrialButtonColor
        if not sameColor(color, expected) then
            check(false, label .. ": the " .. name .. " button has the " .. (name == action and "active" or "normal") .. " colour")
            return
        end
    end
    check(true, label .. ": only the " .. action .. " button is highlighted")
end

-- One full one-shot trial: plays once, then idles on the animation end event.
local function checkOneShot(row, action, label)
    trial(action)
    stageShows(row, action, label)
    buttonHighlight(action, label)
    local started = eventsOf("ANIMATION_START")
    check(#started == 1 and started[1].action == action and started[1].ruid == row[FIELDS[action]], label .. ": one start event with the animation RUID")
    check(await(function() return dex:GetSnapshot().action == "IDLE" end, 6), label .. ": " .. action .. " returns to idle")
    stageShows(row, "IDLE", label .. " after " .. action)
    local ended = eventsOf("ANIMATION_END")
    check(#ended == 1 and ended[1].action == action, label .. ": exactly one animation end event, for " .. action)
    local idleStarts = eventsOf("ANIMATION_START")
    check(#idleStarts == 2 and idleStarts[2].action == "IDLE", label .. ": idle starts after the end event")
    check(ended[1].at <= idleStarts[2].at + 0.001 and ended[1].at - started[1].at > 0.05, label .. ": the end came after the clip ran")
    if action == "ATTACK" then
        local elapsed = ended[1].at - started[1].at
        check(math.abs(elapsed - row.attackDuration) < 0.35, label .. ": the attack clip ends about the published attack length (" .. string.format("%.2f vs %.2f", elapsed, row.attackDuration) .. ")")
    end
    local sound = SOUNDS[action]
    local sounds = eventsOf("SOUND")
    if sound ~= nil and (row[sound] or "") ~= "" then
        check(#sounds == 1 and sounds[1].action == action and sounds[1].ruid == row[sound], label .. ": " .. action .. " plays its own sound")
    else
        check(#sounds == 0, label .. ": " .. action .. " plays no sound")
    end
    buttonHighlight("IDLE", label .. " after " .. action)
end

local ok, detail = pcall(function()
    check(await(function()
        return isvalid(_UserService.LocalPlayer) and _UserService.LocalPlayer.CurrentMapName == "formationlobby"
            and _MatchFlowInput:AllowsFormationActions() and isvalid(dex.lobbyButton) and dex.lobbyButton.Enable
    end, 40), "the lobby is ready and the dex entry is usable")

    -- A closed book has no stage and refuses trials.
    check(not sprite().Entity.Enable, "before opening the stage image is hidden")
    check(dex:Play("ATTACK") == false, "a closed book refuses a trial")

    click(dex.lobbyButton.Entity)
    check(await(function() return dex:GetSnapshot().open and dex:GetSnapshot().loadState == "READY" end), "the entry opens the book and the rows arrive")
    local latest = _MonsterDexService:GetLatest()
    local rows = uiRows()
    check(latest ~= nil and #latest > 0 and #rows == #latest, "one list row per published monster (" .. tostring(#rows) .. ")")

    -- Opening shows the first monster idling at battle scale.
    check(await(function() return sprite().Entity.Enable end, 3), "opening shows the stage image")
    -- The selection survives from earlier use of the book in this Play (the first monster on a fresh Play).
    local opened = latest[1]
    for _, row in ipairs(latest) do if row.monsterId == dex:GetSnapshot().selectedMonsterId then opened = row end end
    stageShows(opened, "IDLE", "selected monster on open")
    checkScaleAndFacing(opened, "selected monster on open")
    check(#dex:GetSnapshot().events == 0, "the idle a monster starts with is not a logged trial")
    buttonHighlight("IDLE", "on open")

    -- The stage sits inside its panel on the ground line, left of centre.
    local stage = sprite().Entity.Parent
    local right = stage.Parent
    local stageSize = stage.UITransformComponent.RectSize
    local actor = sprite().Entity.UITransformComponent.anchoredPosition
    check(stage.Name == "Stage" and right.Name == "RightPage" and stage.UITransformComponent.anchoredPosition.y > -right.UITransformComponent.RectSize.y * 0.1,
        "the stage is the top of the right page")
    check(actor.x > 0 and actor.x < stageSize.x / 2 and actor.y > 0 and actor.y < stageSize.y / 2, "the actor stands low and left of centre inside the stage")

    -- Every monster: selecting it idles it at the right scale with the right clip.
    for index, row in ipairs(latest) do
        click(rows[index])
        stageShows(row, "IDLE", row.monsterName .. " selected")
        checkScaleAndFacing(row, row.monsterName .. " selected")
    end

    -- Every action of every monster starts the right clip with the right play type.
    for index, row in ipairs(latest) do
        click(rows[index])
        for _, action in ipairs({ "MOVE", "ATTACK", "HURT", "DIE", "IDLE" }) do
            trial(action)
            stageShows(row, action, row.monsterName)
        end
    end

    -- Full one-shot runs (animation end event, back to idle, sounds) on the first monster, a projectile monster and the last.
    local picks = { 1 }
    local projectile, last = nil, #latest
    for index, row in ipairs(latest) do if projectile == nil and (row.projectileRuid or "") ~= "" then projectile = index end end
    if projectile ~= nil then table.insert(picks, projectile) end
    table.insert(picks, last)
    for _, index in ipairs(picks) do
        local row = latest[index]
        click(rows[index])
        for _, action in ipairs({ "ATTACK", "HURT", "DIE" }) do checkOneShot(row, action, row.monsterName .. " " .. action) end
    end

    -- Idle and move keep looping: no end event, no return trip.
    local row = latest[1]
    click(rows[1])
    trial("MOVE")
    wait(row.attackDuration * 2 + 0.5)
    stageShows(row, "MOVE", "move after waiting")
    check(#eventsOf("ANIMATION_END") == 0, "a looping move never ends")
    trial("IDLE")
    wait(1.5)
    stageShows(row, "IDLE", "idle after waiting")
    check(#eventsOf("ANIMATION_END") == 0, "a looping idle never ends")

    -- Pressing the same button again restarts the clip from its beginning.
    trial("ATTACK")
    wait(row.attackDuration * 0.5)
    local firstStart = eventsOf("ANIMATION_START")[1].at
    trial("ATTACK")
    local secondStart = eventsOf("ANIMATION_START")[1].at
    check(#dex:GetSnapshot().events == 1 and secondStart > firstStart + row.attackDuration * 0.3, "replaying the same action starts a fresh trial")
    wait(row.attackDuration * 0.55)
    check(dex:GetSnapshot().action == "ATTACK" and #eventsOf("ANIMATION_END") == 0, "the replay is still running when the first run would have ended")
    check(await(function() return dex:GetSnapshot().action == "IDLE" end, 5), "the replay ends and returns to idle")
    local ended = eventsOf("ANIMATION_END")
    check(#ended == 1 and ended[1].at - secondStart > row.attackDuration * 0.8, "only the replay's own end is recorded after a full length")

    -- Another button aborts the running trial at once.
    trial("ATTACK")
    wait(0.2)
    trial("HURT")
    stageShows(row, "HURT", "hurt aborts attack")
    check(#eventsOf("ANIMATION_END") == 0 and eventsOf("ANIMATION_START")[1].action == "HURT", "the aborted attack leaves no end event")
    check(await(function() return dex:GetSnapshot().action == "IDLE" end, 5), "the replacing hurt returns to idle")
    check(#eventsOf("ANIMATION_END") == 1 and eventsOf("ANIMATION_END")[1].action == "HURT", "the only end event belongs to hurt")
    trial("DIE")
    wait(0.2)
    trial("MOVE")
    stageShows(row, "MOVE", "move aborts die")
    wait(1.5)
    stageShows(row, "MOVE", "move keeps looping after the aborted die")

    -- Choosing another monster during a trial puts the stage back to idle on the new monster.
    trial("ATTACK")
    wait(0.2)
    click(rows[2])
    stageShows(latest[2], "IDLE", "switching during an attack")
    checkScaleAndFacing(latest[2], "switching during an attack")
    check(#dex:GetSnapshot().events == 0, "switching clears the previous trial's events")
    wait(row.attackDuration + 0.5)
    stageShows(latest[2], "IDLE", "the abandoned attack never leaves idle")
    check(#eventsOf("ANIMATION_END") == 0, "no end event arrives from the abandoned monster")

    -- A blank hurt or die sound is skipped without error (simulated on the cached row, restored afterwards).
    local cached = dex:GetSelectedRow()
    local hurtSound, dieSound = cached.hurtSoundRuid, cached.dieSoundRuid
    cached.hurtSoundRuid = ""
    cached.dieSoundRuid = ""
    trial("HURT")
    check(#eventsOf("SOUND") == 0 and dex:GetSnapshot().action == "HURT", "a blank hurt sound is skipped, the animation still plays")
    await(function() return dex:GetSnapshot().action == "IDLE" end, 5)
    trial("DIE")
    check(#eventsOf("SOUND") == 0 and dex:GetSnapshot().action == "DIE", "a blank die sound is skipped, the animation still plays")
    await(function() return dex:GetSnapshot().action == "IDLE" end, 5)
    cached.hurtSoundRuid = hurtSound
    cached.dieSoundRuid = dieSound

    -- Unknown actions are refused; closing hides the stage and a reopening starts idle again.
    check(dex:Play("DANCE") == false, "an unknown action is refused")
    trial("ATTACK")
    click(dex.closeButton.Entity)
    check(not dex:GetSnapshot().open and not sprite().Entity.Enable and dex:GetSnapshot().action == "IDLE" and #dex:GetSnapshot().events == 0, "closing hides the stage and drops the trial")
    wait(row.attackDuration + 0.5)
    check(not sprite().Entity.Enable and dex:GetSnapshot().action == "IDLE", "a finished attack cannot revive the hidden stage")
    click(dex.lobbyButton.Entity)
    check(await(function() return dex:GetSnapshot().open and sprite().Entity.Enable end, 8), "reopening shows the stage again")
    stageShows(dex:GetSelectedRow(), "IDLE", "after reopening")
end)
if not ok then check(false, "probe raised: " .. tostring(detail)) end
if isvalid(dex) and dex:GetSnapshot().open then dex:Close() end
if failures == 0 then log("[VRF][MonsterDexStageProbe] PASS")
else log_error("[VRF][MonsterDexStageProbe] FAILURES=" .. tostring(failures)) end
