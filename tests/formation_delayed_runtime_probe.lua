-- Client. First configure server _FormationStorage:ConfigureMakerFaults(0, 0, 2).
local failures = 0
local function check(value, label) if not value then failures=failures+1 log('[VRF][FormationDelay] FAIL '..label) end end
local function await(predicate) for index=1,100 do if predicate() then return true end wait(0.1) end return false end
local function click(path) _EntityService:GetEntityByPath('/ui/FormationGroup/'..path):SendEvent(ButtonClickEvent()) end
local l=_FormationLobby
local ok,detail=pcall(function()
    local version=l.Snapshot.draftVersion
    click('Editor/Units/Unit1')
    _UserService.LocalPlayer.CurrentMap:GetComponent('FormationMapInput'):HandleWorldClick(Vector3(-5.25, -0.35, 0))
    await(function() return l.Snapshot.draftVersion>version end)
    local savingVersion=l.Snapshot.draftVersion
    local oldRevision=l.Snapshot.saved.revision
    click('Editor/Save')
    check(await(function() return l.Snapshot.pending end),'write in flight')
    _UserService.LocalPlayer.CurrentMap:GetComponent('FormationMapInput'):HandleWorldClick(Vector3(-5.25, 0.65, 0))
    check(await(function() return l.Snapshot.draftVersion>savingVersion end),'edit during pending write accepted')
    _FormationService:RequestSave(l.Snapshot.draftVersion)
    check(await(function() return not l.Snapshot.pending end),'old write completes')
    check(l.Snapshot.saveState=='UNSAVED' and l.Snapshot.savedDraftVersion==savingVersion,'old success cannot mark newer draft saved')
    check(l.Snapshot.saved.revision==oldRevision+1 and math.abs(l.Snapshot.saved.slots['1'].units[1].y + 0.35)<0.001 and math.abs(l.Snapshot.draft[1].y-0.65)<0.001,'old reply corresponds exactly to captured version')
    click('Editor/Save')
    check(await(function() return l.Snapshot.saveState=='SAVED' end),'new version separately saved')
    check(l.Snapshot.saved.revision==oldRevision+2 and math.abs(l.Snapshot.saved.slots['1'].units[1].y-0.65)<0.001,'delayed write never replaces newer confirmed version')
end)
if not ok then failures=failures+1 log('[VRF][FormationDelay] exception='..tostring(detail)) end
log(failures==0 and '[VRF][FormationDelay] PASS' or '[VRF][FormationDelay] FAILURES='..failures)
