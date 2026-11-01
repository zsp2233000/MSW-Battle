-- Client, fresh Play with an isolated FormationService.StorageKey (see editor_save_flow_runtime_probe.lua).
-- Edit MODE/PHASE on the next line, and set the matching storage acknowledgement fault in server_main first:
--   FAIL   : _FormationStorage:ConfigureMakerSaveResponse('FAIL', 0)     explicit failure
--   SILENT : _FormationStorage:ConfigureMakerSaveResponse('SILENT', 0)   never answers, so the 5 s watchdog fires
--   LATE   : _FormationStorage:ConfigureMakerSaveResponse('LATE', 9)     commits, but answers after the watchdog
-- PHASE 1 injects the fault. Reset the fault with ConfigureMakerSaveResponse('', 0) before PHASE 2 (recovery; FAIL and SILENT).
local MODE, PHASE = 'FAIL', 1
local l = _FormationLobby
local function await(predicate, tries)
    for _ = 1, tries or 120 do if predicate() then return true end wait(0.1) end
    return false
end
local function node(path) return l:Ui(path) end
local function enabled(path) return node(path).ButtonComponent.Enable end
local function label(path) return node(path).TextGUIRendererComponent.Text end
local function has(text, part) return string.find(text, part, 1, true) ~= nil end
local function click(path)
    if not enabled(path) then return false end
    node(path):SendEvent(ButtonClickEvent())
    return true
end
local function dialogOpen() return node('ExitConfirm').Enable end
local function map() return _UserService.LocalPlayer.CurrentMapName end
local function inEditor() return map() == 'formationsim' and node('Editor').EnabledInHierarchy and _FormationEditSession.DraftSlot == _FormationEditSession.Snapshot.editSlot and _MatchProbeInput:AllowsFormationActions() end
local function resultIs(status) return _FormationEditSession.Snapshot.result ~= nil and _FormationEditSession.Snapshot.result.status == status end

