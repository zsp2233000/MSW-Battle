-- Run in a fresh Maker Play test with context=client, after the lobby is ready (formationlobby, idle, formation loaded).
-- Opens the monster dex through its lobby entry's connected ButtonClickEvent, then drives the stage only through the
-- connected list-row and trial-button ButtonClickEvents and reads the stage image (ImageRUID, AnimClipPlayType, scale, flip)
-- and the public snapshot. Expected animation RUIDs come from the server's published rows; the stage scale expectation is
-- written down independently of the implementation: a 16:9 window is a 1920 unit wide canvas, the PC view is 12.8 world units wide at
-- camera zoom 100, so the battle camera (zoom 60) shows 12.8 * 100 / 60 world units and one world unit is 1920 / that = 90 canvas units.
-- A missing battle camera zoom is simulated at the end: the rows, the details and the selection must keep working, only the stage goes off.
-- The attack trial is checked per monster against the dex row's own delays (attackEffectDelay, impactDelay): the attack, effect and hit
-- effect events are recorded with their times and the effect sprites are inspected the moment each event appears. The hit point is written
-- down independently: one attack range in front of the attacker's body centre (like the combat rectangle), and the whole stage shrinks when
-- that point would pass the stage's right edge minus a margin.
-- A monster with a projectile clip and a speed launches its ball at the hit-frame delay from the attacker's body centre; the ball flies level (at the body-centre height) to the point one attack range ahead of the body centre in
-- attack range / speed seconds, like a combat ball at a target of the same height, and the hit effect appears at that arrival on the ground line (the distance is written down
-- independently: the attack range, in world units). Replaying, another button, another monster and closing remove the ball. Nothing is queued, stored or edited; the book is closed again at the end. Sounds cannot be heard here: the SOUND events record that
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

local CANVAS_WIDTH = 1920
local PC_WORLD_WIDTH_AT_ZOOM_100 = 12.8
local BATTLE_ZOOM = 60
local PIXELS_PER_UNIT = CANVAS_WIDTH / (PC_WORLD_WIDTH_AT_ZOOM_100 * 100 / BATTLE_ZOOM)
local SCALE_TOLERANCE = 0.01
local ART_PIXELS_PER_WORLD_UNIT = 100
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
local SOUNDS = { ATTACK = "attackSoundRuid", HURT = "hurtSoundRuid", DIE = "dieSoundRuid" }
local LOOPS = { IDLE = true, MOVE = true, ATTACK = false, HURT = false, DIE = false }

local TIME_TOLERANCE = 0.12
local function sprite() return dex.stageSprite end
local function stageWidth() return sprite().Entity.Parent.UITransformComponent.RectSize.x end
-- Independent geometry of one monster on the stage: the hit point is one attack range in front of the body centre, and the whole
-- stage shrinks (factor < 1) when that point would pass the right edge minus the margin.
local function expectedGeometry(row)
    local foot = sprite().Entity.UITransformComponent.anchoredPosition
    local bodyX = (row.bodyOffsetX or 0) * math.abs(row.scaleX)
    local needed = (row.attackRange - bodyX) * PIXELS_PER_UNIT
    local available = stageWidth() - foot.x - dex.HitPointMargin
    local factor = needed > available and available / needed or 1
    return { factor = factor, footX = foot.x, footY = foot.y, hitX = foot.x + (row.attackRange - bodyX) * PIXELS_PER_UNIT * factor }
