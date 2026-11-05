-- client, dispatched while the battle runs: moving rooms resets the client context (#51). Reads the
-- player-visible HUD and result through the formal UI, waits for the natural result, optionally for a
-- server-side identity swap, then clicks return. The context ends on return, so log before dispatch.
local ok, detail = pcall(function()
    local player = _UserService.LocalPlayer
    assert(player.CurrentMapName == "matchprobe", "client is in the match")
    local battle = player.CurrentMap:GetComponent("script.BattleSession")
    local ui = _BattleUIController
    local text = function(entity) return entity.TextGUIRendererComponent.Text end
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
