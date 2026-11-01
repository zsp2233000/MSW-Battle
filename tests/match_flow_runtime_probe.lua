-- client, isolated FormationService AND FormationHandoff storage keys; only one participant queued.
-- Run QUEUE, then set ConfigureMakerFaults(0, 1, 0) on server_main and run CANCEL_FAILURE.
-- Reset faults to (0, 0, 0), then run CANCEL_RECOVER. No original player data is written.
local PHASE = 'QUEUE'
local l, m, s = _FormationLobby, _MatchProbeInput, _FormationEditSession
local function await(predicate, tries)
    for _ = 1, tries or 150 do if predicate() then return true end wait(0.1) end
    return false
end
local function click(path)
    local node = l:Ui(path)
    assert(node.EnabledInHierarchy and node.ButtonComponent.Enable, path .. ' is usable')
    node:SendEvent(ButtonClickEvent())
end
local ok, detail = pcall(function()
    assert(_UserService.LocalPlayer.CurrentMapName == 'formationlobby', 'lobby')
    if PHASE == 'PREPARE' then
        assert(await(function() return m:AllowsFormationActions() end), 'lobby confirmed')
        click('Lobby/Edit')
        assert(await(function() return _UserService.LocalPlayer.CurrentMapName == 'formationsim' and s:CanEdit() end), 'editor ready')
        local input = _UserService.LocalPlayer.CurrentMap:GetComponent('FormationMapInput')
        for slot = 1, 5 do
            if s.Snapshot.editSlot ~= slot then
                click('Editor/Slots/Slot' .. tostring(slot))
                assert(await(function() return s.Snapshot.editSlot == slot and s:CanEdit() end), 'viewed group acknowledged')
            end
            -- Keep the first group's prior discard/restore regression intact; fill the remaining groups through UI.
            if #s.Draft == 0 then
                click('Editor/Catalog/Monster1')
                input:HandleWorldClick(Vector3(-4 - slot * 0.3, slot - 3, 0))
                assert(s:IsDirty(), 'local formation changed')
                click('Editor/Save')
                assert(await(function() return not s:Busy() and not s:IsDirty() and s:Writable() end), 'single group saved')
            end
        end
        click('Editor/Slots/Slot3')
        assert(await(function() return s.Snapshot.editSlot == 3 and s:CanEdit() end), 'third group selected')
        click('Editor/Activate')
        assert(await(function() return s.Snapshot.saved.activeSlot == 3 and not s:Busy() end), 'third group activated explicitly')
        local before = s.Snapshot.saved.slots['3'].revision
        s.SelectedMonsterId = ''
        s.SelectedUnit = 1
        input:HandleWorldClick(Vector3(-7, 1, 0))
        assert(s:IsDirty(), 'active group changed locally')
        click('Editor/Save')
        assert(await(function() return not s:Busy() and not s:IsDirty() end), 'active group new version saved')
        assert(s.Snapshot.saved.slots['3'].revision == before + 1, 'next match gets updated active version')
        for slot = 1, 5 do assert(#s.Snapshot.saved.slots[tostring(slot)].units > 0, 'all five groups saved') end
        click('Editor/Back')
        assert(await(function() return _UserService.LocalPlayer.CurrentMapName == 'formationlobby' and m:AllowsFormationActions() end), 'back to lobby before matching')
        log('[VRF][Flow52] PREPARE PASS five saved groups; explicit active choice; updated active version; clean lobby return')
    elseif PHASE == 'QUEUE' then
        assert(await(function() return m:AllowsFormationActions() and s:HasValidActive() end), 'valid active team')
        local active = s.Snapshot.saved.activeSlot
        local preview = active == 5 and 1 or 5
        click('Lobby/Slots/Slot' .. tostring(preview))
        assert(await(function() return s.Snapshot.editSlot == preview end), 'preview selection acknowledged')
        assert(s.Snapshot.saved.activeSlot == active, 'preview never changes the active group')
        assert(m.action.TextGUIRendererComponent.Text == '開始配對', 'start is offered in lobby')
        m.action:SendEvent(ButtonClickEvent())
        assert(not m:AllowsFormationActions(), 'start immediately locks navigation before the reply')
        l:Travel('formationsim')
        l:SelectLobbySlot(active, true)
        assert(await(function() return m.State == 'QUEUED' and not m._T.pending end), 'official queue acknowledged')
        local summary = m.FixedSummary
        assert(string.find(summary, '第 ' .. tostring(active) .. ' 組', 1, true), 'summary uses active, not preview group')
        assert(not l:Ui('Lobby/Edit').ButtonComponent.Enable and not l:Ui('Lobby/Legacy').ButtonComponent.Enable, 'editor and POC disabled')
        assert(not s:CanEdit() and s:RequestSwitchSlot(active) == nil, 'no hidden editing path')
        -- Exercise authenticated old entry points too; the server must reject travel, selection and activation.
        _FormationService:RequestTravel('formationsim')
        _FormationService:RequestSelectSlot(active)
        _FormationService:RequestActivate(preview, s.Snapshot.saved.slots[tostring(preview)].revision)
        wait(1)
        assert(_UserService.LocalPlayer.CurrentMapName == 'formationlobby' and s.Snapshot.editSlot == preview, 'old RPC paths cannot enter or switch')
        assert(s.Snapshot.saved.activeSlot == active and m.FixedSummary == summary, 'active and fixed summary unchanged')
        -- Real time, not a synthetic countdown value: queue must remain open beyond sixty seconds.
        for _ = 1, 63 do wait(1) end
        assert(m.State == 'QUEUED' and m.FixedSummary == summary, 'queue does not expire at sixty seconds')
        assert(string.find(m.status.TextGUIRendererComponent.Text, '已等候', 1, true), 'elapsed wait is explicitly labelled')
        log('[VRF][Flow52] QUEUE PASS lobby-only; locked entry/RPCs; independent preview; fixed summary; real wait >60s')
    elseif PHASE == 'CANCEL_FAILURE' then
        assert(m.State == 'QUEUED', 'still queued')
        m.action:SendEvent(ButtonClickEvent())
        assert(not m:AllowsFormationActions(), 'cancel request keeps editing locked')
        assert(await(function() return m.Message == 'CANCEL_SAVE_FAILED' and not m._T.pending end), 'failed cancellation reported')
        assert(m.State == 'CANCELLED' and not m:AllowsFormationActions(), 'unconfirmed cancellation keeps editing locked')
        assert(not l:Ui('Lobby/Edit').ButtonComponent.Enable and m.action.ButtonComponent.Enable, 'only retry cancellation is usable')
        log('[VRF][Flow52] CANCEL_FAILURE PASS no early unlock')
    elseif PHASE == 'CANCEL_RECOVER' then
        m.action:SendEvent(ButtonClickEvent())
        assert(await(function() return m:AllowsFormationActions() end), 'confirmed cancellation unlocks editing')
        assert(await(function() return l:Ui('Lobby/Edit').ButtonComponent.Enable end), 'editor restored')
        assert(m.FixedSummary == '' and m.action.TextGUIRendererComponent.Text == '開始配對', 'old summary cleared')
        click('Lobby/Edit')
        assert(await(function() return _UserService.LocalPlayer.CurrentMapName == 'formationsim' and s:CanEdit() end), 'editor usable after cancellation')
        assert(not m.root.Enable, 'editor has no matchmaking screen')
        m:Click()
        _MatchProbe:RequestQueue(_UtilLogic:NewGuid())
        wait(0.6)
        assert(m.State == 'IDLE' and not m._T.pending, 'stale binding and server queue request rejected in editor')
        click('Editor/Back')
        assert(await(function() return _UserService.LocalPlayer.CurrentMapName == 'formationlobby' and m:AllowsFormationActions() end), 'clean return')
        log('[VRF][Flow52] CANCEL_RECOVER PASS confirmed unlock; no editor matchmaking; clean lobby return')
    end
end)
if not ok then log('[VRF][Flow52] FAIL ' .. PHASE .. ' ' .. tostring(detail)) end