local ok, detail = pcall(function()
    if PHASE == 1 then
        if dialogOpen() then l:Run(_FormationEditSession:ContinueEditing()) end
        _FormationService:RequestRetryLoad()
        assert(await(function() return _FormationEditSession.Snapshot.loadState == 'NEW' end), 'isolated new-player fixture')
        assert(click('Lobby/Edit'), 'edit button')
        assert(await(inEditor), 'editor entered')
        wait(0.4)
        local input = _UserService.LocalPlayer.CurrentMap:GetComponent('FormationMapInput')
        click('Editor/Catalog/Monster1')
        input:HandleWorldClick(Vector3(-5, 0, 0))
        assert(#_FormationEditSession.Draft == 1 and _FormationEditSession:IsDirty() and enabled('Editor/Save'), 'a valid change is ready to save')
        local before = #_FormationEditSession.Snapshot.saved.slots['1'].units

        if MODE == 'FAIL' then
            click('Editor/Save')
            assert(await(function() return resultIs('FAILED') end, 80), 'explicit failure reported')
            assert(map() == 'formationsim' and #_FormationEditSession.Draft == 1 and _FormationEditSession:IsDirty(), 'content and marker kept, stayed in the group')
            assert(#_FormationEditSession.Snapshot.saved.slots['1'].units == before, 'saved content untouched')
            assert(not enabled('Editor/Save') and has(_FormationEditSession:SaveBlockReason(), '重新讀取'), 'save disabled with a readable reason')
            assert(await(function() return has(label('EditorControls/Retry'), '重新讀取') and node('EditorControls/Retry').EnabledInHierarchy end), 'manual retry is offered')
            assert(not _FormationEditSession:Unconfirmed(), 'an explicit failure is not an unconfirmed write')
            wait(2)
            assert(_FormationEditSession.Snapshot.result.status == 'FAILED' and not _FormationEditSession.Snapshot.pending, 'no automatic resend')
            log('[VRF][Save50F] FAIL-mode phase 1 ok')

        elseif MODE == 'SILENT' then
            click('Editor/Save')
            assert(await(function() return resultIs('UNCONFIRMED') end, 150), 'timeout reported as unconfirmed')
            assert(_FormationEditSession:Unconfirmed() and _FormationEditSession:IsDirty() and #_FormationEditSession.Draft == 1, 'content kept while unconfirmed')
            assert(not enabled('Editor/Save') and has(_FormationEditSession:SaveBlockReason(), '確認結果'), 'writes disabled, reason names the confirm action')
            assert(has(label('EditorControls/Retry'), '確認結果'), 'the confirm-result action is offered')
            click('Editor/Back')
            assert(map() == 'formationsim' and not dialogOpen(), 'cannot leave before the result is confirmed')
            click('Editor/Slots/Slot2')
            assert(_FormationEditSession.Snapshot.editSlot == 1 and not dialogOpen(), 'cannot switch before the result is confirmed')
            log('[VRF][Save50F] SILENT-mode phase 1 ok')

        elseif MODE == 'LATE' then
            click('Editor/Back')
            assert(dialogOpen() and _FormationEditSession.ConfirmKind == 'RETURN', 'leave asks')
            click('ExitConfirm/Window/SaveAndReturn')
            assert(label('ExitConfirm/Window/Title') == '儲存中…', 'waiting is shown')
            assert(not enabled('ExitConfirm/Window/SaveAndReturn') and not enabled('ExitConfirm/Window/ReturnWithoutSave')
                and not enabled('ExitConfirm/Window/ContinueEditing'), 'every choice is paused while waiting')
            assert(not enabled('Editor/Save'), 'saving is paused')
            -- The group buttons stay drawn as usable while waiting; the click itself is ignored.
            click('Editor/Slots/Slot2')
            assert(_FormationEditSession.Snapshot.editSlot == 1 and _FormationEditSession.ConfirmKind == 'RETURN', 'switching is paused')
            assert(await(function() return resultIs('UNCONFIRMED') end, 150), 'watchdog fires before the late reply')
            assert(map() == 'formationsim' and not dialogOpen(), 'the aborted return did not run')
            -- The commit lands and is acknowledged late; it must never run the abandoned return.
            assert(await(function() return _FormationEditSession.Snapshot.result ~= nil and _FormationEditSession.Snapshot.result.status == 'OK' and not _FormationEditSession.Snapshot.pending end, 200), 'late acknowledgement accepted')
            wait(2)
            assert(map() == 'formationsim', 'the late reply did not travel')
            assert(#_FormationEditSession.Snapshot.saved.slots['1'].units == 1 and not _FormationEditSession:IsDirty() and not _FormationEditSession:IsDirty(), 'late success clears the marker by content')
            log('[VRF][Save50F] LATE-mode ok')
        end

    elseif PHASE == 2 then
        -- Recovery after the fault was reset: read the durable content again, then save by hand.
        assert(map() == 'formationsim' and _FormationEditSession:IsDirty(), 'still in the group with unsaved content')
        if _FormationEditSession.Snapshot.loadState == 'CONFLICT' or _FormationEditSession:Unconfirmed() then
            assert(click('EditorControls/Retry'), 'the retry/confirm action is available')
        end
        -- A never-written account reads back as NEW, an existing one as READY; both accept commands.
        assert(await(function() return _FormationEditSession:Writable() and not _FormationEditSession.Snapshot.pending end, 120), 'durable content read back')
        assert(not _FormationEditSession:Unconfirmed() and _FormationEditSession:IsDirty() and #_FormationEditSession.Draft == 1, 'content still kept after the read')
        assert(enabled('Editor/Save'), 'saving is possible again')
        click('Editor/Save')
        assert(await(function() return #_FormationEditSession.Snapshot.saved.slots['1'].units == 1 and not _FormationEditSession.Snapshot.pending end, 120), 'manual retry saved')
        assert(not _FormationEditSession:IsDirty() and not _FormationEditSession:IsDirty(), 'marker cleared only after confirmed success')
        click('Editor/Back')
        assert(await(function() return map() == 'formationlobby' end), 'a clean return works')
        log('[VRF][Save50F] recovery ok')
    end
end)
log(ok and ('[VRF][Save50F] PASS ' .. MODE .. ' phase ' .. tostring(PHASE)) or ('[VRF][Save50F] FAIL ' .. MODE .. ' phase ' .. tostring(PHASE) .. ' ' .. tostring(detail)))
