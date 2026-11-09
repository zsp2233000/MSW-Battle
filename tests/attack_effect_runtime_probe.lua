-- Fresh Maker Play, server_main. Client [VRF][BattleEffect] logs prove actual playback.
local map = _EntityService:GetEntityByPath("/maps/template")
local session = isvalid(map) and map:GetComponent("script.BattleSession") or nil
local ownsClock = false
local failures = 0
local function check(ok, message)
    if ok then log("[VRF][AttackEffectProbe][PASS] " .. message)
    else failures = failures + 1; log_error("[VRF][AttackEffectProbe][FAIL] " .. message) end
end
local function row(id, name, x)
    return { monsterId = id, name = name, position = Vector3(x, 0, 0),
        overrides = { MoveSpeed = 0, AttackDamageMin = 0, AttackDamageMax = 0, AttackIntervalSeconds = 100 } }
end
local ok, detail = pcall(function()
    check(isvalid(session), "battle session exists")
    if not isvalid(session) then return end
    ownsClock = session:BeginManualSimulation()
    check(ownsClock, "manual clock acquired")
    if not ownsClock then return end
    local ruid = session:GetMonsterProfile("monster_warrior").HitEffectRUID
    for _, id in ipairs({ "monster_tank", "monster_warrior", "monster_shooter" }) do
        for _, whiff in ipairs({ false, true }) do
            local name = "Effect_" .. id .. (whiff and "_whiff" or "_hit")
            check(session:PrepareBattleForTest({ row(id, name, 0) }, {
                row("monster_warrior", "EffectTargetA", 0.5), row("monster_warrior", "EffectTargetB", 0.5),
            }), "controlled scene prepared")
            check(session:TryStartBattle(), "battle started")
            local actor = map:GetChildByName(name)
            local unit = actor:GetComponent("script.BattleUnit")
            local attack = actor:GetComponent("script.BattleAttackComposition")
            local target = map:GetChildByName("EffectTargetA")
            local profile = {}
            for key, value in pairs(session:GetMonsterProfile(id)) do profile[key] = value end
            profile.AttackEffectRUID = ruid
            profile.ImpactDelaySeconds = 0.25
            check(attack:Configure(profile, 0), "effect profile configured")
            unit:DriveAttack(target, false)
            check(unit.AttackSerial == 0, "rejected attack has no start or effect")
            unit:DriveAttack(target, true)
            unit:DriveAttack(target, true)
            check(unit.AttackSerial == 1, "repeated request produces one start and one ATTACK effect log for " .. name)
            if whiff then
                target.KinematicbodyComponent:SetWorldPosition(Vector2(5, 0))
                map:GetChildByName("EffectTargetB").KinematicbodyComponent:SetWorldPosition(Vector2(5, 0))
            end
            unit:AdvanceAttack(0.3)
            session:AdvanceForTest(0.001)
            check(unit.AttackSerial == 1, "impact does not replay the attack effect")
            if whiff then
                check(target:GetComponent("script.BattleUnit").DamageTakenSerial == 0, "whiff retains its start effect without damage")
            end
            -- Allow the real client RPC to render before replacing the scene.
            wait(0.5)
        end
    end
end)
if ownsClock then session:EndManualSimulation() end
if not ok then check(false, "probe raised: " .. tostring(detail)) end
if failures == 0 then log("[VRF][AttackEffectProbe] PASS; also require one successful client ATTACK effect per named actor")
else log_error("[VRF][AttackEffectProbe] FAILURES=" .. tostring(failures)) end
