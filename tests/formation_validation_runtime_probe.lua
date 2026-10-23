-- Client. Reject malicious edits at the authenticated public RPC boundary.
local failures=0
local function check(value,label) if not value then failures=failures+1 log('[VRF][FormationValidation] FAIL '..label) end end
local l=_FormationLobby
local function reject(units,label)
    local version=l.Snapshot.draftVersion
    local sequence=l.ObservedSequence
    _FormationService:RequestDraft(units,version,1)
    for index=1,50 do if l.ObservedSequence>sequence then break end wait(0.1) end
    check(l.ObservedSequence>sequence and l.Snapshot.draftVersion==version,label)
end
local ok,detail=pcall(function()
    reject({{monsterId='monster_tank',x=-1,y=2}},'collidable terrain')
    reject({{monsterId='unknown',x=0,y=0}},'unknown ID')
    reject({{monsterId='monster_tank',x=100,y=0}},'outside reference terrain bounds')
    reject({{monsterId='monster_tank',x='0',y=0}},'numeric string')
    reject({{monsterId='monster_tank',x=0,y=0},{monsterId='monster_tank',x=0,y=0}},'overlapping units')
    local seven={}
    for index=1,7 do seven[index]={monsterId='monster_tank',x=index-4,y=0} end
    reject(seven,'seventh unit')
    reject({[2]={monsterId='monster_tank',x=0,y=0}},'sparse array')
    local seq=l.ObservedSequence
    local version=l.Snapshot.draftVersion
    _FormationService:RequestDraft({{monsterId='monster_tank',x=0,y=0}},version-1,1)
    for index=1,50 do if l.ObservedSequence>seq then break end wait(0.1) end
    check(l.ObservedSequence>seq and l.Snapshot.draftVersion==version,'stale draft command rejected')
end)
if not ok then failures=failures+1 log('[VRF][FormationValidation] exception='..tostring(detail)) end
log(failures==0 and '[VRF][FormationValidation] PASS' or '[VRF][FormationValidation] FAILURES='..failures)
