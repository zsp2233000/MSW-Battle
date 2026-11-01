-- client in matchprobe, with ConfigureMakerFaults(0, 1, 0) armed in that room after admission.
-- Tests the return-save failure at the settled result; battle HUD verification has a separate probe.
local function await(predicate)
    for _ = 1, 900 do if predicate() then return true end wait(0.1) end
    return false
end
local ok, detail = pcall(function()
    local player, m, ui = _UserService.LocalPlayer, _MatchProbeInput, _BattleUIController
    assert(player.CurrentMapName == 'matchprobe', 'admitted match room')
    assert(await(function()
        return string.sub(m.State, 1, 7) == 'RESULT_' and ui.result.Enable and isvalid(m.action)
            and m.action.EnabledInHierarchy and m.action.Parent == m.root:GetChildByName('BattleResult', false)
    end), 'natural battle result and return control ready')
    local battle = player.CurrentMap:GetComponent('script.BattleSession')
    assert(m.State == 'RESULT_' .. battle:ResultForProfile(player.PlayerComponent.ProfileCode), 'own result')
    assert(m.action.ButtonComponent.Enable and m.action.TextGUIRendererComponent.Text == '返回大廳', 'formal return control')
    m.action:SendEvent(ButtonClickEvent())
    assert(await(function() return m.Message == 'RETURN_SAVE_FAILED' and not m.Busy and m.action.ButtonComponent.Enable end), 'return save failure reported')
    assert(player.CurrentMapName == 'matchprobe' and ui.result.Enable and string.sub(m.State, 1, 7) == 'RESULT_', 'failed save retains the result and room')
    assert(m.action.TextGUIRendererComponent.Text == '重試返回'
        and string.find(m.status.TextGUIRendererComponent.Text, '返回資料儲存失敗', 1, true), 'reason and retry visible')
    m.action:SendEvent(ButtonClickEvent())
    log('[VRF][ReturnSave52] PASS failed save retains result; reason visible; retry dispatched')
end)
if not ok then log('[VRF][ReturnSave52] FAIL ' .. tostring(detail)) end
