-- client, dispatched while the battle runs: moving rooms resets the client context (#51). Reads the
-- player-visible HUD and result through the formal UI, waits for the natural result, optionally for a
-- server-side identity swap, then clicks return. The context ends on return, so log before dispatch.
local MODE = "FLOW" -- EXPERIENCE observes the isolated #68 fixture and leaves return to its owner.
local ok, detail = pcall(function()
    local player = _UserService.LocalPlayer
    assert(player.CurrentMapName == "matchprobe", "client is in the match")
    local battle = player.CurrentMap:GetComponent("script.BattleSession")
    local ui = _BattleUIController
    local text = function(entity) return entity.TextGUIRendererComponent.Text end
    if MODE == "EXPERIENCE" or MODE == "EXPERIENCE_MAX" then
        local function await(predicate)
            for _ = 1, 1500 do if predicate() then return true end wait(0.1) end
            return false
        end
        assert(await(function() return ui.OwnResult ~= "" and ui.result.Enable end), "natural result becomes visible")
        local caption = ui.result:GetChildByName("Window"):GetChildByName("Caption")
        local function cards()
            local result = {}
            for _, entity in ipairs(ui.result.Children:ToTable()) do
                if string.sub(entity.Name, 1, 11) == "Experience_" and entity.EnabledInHierarchy then table.insert(result, entity) end
            end
            return result
        end
        if battle.ExperienceResult.status == "PENDING" then
            assert(text(caption) == "怪物經驗結算處理中…" and #cards() == 0, "pending never previews gains")
            log("[VRF][MatchedResultUI] EXPERIENCE_PENDING_PASS")
        end
        assert(await(function() return battle.ExperienceResult.status == "SAVED" or battle.ExperienceResult.status == "FAILED" end), "bounded settlement acknowledgement")
        wait(0.2)
        if battle.ExperienceResult.status == "FAILED" then
            assert(text(caption) == "怪物經驗結算失敗" and #cards() == 0, "storage failure shows no fictional upgrade")
            log("[VRF][MatchedResultUI] EXPERIENCE_FAILED_PASS")
            return
        end
        local receipt = battle.ExperienceResult
        local own = player.PlayerComponent.ProfileCode == battle.HomeProfile and "PLAYER" or "ENEMY"
        local expected, dead = {}, 0
        for _, unit in ipairs(player.CurrentMap:GetChildComponentsByTypeName("script.BattleUnit", false)) do
            if unit.Faction == own then
                expected[unit.MonsterId] = expected[unit.MonsterId] or {name=unit.MonsterName, deaths=0}
                if unit.IsDead then dead = dead + 1 end
                if unit.IsDead and unit.Level < 30 then expected[unit.MonsterId].deaths = expected[unit.MonsterId].deaths + 1 end
            end
        end
        local unique = 0
        for _ in pairs(expected) do unique = unique + 1 end
        assert(#receipt.monsters == unique and #cards() == unique, "one card per own monster, including merged duplicates")
        local seen, upgrades = {}, 0
        for index, entry in ipairs(receipt.monsters) do
            local want = expected[entry.monsterId]
            assert(want and not seen[entry.monsterId] and entry.gained == want.deaths, "own deaths alone grant experience")
            seen[entry.monsterId] = true
            local card = ui.result:GetChildByName("Experience_" .. index)
            assert(text(card:GetChildByName("MonsterName")) == want.name, "own monster name")
            assert(text(card:GetChildByName("Identity")) == "經驗 +" .. entry.gained, "confirmed experience displayed")
            if entry.before then
                upgrades = upgrades + 1
                local detail = card:GetChildByName("Progression")
                local wanted = "Lv." .. entry.before.level .. " → Lv." .. entry.after.level
                    .. "\n生命 " .. entry.before.MaxHp .. " → " .. entry.after.MaxHp
                    .. "\n傷害 " .. entry.before.AttackDamageMin .. "～" .. entry.before.AttackDamageMax
                    .. "\n→ " .. entry.after.AttackDamageMin .. "～" .. entry.after.AttackDamageMax
                assert(detail.EnabledInHierarchy and text(detail) == wanted, "both levels, maximum HP and damage endpoints")
                assert(detail.TextGUIRendererComponent:GetPreferredHeight(wanted, 117) <= 126, "upgrade details fit the existing card")
            end
        end
        if MODE == "EXPERIENCE_MAX" then
            assert(dead > 0, "at least one own max-level monster died naturally")
            assert(upgrades == 0, "max-level monsters never upgrade")
            for _, entry in ipairs(receipt.monsters) do assert(entry.gained == 0, "max-level deaths grant zero experience") end
        else
            assert(upgrades > 0, "the successful fixture must exercise actual level changes")
            for _, entry in ipairs(receipt.monsters) do
                if entry.monsterId == "monster_tank" then
                    assert(entry.gained == 2 and entry.before.level == 1 and entry.after.level == 2
                        and entry.before.MaxHp == 400 and entry.after.MaxHp == 413, "literal two-death tank upgrade")
                end
            end
        end
        -- Exercise the public client receipt boundary without changing server settlements or player saves.
        local ran, failure = pcall(function()
            for _, state in ipairs({"PENDING", "FAILED"}) do
                battle:ReceiveExperienceResult({profile=receipt.profile, matchId=receipt.matchId, status=state, monsters=receipt.monsters})
                wait(0.1)
                assert(#cards() == 0, "unconfirmed candidate rows are hidden: " .. state)
                assert(text(caption) == (state == "FAILED" and "怪物經驗結算失敗" or "怪物經驗結算處理中…"), "visible settlement state")
            end
            local zero = receipt.monsters[1]
            battle:ReceiveExperienceResult({profile=receipt.profile, matchId=receipt.matchId, status="SAVED",
                monsters={{monsterId=zero.monsterId,name=zero.name,ruid=zero.ruid,gained=0}}})
            wait(0.1)
            assert(#cards() == 1 and text(cards()[1]:GetChildByName("Identity")) == "經驗 +0", "survivor earns zero")
            assert(not cards()[1]:GetChildByName("Progression").Enable, "zero gain has no upgrade")
            battle:ReceiveExperienceResult({profile=receipt.profile, matchId="stale-match", status="SAVED", monsters=receipt.monsters})
            wait(0.1)
            assert(#cards() == 1 and battle.ExperienceResult.matchId == receipt.matchId, "stale receipt cannot replace this match's confirmed data")
            battle:ReceiveExperienceResult({profile="another-player", matchId=receipt.matchId, status="SAVED", monsters=receipt.monsters})
            assert(battle.ExperienceResult.profile == receipt.profile, "another player's receipt is rejected")
        end)
        battle:ReceiveExperienceResult(receipt)
        wait(0.1)
        assert(ran, failure)
        assert(#cards() == unique, "confirmed cards restored without duplicates")
        local marker = MODE == "EXPERIENCE_MAX" and "EXPERIENCE_MAX_PASS" or "EXPERIENCE_PASS"
        log("[VRF][MatchedResultUI] " .. marker .. " own monsters=" .. unique .. "; merged deaths; levels/HP/damage; pending/failure; +0; foreign/stale receipts")
        return
    end
    local counts = function()
        -- Expected numbers come from the unit roster sides, not from the controller's own swap.
        local home, away = 0, 0
        for _, unit in ipairs(player.CurrentMap:GetChildComponentsByTypeName("script.BattleUnit", false)) do
            if unit.Hp > 0 then
                if unit.Faction == "PLAYER" then home = home + 1 else away = away + 1 end
            end
        end
        if player.PlayerComponent.ProfileCode == battle.AwayProfile then return away, home end
        return home, away
    end
    local seenBattle = false
    for attempt = 1, 900 do
        if battle.Phase == "BATTLE" and _MatchFlowInput.Snapshot.state == "BATTLE" then
            seenBattle = true
            assert(ui.hud.Enable and not ui.deployment.Enable and not ui.result.Enable, "battle shows the HUD only")
            assert(ui.hud.SpriteGUIRendererComponent.RaycastTarget == false, "HUD does not intercept the field")
            assert(not _MatchFlowInput.root:GetChildByName("BattleMatch", false).Enable, "match panel leaves the field clear")
            assert(not _MatchFlowInput.root:GetChildByName("BattleResult", false).Enable, "no result during battle")
            assert(not _EntityService:GetEntityByPath("/ui/FormationGroup").Enable, "formation UI is off during battle")
            assert(text(ui.phaseText) == "戰鬥進行中", "battle phase text")
            local own, enemy = counts()
            log("[VRF][MatchedResultUI] BATTLE_VIEW profile=" .. player.PlayerComponent.ProfileCode .. " home=" .. battle.HomeProfile .. " hud=" .. text(ui.playerCount) .. "/" .. text(ui.enemyCount) .. " roster=" .. tostring(own) .. "/" .. tostring(enemy))
            break
        end
        wait(0.1)
    end
    assert(seenBattle, "observed the running battle")
    local swapped = false
    local swapHome = battle.HomeProfile
    for attempt = 1, 900 do
        if battle.HomeProfile ~= swapHome and not swapped then
            swapped = true
            wait(0.5)
            local own, enemy = counts()
            assert(text(ui.playerCount) == tostring(own) and text(ui.enemyCount) == tostring(enemy), "swapped HUD follows the viewer's side")
            log("[VRF][MatchedResultUI] SWAPPED_VIEW home=" .. battle.HomeProfile .. " hud=" .. text(ui.playerCount) .. "/" .. text(ui.enemyCount))
        end
        if string.sub(_MatchFlowInput.Snapshot.state, 1, 7) == "RESULT_" then break end
        wait(0.1)
    end
    wait(0.3)
    local expected = battle:ResultForProfile(player.PlayerComponent.ProfileCode)
    assert(expected ~= "" and _MatchFlowInput.Snapshot.state == "RESULT_" .. expected, "result belongs to this player's actual battle side")
    assert(ui.OwnResult == expected and ui.result.Enable, "result window shows this player's result")
    assert(ui.resultWin.Enable == (expected == "WIN") and ui.resultLose.Enable == (expected == "LOSE") and ui.resultDraw.Enable == (expected == "DRAW"), "exactly one result entity")
    local own, enemy = counts()
    assert(string.find(text(ui.resultPlayerCount), tostring(own) .. " / ", 1, true) == 1, "own survivors on the result")
    assert(string.find(text(ui.resultEnemyCount), tostring(enemy) .. " / ", 1, true) == 1, "enemy survivors on the result")
    local panel = _MatchFlowInput.root:GetChildByName("BattleResult", false)
    assert(panel.Enable and _MatchFlowInput.action.Parent == panel, "return action lives on the result screen")
    assert(not _MatchFlowInput.root:GetChildByName("BattleMatch", false).Enable, "only one return action")
    assert(text(_MatchFlowInput.action) == "返回大廳" and _MatchFlowInput.action.ButtonComponent.Enable, "return button enabled")
    assert(ui.hud.Enable and text(ui.phaseText) == "戰鬥結束", "HUD names the finished phase")
    log("[VRF][MatchedResultUI] PASS own " .. expected .. " counts=" .. text(ui.resultPlayerCount) .. " vs " .. text(ui.resultEnemyCount) .. " swapped=" .. tostring(swapped) .. "; dispatching connected return button")
    _MatchFlowInput.action:SendEvent(ButtonClickEvent())
    wait(0.03)
    assert(text(_MatchFlowInput.action) == "返回中…" and not _MatchFlowInput.action.ButtonComponent.Enable, "sent return shows as pending")
    log("[VRF][MatchedResultUI] RETURN_PENDING status=" .. text(_MatchFlowInput.status))
    -- With _MatchFlow:ConfigureMakerTransferFaults(0, 1) armed in the match server, the first move fails.
    for attempt = 1, 100 do
        if text(_MatchFlowInput.action) == "重試返回" and _MatchFlowInput.action.ButtonComponent.Enable then break end
        wait(0.1)
    end
    assert(player.CurrentMapName == "matchprobe" and ui.result.Enable and text(_MatchFlowInput.action) == "重試返回", "failed return stays on the result with a retry")
    log("[VRF][MatchedResultUI] RETURN_FAILED msg=" .. _MatchFlowInput.Snapshot.reasonCode .. " status=" .. text(_MatchFlowInput.status))
    _MatchFlowInput.action:SendEvent(ButtonClickEvent())
    wait(0.03)
    assert(text(_MatchFlowInput.action) == "返回中…" and not _MatchFlowInput.action.ButtonComponent.Enable, "retry shows as pending")
    log("[VRF][MatchedResultUI] RETRY_PENDING status=" .. text(_MatchFlowInput.status))
end)
if not ok then log("[VRF][MatchedResultUI] FAIL " .. tostring(detail)) end
