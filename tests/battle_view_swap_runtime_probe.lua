-- Run in server_main after the HOME opening probe/screenshot, on the very same scene generation.
local map = _EntityService:GetEntityByPath('/maps/battleviewprototype')
local session = map:GetComponent('script.BattleSession')
local view = map:GetComponent('script.BattleViewPrototype')
assert(session.Phase == 'DEPLOYMENT', 'swap at the stable opening')
local before = session:GetUnitSnapshots()
view.HomeUserId, view.AwayUserId = view.AwayUserId, view.HomeUserId
session.HomeProfile, session.AwayProfile = session.AwayProfile, session.HomeProfile
wait(1)
assert(session:GetUnitSnapshots() == before, 'presentation identity modified authority')
log('[VRF][BattleView] AUTHORITY_UNCHANGED generation='..tostring(session.SessionGeneration))
