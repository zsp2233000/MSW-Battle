-- client, one lobby player with an isolated saved active formation (same fixture as match_recovery_runtime_probe).
-- First arm server_main: _MatchFaults:ConfigureCancel(1, 1).
-- After this probe, reset _MatchFaults:ConfigureCancel(0, 0), restore storage keys and reload the original session.
-- ENTRY runs after the server race's ENTRY mode; PROGRESS watches its SEAL_FAILURE mode.
local MODE = 'FAILURE'
local m, l = _MatchFlowInput, _FormationLobby
local function await(predicate, tries)
    for _ = 1, tries or 150 do if predicate() then return true end wait(0.1) end
    return false
end
local ok, detail = pcall(function()
    if MODE == 'ENTRY' then
        assert(await(function() return m.Snapshot.reasonCode == 'ROOM_MOVE_FAILED' and not m.Snapshot.busy end), 'entry movement failed')
        assert(m.Snapshot.state == 'TRANSFER' and string.find(m.status.TextGUIRendererComponent.Text, '入場失敗', 1, true), 'entry failure reason visible')
        assert(m.action.Enable and m.action.ButtonComponent.Enable and m.action.TextGUIRendererComponent.Text == '停止入場'
            and not m:AllowsFormationActions(), 'Stop Entry usable; editing locked')
        -- A recovery that is running when the button is pressed answers with a status refresh, which re-enables the button; the player presses again.
        local clicks = 0
        for _ = 1, 5 do
            if m.action.Enable and m.action.ButtonComponent.Enable then
                clicks = clicks + 1
                m.action:SendEvent(ButtonClickEvent())
            end
            if await(function() return m:AllowsFormationActions() end, 40) then break end
        end
        assert(await(function() return m:AllowsFormationActions() end), 'visible abort restores confirmed lobby')
        log('[VRF][Cancel52Entry] PASS movement failure reason; visible abort; confirmed lobby restore clicks=' .. tostring(clicks))
        return
    elseif MODE == 'PROGRESS' then
        -- The commit is published as reason COMMITTING on the still-SAVING ticket; either spelling is the post-pairing commit.
        assert(await(function() return m.Snapshot.state == 'COMMITTING' or m.Snapshot.reasonCode == 'COMMITTING' end, 300), 'observed resumed commit')
        assert(m.Snapshot.reasonCode ~= 'CANCEL_FAILED' and not m.action.Enable, 'commit has no cancel action')
        log('[VRF][Cancel52Progress] PASS post-pairing commit hides cancellation')
        return
    end
    assert(await(function() return m:AllowsFormationActions() and _FormationEditSession:HasValidActive() end), 'valid lobby fixture')
    m.action:SendEvent(ButtonClickEvent())
    assert(await(function() return m.Snapshot.state == 'QUEUED' and not m.Snapshot.busy end), 'queued through the visible control')
    local summary, attempt = m.Snapshot.summary, m.Snapshot.attempt
    m.action:SendEvent(ButtonClickEvent())
    assert(not m:AllowsFormationActions(), 'cancellation request keeps editing locked')
    assert(await(function() return m.Snapshot.state == 'CANCELLING' and m.Snapshot.busy end), 'pending cancellation is distinct from confirmed completion')
    assert(not m.action.Enable, 'in-flight cancel has no button')
    assert(await(function() return m.Snapshot.reasonCode == 'CANCEL_FAILED' and not m.Snapshot.busy end), 'cancellation response failed')
    assert(m.Snapshot.state == 'QUEUED', 'failed cancellation retains the live queue state')
    assert(not m:AllowsFormationActions() and not l:Ui('Lobby/Edit').ButtonComponent.Enable, 'failure cannot unlock editing')
    assert(m.Snapshot.attempt == attempt and m.Snapshot.summary == summary, 'same attempt and fixed formation retained')
    assert(m.action.ButtonComponent.Enable, 'retry cancellation is usable')
    assert(m.action.Enable and m.action.TextGUIRendererComponent.Text == '取消配對', 'failure offers cancellation with the same label')
    m.action:SendEvent(ButtonClickEvent())
    assert(await(function() return m.Snapshot.state == 'CANCELLING' and m.Snapshot.busy end), 'retry in flight')
    assert(m.Snapshot.reasonCode == 'CANCELLING', 'retry in flight no longer reports the previous failure')
    assert(await(function() return m:AllowsFormationActions() end), 'confirmed retry unlocks editing')
    log('[VRF][Cancel52] PASS native-response failure; queue retained; retry confirmed; editing restored')
end)
if not ok then log('[VRF][Cancel52] FAIL ' .. tostring(detail)) end
