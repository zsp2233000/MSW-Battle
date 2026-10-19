-- Client. First configure server _FormationStorage:ConfigureMakerFaults(1, 1, 1).
local failures = 0
local function check(value, label) if not value then failures = failures + 1 log('[VRF][FormationFailure] FAIL ' .. label) end end
local function await(predicate) for index=1,100 do if predicate() then return true end wait(0.1) end return false end
local function click(path) _EntityService:GetEntityByPath('/ui/FormationGroup/'..path):SendEvent(ButtonClickEvent()) end
local l = _FormationLobby
local ok, detail = pcall(function()
    local revision = l.Snapshot.saved.revision
    local count = #l.Snapshot.draft
    _FormationService:RequestRetryLoad()
    check(await(function() return l.Snapshot.loadState == 'ERROR' end), 'read failure is explicit')
    check(l.Snapshot.saved.revision == revision and #l.Snapshot.draft == count, 'read failure retains confirmed data and draft')
    click('Retry')
    check(await(function() return l.Snapshot.loadState == 'READY' end), 'read retry succeeds')
    _FormationService:RequestTravel('formationsim')
    await(function() return _UserService.LocalPlayer.CurrentMapName == 'formationsim' end)
    local version = l.Snapshot.draftVersion
    click('Editor/Units/Unit1')
    click('Editor/Board/Cell2_4')
    check(await(function() return l.Snapshot.draftVersion > version end), 'draft edited through connected controls')
    click('Editor/Save')
    check(await(function() return l.Snapshot.saveState == 'SAVING' end), 'pending write visible')
    check(await(function() return l.Snapshot.saveState == 'FAILED' end), 'write failure visible')
    check(l.Snapshot.saved.revision == revision and l.Snapshot.draft[1].y == -1, 'failed write preserves old revision and retry draft')
    click('Retry')
    check(await(function() return l.Snapshot.loadState == 'READY' end), 'ambiguous failed write reconciles before retry')
    click('Editor/Save')
    check(await(function() return l.Snapshot.saveState == 'SAVED' end), 'retry receives durable confirmation')
end)
if not ok then failures=failures+1 log('[VRF][FormationFailure] exception='..tostring(detail)) end
log(failures==0 and '[VRF][FormationFailure] PASS' or '[VRF][FormationFailure] FAILURES='..failures)