end
local function hasBall(row) return (row.projectileRuid or "") ~= "" and (row.projectileSpeed or 0) > 0 end
-- Independent ball path of one monster: it leaves the body centre (the attacker's foot, bodyX behind and the body-centre height above it) and flies level to the point one
-- attack range ahead of the body centre (that is the hit point's x); the distance is the attack range itself, in world units, so the flight time does not depend on the stage shrink.
local function expectedFlight(row)
    local geometry = expectedGeometry(row)
    local unit = PIXELS_PER_UNIT * geometry.factor
    local bodyX = (row.bodyOffsetX or 0) * math.abs(row.scaleX)
    local bodyY = (row.bodyOffsetY or 0) * math.abs(row.scaleY)
    local flight = { startX = geometry.footX - bodyX * unit + (row.projectileOffsetX or 0) * unit, startY = geometry.footY + bodyY * unit + (row.projectileOffsetY or 0) * unit, endX = geometry.hitX, endY = geometry.footY + bodyY * unit, unit = unit, seconds = 0 }
    if hasBall(row) then flight.seconds = row.attackRange / row.projectileSpeed end
    return flight
end
local function clipRuid() return sprite().ImageRUID.DataId end
local function isLoop() return sprite().AnimClipPlayType == SpriteAnimClipPlayType.Loop end
-- The public snapshot costs about 50 ms a call (it rebuilds every detail text), too slow for polling at frame rate; the polls read the event log and action directly.
local function eventsOf(name)
    local found = {}
    for _, event in ipairs(dex._T.events) do if event.name == name then table.insert(found, event) end end
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
    local factor = expectedGeometry(row).factor
    local expectedX = PIXELS_PER_UNIT / ART_PIXELS_PER_WORLD_UNIT * row.scaleX * factor
    local expectedY = PIXELS_PER_UNIT / ART_PIXELS_PER_WORLD_UNIT * row.scaleY * factor
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

    -- A 16:9 window is what the literal expectation above assumes; any other shape cannot check the absolute scale.
    local aspect = _UILogic.ScreenWidth / _UILogic.ScreenHeight
    check(math.abs(aspect - 16 / 9) < 0.01, "the Maker window is 16:9 (" .. string.format("%.3f", aspect) .. "), so the literal scale expectation applies")
    check(dex:ActionSpecs() == dex:ActionSpecs() and dex:DetailSpecs() == dex:DetailSpecs(), "the constant tables are built once and shared")

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
    check(not markerShown(), "no hit marker before an attack trial")
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
    check(#eventsOf("ANIMATION_START") == 1 and secondStart > firstStart + row.attackDuration * 0.3, "replaying the same action starts a fresh trial")
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
    -- Reopening rebuilds the list and replaces the cached rows: take the new list entries and the live cache (the old ones are destroyed or stale).
    wait(0.5)
    rows = uiRows()
    latest = _MonsterDexService:GetLatest()
    stageShows(dex:GetSelectedRow(), "IDLE", "after reopening")


    -- Attack trial timing: for every monster, the sound, the attack effect and the hit effect come at the dex row's own delays.
    local function checkEffectSprite(effect, ruid, expectFlip, label, eventAge)
        -- A one-shot effect hides itself when its clip ends, so only a fresh event must still be on screen; the clip is always the row's.
        check((effect.Entity.Enable or eventAge > 0.12) and effect.ImageRUID.DataId == ruid, label .. ": the effect sprite shows the row's effect clip")
        check(effect.FlipX == expectFlip, label .. ": the effect " .. (expectFlip and "faces the attacker's way" or "is not flipped"))
        return effect.Entity.UITransformComponent
    end
    -- The hit marker is a dummy figure standing on the hit point (feet on the ground line) for the whole attack trial, drawn at the stage art scale and facing the attacker.
    local function markerShown() return dex.hitMarkerSprite.Entity.Enable end
    local function checkMarker(geometry, label)
        local marker = dex.hitMarkerSprite
        local box = marker.Entity.UITransformComponent
        local wantScale = geometry.factor * PIXELS_PER_UNIT / ART_PIXELS_PER_WORLD_UNIT
        check(marker.Entity.Enable, label .. ": the hit marker is shown from the trial start")
        check(math.abs(box.anchoredPosition.x - geometry.hitX) < 1 and math.abs(box.anchoredPosition.y - geometry.footY) < 1,
            label .. ": the hit marker stands at the hit point on the ground line (" .. string.format("%.1f,%.1f vs %.1f,%.1f", box.anchoredPosition.x, box.anchoredPosition.y, geometry.hitX, geometry.footY) .. ")")
        check(math.abs(box.UIScale.x - wantScale) < 0.001 and math.abs(box.UIScale.y - wantScale) < 0.001,
            label .. ": the hit marker follows the stage scale (" .. string.format("%.3f vs %.3f", box.UIScale.x, wantScale) .. ")")
        check(marker.FlipX == false and marker.ImageRUID.DataId == dex.HitMarkerRuid and #dex.HitMarkerRuid == 32, label .. ": the hit marker is the dummy art facing the attacker")
        check(marker.RaycastTarget == false, label .. ": the hit marker never takes clicks")
    end
    local function runAttack(row, label)
        local geometry = expectedGeometry(row)
        local wantEffect, wantHit = (row.attackEffectRuid or "") ~= "", (row.hitEffectRuid or "") ~= ""
        local flight = expectedFlight(row)
        local hitDelay = row.impactDelay + flight.seconds
        trial("ATTACK")
        local started = eventsOf("ANIMATION_START")[1]
        checkMarker(geometry, label)
        check(dex:GetSnapshot().hitMarkerShown == true and #eventsOf("SOUND") <= 1, label .. ": the snapshot reports the marker, and it plays no sound of its own")
        local deadline = _UtilLogic.ElapsedSeconds + math.max(row.attackDuration, row.attackEffectDelay, hitDelay) + 1.5
        local checkedEffect, checkedHit = false, false
        local samples, ballFlips, ballScaleOk, ballGoneAtHit = {}, {}, true, nil
        while _UtilLogic.ElapsedSeconds < deadline do
            local ball = dex.projectileSprite
            -- Read the event log first and the ball afterwards: the ball always leaves before the arrival is recorded, so a ball read after the log can never look newer than it.
            local snap = { events = dex._T.events, action = dex._T.action }
            local function seen(name)
                for _, event in ipairs(snap.events) do if event.name == name then return event end end
                return nil
            end
            if ball.Entity.Enable then
                local box = ball.Entity.UITransformComponent
                table.insert(samples, { at = _UtilLogic.ElapsedSeconds, x = box.anchoredPosition.x, y = box.anchoredPosition.y })
                table.insert(ballFlips, ball.FlipX)
                if math.abs(box.UIScale.x - flight.unit / ART_PIXELS_PER_WORLD_UNIT) > 0.001 or math.abs(box.UIScale.y - flight.unit / ART_PIXELS_PER_WORLD_UNIT) > 0.001 then ballScaleOk = false end
            end
            if wantEffect and not checkedEffect and seen("ATTACK_EFFECT") ~= nil then
                checkedEffect = true
                local box = checkEffectSprite(dex.attackEffectSprite, row.attackEffectRuid, true, label .. " attack effect", _UtilLogic.ElapsedSeconds - seen("ATTACK_EFFECT").at)
                local mine = sprite().Entity.UITransformComponent
                check(math.abs(box.anchoredPosition.x - (geometry.footX + (row.attackEffectOffsetX or 0) * PIXELS_PER_UNIT * geometry.factor)) < 1 and math.abs(box.anchoredPosition.y - (geometry.footY + (row.attackEffectOffsetY or 0) * PIXELS_PER_UNIT * geometry.factor)) < 1, label .. ": the attack effect is on the attacker, shifted by its registered offset")
                check(math.abs(box.UIScale.x - mine.UIScale.x) < 0.001 and math.abs(box.UIScale.y - mine.UIScale.y) < 0.001, label .. ": the attack effect is drawn at the attacker's scale")
            end
            if wantHit and not checkedHit and seen("HIT_EFFECT") ~= nil then
                checkedHit = true
                -- The event log is a live table that timers append to while this poll reads other properties, so the ball is read right after the event is seen: the ball leaves before the arrival is recorded.
                ballGoneAtHit = not ball.Entity.Enable
                local box = checkEffectSprite(dex.hitEffectSprite, row.hitEffectRuid, false, label .. " hit effect", _UtilLogic.ElapsedSeconds - seen("HIT_EFFECT").at)
                check(math.abs(box.anchoredPosition.x - (geometry.hitX + (row.hitEffectOffsetX or 0) * PIXELS_PER_UNIT * geometry.factor)) < 1 and math.abs(box.anchoredPosition.y - (geometry.footY + (row.hitEffectOffsetY or 0) * PIXELS_PER_UNIT * geometry.factor)) < 1,
                    label .. ": the hit effect is at the hit point, shifted by its registered offset (" .. string.format("%.1f,%.1f vs %.1f", box.anchoredPosition.x, box.anchoredPosition.y, geometry.hitX) .. ")")
            end
            if snap.action == "IDLE" and (checkedEffect or not wantEffect) and (checkedHit or not wantHit) and (not hasBall(row) or seen("PROJECTILE_ARRIVE") ~= nil) then break end
            wait(0.016)
        end
        local effects, hits = eventsOf("ATTACK_EFFECT"), eventsOf("HIT_EFFECT")
        if wantEffect then
            check(#effects == 1 and math.abs(effects[1].at - started.at - row.attackEffectDelay) < TIME_TOLERANCE and effects[1].ruid == row.attackEffectRuid,
                label .. ": one attack effect at the effect-frame delay " .. string.format("%.2f", row.attackEffectDelay) .. " (" .. (#effects > 0 and string.format("%.2f", effects[1].at - started.at) or "none") .. ")")
        else
            check(#effects == 0 and not dex.attackEffectSprite.Entity.Enable, label .. ": a blank attack effect is skipped")
        end
        if wantHit then
            check(#hits == 1 and math.abs(hits[1].at - started.at - hitDelay) < TIME_TOLERANCE and hits[1].ruid == row.hitEffectRuid,
                label .. ": one hit effect at the hit-frame delay plus the flight " .. string.format("%.2f", hitDelay) .. " (" .. (#hits > 0 and string.format("%.2f", hits[1].at - started.at) or "none") .. ")")
        else
            check(#hits == 0 and not dex.hitEffectSprite.Entity.Enable, label .. ": a blank hit effect is skipped")
        end
        local launches, arrivals = eventsOf("PROJECTILE_START"), eventsOf("PROJECTILE_ARRIVE")
        if hasBall(row) then
            check(#launches == 1 and launches[1].ruid == row.projectileRuid and math.abs(launches[1].at - started.at - row.impactDelay) < TIME_TOLERANCE,
                label .. ": the ball leaves at the hit-frame delay " .. string.format("%.2f", row.impactDelay) .. " (" .. (#launches > 0 and string.format("%.2f", launches[1].at - started.at) or "none") .. ")")
            check(#arrivals == 1 and #launches == 1 and math.abs(arrivals[1].at - launches[1].at - flight.seconds) < TIME_TOLERANCE,
                label .. ": the flight takes distance / speed " .. string.format("%.2f", flight.seconds) .. "s (" .. ((#arrivals > 0 and #launches > 0) and string.format("%.2f", arrivals[1].at - launches[1].at) or "none") .. ")")
            if wantHit then
                check(#hits == 1 and #arrivals == 1 and math.abs(hits[1].at - arrivals[1].at) < 0.05, label .. ": the hit effect appears at the ball's arrival")
                check(ballGoneAtHit == true, label .. ": the ball is gone the moment the hit effect appears")
            else
                check(#hits == 0, label .. ": a blank hit effect leaves the arrival silent")
            end
            check(not dex.projectileSprite.Entity.Enable and not dex:GetSnapshot().projectileActive, label .. ": no ball is left after the arrival")
            check(#samples >= 3 and launches[1] ~= nil, label .. ": the ball was seen flying (" .. tostring(#samples) .. " frames)")
            local deviation, backwards, previous = 0, false, nil
            local tolerance = 3 + row.projectileSpeed * flight.unit * 0.08
            for _, sample in ipairs(samples) do
                local progress = math.max(0, math.min(1, (sample.at - launches[1].at) / flight.seconds))
                local ex = flight.startX + (flight.endX - flight.startX) * progress
                local ey = flight.startY + (flight.endY - flight.startY) * progress
                deviation = math.max(deviation, math.abs(sample.x - ex), math.abs(sample.y - ey))
                if previous ~= nil and sample.x < previous - 0.5 then backwards = true end
                previous = sample.x
            end
            check(deviation <= tolerance, label .. ": the ball follows the straight line from the body centre to the hit point at distance / speed (worst " .. string.format("%.1f", deviation) .. "px, allowed " .. string.format("%.1f", tolerance) .. ")")
            check(not backwards, label .. ": the ball only moves forward")
            local flickered = false
            for _, flip in ipairs(ballFlips) do if flip ~= true then flickered = true end end
            check(not flickered, label .. ": the ball faces right in every frame (no flicker)")
            check(ballScaleOk, label .. ": the ball is drawn at the stage art scale (" .. string.format("%.3f", flight.unit / ART_PIXELS_PER_WORLD_UNIT) .. ")")
            if #samples > 0 then
                local first, last = samples[1], samples[#samples]
                -- The poll may notice the ball a few frames late or early; judge the first and last frames against the line at their own time (above) and against the ends only when they were seen close to them.
                if first.at - launches[1].at < 0.1 then
                    check(math.abs(first.x - flight.startX) < tolerance + 6 and math.abs(first.y - flight.startY) < tolerance + 6, label .. ": the ball starts at the attacker's body centre")
                else
                    check(first.at - launches[1].at < flight.seconds * 0.5, label .. ": the ball was first seen in the first half of its flight (" .. string.format("%.2f", first.at - launches[1].at) .. "s late)")
                end
                if arrivals[1].at - last.at < 0.1 then
                    check(math.abs(last.x - flight.endX) < tolerance + 6 and math.abs(last.y - flight.endY) < tolerance + 6, label .. ": the ball ends at the hit point")
                else
                    check(arrivals[1].at - last.at < flight.seconds * 0.5, label .. ": the ball was last seen in the second half of its flight (" .. string.format("%.2f", arrivals[1].at - last.at) .. "s early)")
                end
            end
        else
            check(#launches == 0 and #arrivals == 0 and not dex.projectileSprite.Entity.Enable and not dex:GetSnapshot().projectileActive, label .. ": no ball without a projectile clip and speed (instant hit)")
        end
        local sounds = eventsOf("SOUND")
        if (row.attackSoundRuid or "") ~= "" then
            check(#sounds == 1 and sounds[1].action == "ATTACK" and sounds[1].ruid == row.attackSoundRuid and math.abs(sounds[1].at - started.at) < 0.02,
                label .. ": the attack sound plays with the animation start and no hit sound follows")
        else
            check(#sounds == 0, label .. ": a blank attack sound plays nothing")
        end
        await(function() return dex:GetSnapshot().action == "IDLE" end, 5)
        check(markerShown(), label .. ": the hit marker stays after the attack returns to idle, until cleared")
        return started
    end
    local laterFrame, firstFrame = nil, nil
    for index, row in ipairs(latest) do
        click(rows[index])
        runAttack(row, row.monsterName .. " attack")
        if (row.attackEffectRuid or "") ~= "" then
            if row.attackEffectDelay > 0 then laterFrame = laterFrame or index else firstFrame = firstFrame or index end
        end
    end
    check(laterFrame ~= nil, "some monster has an attack effect on a later frame (" .. tostring(laterFrame) .. ")")
    -- The data may have no frame 1 effect: simulate it on the cached row of a monster with an attack effect (delay 0 is frame 1), restored afterwards.
    if firstFrame == nil and laterFrame ~= nil then
        click(rows[laterFrame])
        local frameRow = dex:GetSelectedRow()
        local savedDelay = frameRow.attackEffectDelay
        frameRow.attackEffectDelay = 0
        runAttack(frameRow, frameRow.monsterName .. " effect on frame 1 (simulated)")
        frameRow.attackEffectDelay = savedDelay
    end
    local withHit, withoutEffects = nil, nil
    for index, row in ipairs(latest) do
        if (row.hitEffectRuid or "") ~= "" then withHit = withHit or index end
        if (row.hitEffectRuid or "") == "" and (row.attackEffectRuid or "") == "" then withoutEffects = withoutEffects or index end
    end
    check(withHit ~= nil, "some monster has a hit effect")
    -- A monster with neither effect is covered by the blank-field run below when the data has none.

    -- Every in-flight effect is cleared: replaying, another button, another monster and closing.
    local timed = withHit or 1
    local timedRow = latest[timed]
    local otherIndex = timed == 1 and 2 or 1
    local pending = timedRow.impactDelay + timedRow.attackEffectDelay + 0.5
    click(rows[timed])
    trial("ATTACK")
    wait(timedRow.impactDelay * 0.5)
    trial("ATTACK")
    local replayStart = eventsOf("ANIMATION_START")[1].at
    check(#eventsOf("HIT_EFFECT") == 0 and #eventsOf("ATTACK_EFFECT") == 0, "a replay starts with a clean event log")
    check(markerShown(), "a replay shows the hit marker again")
    await(function() return #eventsOf("HIT_EFFECT") > 0 end, timedRow.impactDelay + 1)
    local replayHits = eventsOf("HIT_EFFECT")
    check(#replayHits == 1 and math.abs(replayHits[1].at - replayStart - timedRow.impactDelay) < TIME_TOLERANCE, "a replay's hit effect comes once, one hit delay after the replay started")
    await(function() return dex:GetSnapshot().action == "IDLE" end, 5)
    trial("ATTACK")
    wait(timedRow.impactDelay * 0.4)
    check(markerShown(), "the hit marker is shown during the attack trial")
    trial("MOVE")
    check(not dex.attackEffectSprite.Entity.Enable and not dex.hitEffectSprite.Entity.Enable, "another button hides the effect sprites")
    check(not markerShown() and dex:GetSnapshot().hitMarkerShown == false, "another button hides the hit marker")
    for _, action in ipairs({ "HURT", "DIE", "IDLE", "MOVE" }) do
        trial(action)
        check(not markerShown(), "a " .. action .. " trial shows no hit marker")
    end
    wait(pending)
    check(#eventsOf("HIT_EFFECT") == 0 and #eventsOf("ATTACK_EFFECT") == 0 and not dex.hitEffectSprite.Entity.Enable, "an aborted attack's pending effects never show")
    trial("IDLE")
    trial("ATTACK")
    wait(timedRow.impactDelay * 0.4)
    click(rows[otherIndex])
    check(not dex.attackEffectSprite.Entity.Enable and not dex.hitEffectSprite.Entity.Enable and #dex:GetSnapshot().events == 0, "switching monsters clears the effects and the log")
    check(not markerShown(), "switching monsters hides the hit marker")
    wait(pending)
    check(#dex:GetSnapshot().events == 0 and not dex.hitEffectSprite.Entity.Enable, "an abandoned attack's pending effects never show on the new monster")
    click(rows[timed])
    trial("ATTACK")
    wait(timedRow.impactDelay * 0.4)
    click(dex.closeButton.Entity)
    check(not dex.attackEffectSprite.Entity.Enable and not dex.hitEffectSprite.Entity.Enable, "closing the book clears the effects")
    check(not markerShown(), "closing the book hides the hit marker")
    wait(pending)
    check(not dex.hitEffectSprite.Entity.Enable and not dex.attackEffectSprite.Entity.Enable, "pending effects cannot revive after closing")
    click(dex.lobbyButton.Entity)
    check(await(function() return dex:GetSnapshot().open and sprite().Entity.Enable end, 8), "the book reopens")
    wait(0.5)
    rows = uiRows()

    -- Blank effect and sound fields are skipped silently (simulated on a cached row, restored afterwards).
    click(rows[timed])
    local cachedRow = dex:GetSelectedRow()
    local saved = { cachedRow.attackEffectRuid, cachedRow.hitEffectRuid, cachedRow.attackSoundRuid }
    cachedRow.attackEffectRuid, cachedRow.hitEffectRuid, cachedRow.attackSoundRuid = "", "", ""
    runAttack(cachedRow, cachedRow.monsterName .. " with blank fields")
    cachedRow.attackEffectRuid, cachedRow.hitEffectRuid, cachedRow.attackSoundRuid = saved[1], saved[2], saved[3]

    -- A hit point beyond the stage shrinks the whole stage and says by how much (simulated range on the cached row, restored afterwards).
    local longRow = dex:GetSelectedRow()
    local normalRange = longRow.attackRange
    check(expectedGeometry(longRow).factor == 1 and not dex.scaleLabel.Entity.Enable, "a hit point that fits keeps full scale and no multiplier label")
    longRow.attackRange = 30
    click(rows[otherIndex])
    click(rows[timed])
    local geometry = expectedGeometry(longRow)
    check(geometry.factor < 0.95, "the simulated range does not fit the stage (factor " .. string.format("%.3f", geometry.factor) .. ")")
    checkScaleAndFacing(longRow, "long range")
    check(dex.scaleLabel.Entity.Enable and string.find(dex.scaleLabel.Text, string.format("%.2f", geometry.factor), 1, true) ~= nil,
        "the multiplier is shown on screen (" .. tostring(dex.scaleLabel.Text) .. ")")
    check(math.abs(dex:GetSnapshot().stageFactor - geometry.factor) < 0.001, "the snapshot reports the factor")
    check(geometry.hitX <= stageWidth() - dex.HitPointMargin + 1, "the hit point lies inside the stage")
    runAttack(longRow, "long range attack")
    longRow.attackRange = normalRange
    click(rows[otherIndex])
    click(rows[timed])
    check(not dex.scaleLabel.Entity.Enable, "back at a fitting range the multiplier label is hidden")
    checkScaleAndFacing(longRow, "restored range")

    -- Projectile monsters: the stage shrink scales the ball's path while its flight time stays distance / speed (simulated long range on the cached row, restored afterwards).
    local ballIndex = nil
    for index, row in ipairs(latest) do if ballIndex == nil and hasBall(row) then ballIndex = index end end
    check(ballIndex ~= nil, "some monster has a projectile clip and speed (" .. tostring(ballIndex) .. ")")
    if ballIndex ~= nil then
        local elsewhere = (otherIndex == ballIndex) and timed or otherIndex
        click(rows[ballIndex])
        local ballRow = dex:GetSelectedRow()
        local savedRange = ballRow.attackRange
        local foot = sprite().Entity.UITransformComponent.anchoredPosition
        local bodyX = (ballRow.bodyOffsetX or 0) * math.abs(ballRow.scaleX)
        ballRow.attackRange = 1.6 * (stageWidth() - foot.x - dex.HitPointMargin) / PIXELS_PER_UNIT + bodyX
        click(rows[elsewhere])
        click(rows[ballIndex])
        check(expectedGeometry(ballRow).factor < 0.8, "the simulated ball range shrinks the stage (factor " .. string.format("%.3f", expectedGeometry(ballRow).factor) .. ")")
        runAttack(ballRow, ballRow.monsterName .. " shrunk-stage ball")
        ballRow.attackRange = savedRange
        click(rows[elsewhere])
        click(rows[ballIndex])

        -- A ball without a speed or without a clip is an instant hit at the hit-frame delay.
        local savedSpeed, savedRuid = ballRow.projectileSpeed, ballRow.projectileRuid
        ballRow.projectileSpeed = 0
        runAttack(ballRow, ballRow.monsterName .. " with no ball speed")
        ballRow.projectileSpeed = savedSpeed
        ballRow.projectileRuid = ""
        runAttack(ballRow, ballRow.monsterName .. " with no ball clip")
        ballRow.projectileRuid = savedRuid

        -- Every way out removes a ball in flight, and nothing it queued fires later.
        local flight = expectedFlight(ballRow)
        local function launchAndFly(label)
            trial("ATTACK")
            check(await(function() return dex.projectileSprite.Entity.Enable end, ballRow.impactDelay + 1), label .. ": the ball is flying")
            wait(flight.seconds * 0.4)
            check(dex.projectileSprite.Entity.Enable and dex:GetSnapshot().projectileActive, label .. ": still in flight")
        end
        local function checkGone(label)
            check(not dex.projectileSprite.Entity.Enable and not dex:GetSnapshot().projectileActive, label .. ": the ball is removed at once")
            wait(flight.seconds + 0.5)
            check(#eventsOf("PROJECTILE_ARRIVE") == 0 and #eventsOf("HIT_EFFECT") == 0 and not dex.projectileSprite.Entity.Enable and not dex.hitEffectSprite.Entity.Enable, label .. ": the removed ball never arrives or hits later")
        end
        launchAndFly("replay")
        trial("ATTACK")
        check(not dex.projectileSprite.Entity.Enable and #eventsOf("PROJECTILE_START") == 0, "replay: the old ball is gone and the event log is clean")
        check(await(function() return #eventsOf("PROJECTILE_ARRIVE") > 0 end, ballRow.impactDelay + flight.seconds + 1), "replay: the fresh ball arrives")
        check(#eventsOf("PROJECTILE_START") == 1 and #eventsOf("PROJECTILE_ARRIVE") == 1, "replay: exactly one ball flew")
        await(function() return dex:GetSnapshot().action == "IDLE" end, 5)
        launchAndFly("another button")
        trial("MOVE")
        checkGone("another button")
        trial("IDLE")
        launchAndFly("switching monster")
        click(rows[elsewhere])
        check(#dex:GetSnapshot().events == 0, "switching monster: the log is cleared")
        checkGone("switching monster")
        click(rows[ballIndex])
        launchAndFly("closing")
        click(dex.closeButton.Entity)
        checkGone("closing")
        click(dex.lobbyButton.Entity)
        check(await(function() return dex:GetSnapshot().open and sprite().Entity.Enable end, 8), "the book reopens after the ball checks")
        wait(0.5)
        rows = uiRows()
    end

    -- No battle camera zoom: only the stage is off. The list, the selection and the details keep working.
    local zoom = dex._T.battleZoom
    check(zoom ~= nil and math.abs(zoom - BATTLE_ZOOM) < 0.001 and dex:GetSnapshot().stageAvailable, "the server published the battle zoom " .. tostring(zoom))
    dex:ObserveBattleCamera(0)
    dex:Observe(latest)
    local snapshot = dex:GetSnapshot()
    check(snapshot.stageAvailable == false and snapshot.loadState == "READY", "without a zoom the snapshot reports the stage unavailable but the list ready")
    check(#uiRows() == #latest and #snapshot.rows == #latest, "every monster is still listed")
    check(#snapshot.details > 0 and snapshot.details[1].value ~= "", "the details are still filled")
    check(not sprite().Entity.Enable, "the stage image is hidden")
    local notice = dex.stageNotice
    check(notice.Entity.Enable and notice.Text == dex.StageUnavailableText and #notice.Text > 0, "a clear message says why the stage is off")
    local anyEnabled = false
    for _, property in pairs(BUTTONS) do if dex[property].Enable then anyEnabled = true end end
    check(not anyEnabled, "the trial buttons are disabled")
    check(dex:Play("ATTACK") == false, "a trial is refused")
    local other = dex:GetSelectedRow().monsterId == latest[2].monsterId and 1 or 2
    click(uiRows()[other])
    check(dex:GetSnapshot().selectedMonsterId == latest[other].monsterId and not sprite().Entity.Enable, "selecting a monster still works, the stage stays off")
    dex:ObserveBattleCamera(zoom)
    dex:Render()
    check(dex:GetSnapshot().stageAvailable and sprite().Entity.Enable and not notice.Entity.Enable, "restoring the zoom brings the stage back and hides the message")
    local restored = dex:GetSelectedRow()
    stageShows(restored, "IDLE", "after restoring the zoom")
    checkScaleAndFacing(restored, "after restoring the zoom")
    check(dex.attackButton.Enable and dex:Play("ATTACK"), "the trial buttons work again")
end)
if not ok then check(false, "probe raised: " .. tostring(detail)) end
if isvalid(dex) and dex:GetSnapshot().open then dex:Close() end
if failures == 0 then log("[VRF][MonsterDexStageProbe] PASS")
else log_error("[VRF][MonsterDexStageProbe] FAILURES=" .. tostring(failures)) end
