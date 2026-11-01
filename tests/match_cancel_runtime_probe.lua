-- client, one lobby player with an isolated saved active formation (same fixture as match_recovery_runtime_probe).
-- First arm server_main: _MatchProbe:ConfigureMakerCancelFaults(1, 1).
-- After this probe, reset ConfigureMakerCancelFaults(0, 0), restore storage keys and reload the original session.
-- ENTRY runs after the server race's ENTRY mode; PROGRESS watches its SEAL_FAILURE mode.
local MODE = 'FAILURE'
local m, l = _MatchProbeInput, _FormationLobby
local function await(predicate, tries)
    for _ = 1, tries or 150 do if predicate() then return true end wait(0.1) end
    return false
end
local ok, detail = pcall(function()
    if MODE == 'ENTRY' then
        assert(await(function() return m.Message == 'ROOM_MOVE ok=false' and not m.Busy end), 'entry movement failed')
        assert(m.State == 'TRANSFER' and string.find(m.status.TextGUIRendererComponent.Text, '進入戰場失敗', 1, true), 'entry failure reason visible')
        assert(m.action.ButtonComponent.Enable and not m:AllowsFormationActions(), 'entry abort usable; editing locked')
        m.action:SendEvent(ButtonClickEvent())
        assert(await(function() return m:AllowsFormationActions() end), 'visible abort restores confirmed lobby')
        log('[VRF][Cancel52Entry] PASS movement failure reason; visible abort; confirmed lobby restore')
        return
    elseif MODE == 'PROGRESS' then
        assert(await(function() return m.State == 'COMMITTING' end, 300), 'observed resumed commit')
        assert(m.Message ~= 'CANCEL_FAILED', 'resumed match clears obsolete cancellation failure')
        log('[VRF][Cancel52Progress] PASS resumed commit clears cancellation error')
        return
    end
    assert(await(function() return m:AllowsFormationActions() and _FormationEditSession:HasValidActive() end), 'valid lobby fixture')
    m.action:SendEvent(ButtonClickEvent())
    assert(await(function() return m.State == 'QUEUED' and not m.Busy end), 'queued through the visible control')
    local summary, attempt = m.FixedSummary, m.Attempt
    m.action:SendEvent(ButtonClickEvent())
    assert(not m:AllowsFormationActions(), 'cancellation request keeps editing locked')
    assert(await(function() return m.State == 'CANCELLING' and m.Busy end), 'pending cancellation is distinct from confirmed completion')
    assert(await(function() return m.Message == 'CANCEL_FAILED' and not m.Busy end), 'cancellation response failed')
    assert(m.State == 'QUEUED', 'failed cancellation retains the live queue state')
    assert(not m:AllowsFormationActions() and not l:Ui('Lobby/Edit').ButtonComponent.Enable, 'failure cannot unlock editing')
    assert(m.Attempt == attempt and m.FixedSummary == summary, 'same attempt and fixed formation retained')
    assert(m.action.ButtonComponent.Enable, 'retry cancellation is usable')
    assert(m.action.TextGUIRendererComponent.Text == '重試取消', 'failure offers an explicit retry')
    m.action:SendEvent(ButtonClickEvent())
    assert(await(function() return m.State == 'CANCELLING' and m.Busy end), 'retry in flight')
    assert(m.Message == 'CANCELLING', 'retry in flight no longer reports the previous failure')
    assert(await(function() return m:AllowsFormationActions() end), 'confirmed retry unlocks editing')
    log('[VRF][Cancel52] PASS native-response failure; queue retained; retry confirmed; editing restored')
end)
if not ok then log('[VRF][Cancel52] FAIL ' .. tostring(detail)) end
