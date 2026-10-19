-- Server context. Native storage boundary, using a disposable key in the test player's private storage.
local failures=0
local function check(value,label) if not value then failures=failures+1 log('[VRF][FormationStorage] FAIL '..label) end end
local function await(predicate) for index=1,100 do if predicate() then return true end wait(0.1) end return false end
local player=_UserService.UserEntities.Values[1]
local profile=player.PlayerComponent.ProfileCode
local storage=_DataStorageService:GetUserDataStorage(profile)
local key='FormationBootstrap28_'..tostring(_UtilLogic.ElapsedSeconds)
local ok,detail=pcall(function()
    local catalog=_FormationService:GetCatalog()
    check(_FormationSchema:ValidateUnits({{monsterId='monster_tank',x=0/0,y=0}},catalog,false)==nil,'NaN rejected')
    check(_FormationSchema:ValidateUnits({{monsterId='monster_tank',x=math.huge,y=0}},catalog,false)==nil,'infinity rejected')
    local clean=_FormationSchema:ValidateUnits({{monsterId='monster_tank',x=0,y=0,MaxHp=99999,AttackDamage=99999}},catalog,false)
    check(clean~=nil and clean[1].MaxHp==nil and clean[1].AttackDamage==nil,'client abilities discarded')
    local encoded=_FormationSchema:EncodeDocument(_FormationSchema:EmptyDocument())
    check(_FormationSchema:ValidateDocument(_HttpService:JSONDecode(encoded),catalog)~=nil,'five empty slots round-trip')
    local oldCode=nil
    local newCode=nil
    _FormationStorage:ConfigureMakerFaults(0,0,2)
    _FormationStorage:Write(profile,key,'','older',function(code) oldCode=code end)
    _FormationStorage:ConfigureMakerFaults(0,0,0)
    _FormationStorage:Write(profile,key,'','newer',function(code) newCode=code end)
    check(await(function() return newCode~=nil and oldCode~=nil end),'both delayed creations complete')
    check(newCode==0 and oldCode~=0,'late stale creation rejected')
    local code,raw=storage:GetAndWait(key)
    check(code==0 and raw=='newer','late first write cannot overwrite newer successful creation')
    local staleCode=nil
    _FormationStorage:Write(profile,key,'older','stale-overwrite',function(value) staleCode=value end)
    check(await(function() return staleCode~=nil end) and staleCode~=0,'native compare-and-update rejects stale writer')
    code,raw=storage:GetAndWait(key)
    check(code==0 and raw=='newer','stale CAS leaves persisted version untouched')
    _FormationStorage:ConfigureMakerGuardFailures(1)
    local cleanupFailureCode=nil
    _FormationStorage:Write(profile,key,'newer','after-cleanup-fault',function(value) cleanupFailureCode=value end)
    check(await(function() return cleanupFailureCode~=nil end) and cleanupFailureCode==0,'durable success survives cleanup fault')
    local retryCode=nil
    _FormationStorage:Write(profile,key,'after-cleanup-fault','recovered',function(value) retryCode=value end)
    check(await(function() return retryCode~=nil end) and retryCode==0,'later write retries failed ownership cleanup')
    code,raw=storage:GetAndWait(key)
    check(code==0 and raw=='recovered','guard cleanup failure cannot permanently block saving')
end)
_FormationStorage:ConfigureMakerFaults(0,0,0)
_FormationStorage:ConfigureMakerGuardFailures(0)
local cleanup=storage:DeleteAndWait(key)
check(cleanup==0,'disposable probe key removed')
if not ok then failures=failures+1 log('[VRF][FormationStorage] exception='..tostring(detail)) end
log(failures==0 and '[VRF][FormationStorage] PASS' or '[VRF][FormationStorage] FAILURES='..failures)
