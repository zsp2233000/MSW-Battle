-- Server context: exercise the shared placement rules through their public interface.
local session = _EntityService:GetEntityByPath('/maps/template'):GetComponent('BattleSession')
local deployed = false
local ok, detail = pcall(function()
    local elapsed = 0
    while elapsed < 5 and (not isvalid(_FormationService:GetCatalog()) or session.Phase ~= 'DEPLOYMENT' or session.EnemyAlive ~= 6) do
        wait(0.1)
        elapsed = elapsed + 0.1
    end
    local layout = _FormationMapLayout
    assert(not layout:IsTooClose(-2, 0, -2.3, 0), '0.3 separation including floating-point rounding is accepted')
    assert(not layout:IsTooClose(0, 0, 0.299999, 0), 'float32 boundary tolerance is shared')
    assert(layout:IsTooClose(0, 0, 0.299, 0), 'meaningfully shorter spacing is rejected')
    assert(layout:IsTooClose(0, 0, 0.2, 0.2), 'diagonal overlap is rejected')
    assert(not layout:IsTooClose(0, 0, 0.18, 0.24), 'diagonal minimum spacing is accepted')
    assert(layout:CanDeploy(0.49, 0) and not layout:CanDeploy(0.5, 0), 'left-side boundary is shared')
    assert(not layout:CanDeploy(math.huge, 0) and not layout:CanDeploy(0/0, 0), 'non-finite coordinates are rejected')
    assert(not layout:IsWalkable(15, 0) and not layout:IsWalkableOn(nil, -2, 0), 'bounds and missing terrain fail closed')

    local catalog = _FormationService:GetCatalog()
    assert(isvalid(catalog), 'template catalog is available from the lobby')
    local units = {{monsterId='monster_tank', x=-2, y=0}, {monsterId='monster_tank', x=-2.3, y=0}}
    local clean = _FormationSchema:ValidateUnits(units, catalog, false)
    assert(clean ~= nil and clean[2].x == -2.3, 'saving preserves exact minimum-spacing coordinates')
    assert(_FormationSchema:ValidateUnits({{monsterId='monster_tank',x=-2,y=0},{monsterId='monster_tank',x=-2.15,y=0}}, catalog, false) == nil, 'saving rejects overlapping units')
    local doc = _FormationSchema:EmptyDocument()
    doc.slots['1'].units, doc.activeSlot = clean, 1
    local restored = _FormationSchema:ValidateDocument(_HttpService:JSONDecode(_FormationSchema:EncodeDocument(doc)), catalog)
    assert(restored ~= nil and restored.schema == 2 and restored.slots['1'].units[2].x == -2.3, 'existing storage format round-trips without coordinate changes')

    local home = layout:BattlePosition(-2.25, 0.25, false)
    local away = layout:BattlePosition(-2.25, 0.25, true)
    assert(home.x == -2.25 and away.x == 3.25 and away.y == 0.25 and away.z == 0, 'battle entry preserves fractional positions and mirrors at x=0.5')
    assert(layout:MirrorX(away.x) == home.x, 'away viewing restores the original player-relative position')
    assert(layout:BattlePosition(0.5, 0, true) == nil, 'invalid saved coordinates cannot enter either battle side')

    assert(session.Phase == 'DEPLOYMENT' and session.PlayerAlive == 0 and session.EnemyAlive == 6, 'template roster is ready')
    deployed = true
    assert(session:TryDeployMonster('monster_tank', Vector3(-2, 0, 0)), 'first unit deploys')
    assert(session:TryDeployMonster('monster_tank', Vector3(-2.3, 0, 0)), 'deployment accepts the same minimum-spacing formation as saving')
    assert(not session:TryDeployMonster('monster_tank', Vector3(-2.15, 0, 0)), 'deployment rejects the same overlapping formation as saving')
    assert(session.PlayerAlive == 2 and session.EnemyAlive == 6, 'rejected deployment leaves the roster intact')
end)
if deployed then
    session:TryRemoveDeployedUnitAt(Vector3(-2, 0, 0))
    session:TryRemoveDeployedUnitAt(Vector3(-2.3, 0, 0))
end
log(ok and '[VRF][FormationPlacement] PASS' or '[VRF][FormationPlacement] FAIL ' .. tostring(detail))
