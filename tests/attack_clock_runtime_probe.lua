-- Run in a fresh Maker Play test with context=server_main.
-- Manual time controls custom battle logic; native physics still runs normally.
local map = _EntityService:GetEntityByPath("/maps/map01")
local session = isvalid(map) and map:GetComponent("script.BattleSession") or nil
local failures = 0

local function check(condition, message)
    if condition then log("[M1][AttackClockProbe][PASS] " .. message)
    else failures = failures + 1; log_error("[M1][AttackClockProbe][FAIL] " .. message) end
end

local function row(monsterId, name, x, y, overrides)
    return { monsterId = monsterId, name = name, position = Vector3(x, y, 0), overrides = overrides }
end

local function unitByName(name)
    local entity = _EntityService:GetEntityByPath("/maps/map01/" .. name)
    if not isvalid(entity) then return nil, nil end
    return entity, entity:GetComponent("script.BattleUnit")
end

if not isvalid(session) then
    check(false, "BattleSession is available on map01")
elseif session.BeginManualSimulation == nil or session.PrepareBattleForTest == nil then
    check(false, "manual clock and controlled scene APIs are available")
else
    local acquireOk, acquired = pcall(function() return session:BeginManualSimulation() end)
    if not acquireOk then
        check(false, "manual clock acquisition raised: " .. tostring(acquired))
    elseif acquired ~= true then
        check(false, "manual clock is acquired explicitly")
    else
        local ownsClock = true
        local runOk, completed = pcall(function()
            check(not session:BeginManualSimulation(), "a second driver cannot acquire the owned clock")

            local actorName = "Issue16_ClockShooter"
            local targetName = "Issue16_ClockTarget"
            local playerRoster = {
                row("monster_shooter", actorName, -1, 0, {
                    MoveSpeed = 0,
                    RetargetIntervalSeconds = 0,
                    ImpactDelaySeconds = 0.18,
                    AttackIntervalSeconds = 0.8,
                }),
            }
            local enemyRoster = {
                row("monster_warrior", targetName, -0.5, 0, {
                    MoveSpeed = 0,
                    AttackDamage = 0,
                    AttackRange = 0,
                    RetargetIntervalSeconds = 0,
                    ImpactDelaySeconds = 0.05,
                    AttackIntervalSeconds = 100,
                }),
            }
            local prepared = session:PrepareBattleForTest(playerRoster, enemyRoster)
            check(prepared == true, "manual owner prepares a complete controlled clock scene")
            if prepared ~= true then return false end
            check(session.PlayerAlive == 1 and session.EnemyAlive == 1,
                "prepared shooter and target are both included in real alive counts")

            local actorEntity, actor = unitByName(actorName)
            local targetEntity, target = unitByName(targetName)
            check(isvalid(actorEntity) and isvalid(actor) and isvalid(targetEntity) and isvalid(target),
                "the clock scene resolves fresh actor and target references")
            if not isvalid(actorEntity) or not isvalid(actor) or not isvalid(targetEntity) or not isvalid(target) then
                return false
            end

            local started = session:TryStartBattle()
            check(started == true and session.Phase == "BATTLE"
                and session.InitialPlayerAlive == 1 and session.InitialEnemyAlive == 1,
                "the prepared 1v1 enters BATTLE with complete initial counts")
            if started ~= true then return false end

            local initialHp = target.Hp
            session:AdvanceForTest(0.05)
            check(actor.AttackSerial == 1 and target.Hp == initialHp,
                "manual session time starts one attack before its impact")

            wait(0.35)
            check(actor.AttackSerial == 1 and target.Hp == initialHp,
                "live Maker frames do not advance attacks while this probe owns the clock")

            session:AdvanceForTest(actor.ImpactDelay + 0.02)
            check(target.Hp == initialHp - 30 and target.DamageTakenSerial == 1,
                "manual elapsed time reaches the real shooter HitEvent and damage batch")

            local released, releaseDetail = pcall(function() session:EndManualSimulation() end)
            ownsClock = not released
            check(released, "the probe releases its own manual clock" ..
                (released and "" or ": " .. tostring(releaseDetail)))
            if not released then return false end

            local serialAfterRelease = actor.AttackSerial
            local hpAfterRelease = target.Hp
            session:AdvanceForTest(10)
            check(actor.AttackSerial == serialAfterRelease and target.Hp == hpAfterRelease,
                "manual elapsed time is rejected after the probe releases ownership")

            wait(1.1)
            check(actor.AttackSerial > serialAfterRelease and target.Hp < hpAfterRelease,
                "live clock resumes automatic attacks after release")
            return true
        end)

        if ownsClock then
            local releaseOk, releaseDetail = pcall(function() session:EndManualSimulation() end)
            if releaseOk then ownsClock = false end
            if not releaseOk then check(false, "error cleanup could not release the probe clock: " .. tostring(releaseDetail)) end
        end
        if not runOk then
            check(false, "clock probe raised: " .. tostring(completed))
        elseif completed ~= true then
            check(false, "clock probe could not complete its prepared scene")
        end
    end
end

if failures == 0 then
    log("[M1][AttackClockProbe] PASS")
else
    log_error("[M1][AttackClockProbe] FAILURES=" .. tostring(failures))
end
