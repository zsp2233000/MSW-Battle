-- Server context: public deployment regression using current authored bounds.
local failures = 0
local function check(value, label)
    if not value then failures = failures + 1 log('[VRF][FormationPOC] FAIL ' .. label) end
end
local ok, detail = pcall(function()
    local map = _EntityService:GetEntityByPath('/maps/map01')
    local session = map:GetComponent('BattleSession')
    check(session.Phase == 'DEPLOYMENT' and session.PlayerAlive == 0 and session.EnemyAlive == 6, 'production roster starts ready')
    check(not session:TryStartBattle(), 'empty formation cannot start')
    check(not session:TryDeployMonster('missing_monster', Vector3(-4.4,1,0)), 'unknown monster rejected')
    local bounds = _FormationMapLayout:Bounds()
    check(not session:TryDeployMonster('monster_tank', Vector3(bounds.minX-0.01,0,0)), 'outside authored X bound rejected')
    check(not session:TryDeployMonster('monster_tank', Vector3(-4.4,bounds.maxY+0.01,0)), 'outside authored Y bound rejected')
    local catalog = _FormationService:GetCatalog()
    for _, x in ipairs({0, 0.25, 0.49, 0.5, 0.51}) do
        local units = {{monsterId='monster_tank',x=x,y=0}}
        local valid = _FormationSchema:ValidateUnits(units, catalog, false) ~= nil
        local deployed = session:TryDeployMonster('monster_tank', Vector3(x,0,0))
        check(valid == (x < 0.5) and deployed == valid, 'POC and saved formation share center boundary '..x)
        if deployed then check(session:TryRemoveDeployedUnitAt(Vector3(x,0,0)), 'boundary fixture removed') end
    end
    check(session:TryDeployMonster('monster_tank', Vector3(-4.4,1,0)), 'formal monster deployed')
    check(not session:TryDeployMonster('monster_tank', Vector3(-4.4+session.DeploymentMinDistance/2,1,0)), 'inside authored minimum separation rejected')
    check(session:TryDeployMonster('monster_tank', Vector3(-4.4,0,0)), 'duplicate monster deployed')
    check(session.PlayerAlive == 2, 'two deployments registered once')
    check(session:TryRemoveDeployedUnitAt(Vector3(-4.4,1,0)), 'first formal removal accepted')
    check(session:TryRemoveDeployedUnitAt(Vector3(-4.4,0,0)), 'second formal removal accepted')
    check(session.PlayerAlive == 0 and session.EnemyAlive == 6, 'removal restores initial roster')
    for count=1,6 do check(session:CanStartBattleWithPlayerCount(count), 'valid player count '..count) end
    check(not session:CanStartBattleWithPlayerCount(7), 'capacity gate retained')
end)
if not ok then failures=failures+1 log('[VRF][FormationPOC] exception='..tostring(detail)) end
log(failures==0 and '[VRF][FormationPOC] PASS' or '[VRF][FormationPOC] FAILURES='..failures)
