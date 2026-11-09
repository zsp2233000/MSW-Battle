-- server_main, fresh Maker Play. Move the local player to template before running this fixture.
-- Result UI fixture only: publishes controlled outcomes without writing player storage.
assert(Environment:IsMakerPlay(), "Maker-only fixture")
local map = _EntityService:GetEntityByPath("/maps/template")
local session = map:GetComponent("script.BattleSession")
assert(session.Phase == "DEPLOYMENT" and session.PlayerAlive == 0, "fresh POC deployment required")
for index = 1, 6 do
    assert(session:TryDeployMonster("monster_tank", Vector3(-5 + (index - 1) * 0.6, 1, 0)))
end
local previousLast = map:GetChildByName("M1_Player_6", false):GetComponent("script.BattleUnit").DeploymentOrder
assert(session:TryRemoveDeployedUnitAt(Vector3(-5, 1, 0)))
assert(session:TryDeployMonster("monster_tank", Vector3(-5, 1, 0)))
local replacement = map:GetChildByName("M1_Player_7", false):GetComponent("script.BattleUnit")
assert(replacement.DeploymentOrder > previousLast, "replacement follows every surviving deployment")
local seen = {}
for _, unit in ipairs(map:GetChildComponentsByTypeName("script.BattleUnit", false)) do
    assert(not seen[unit.DeploymentOrder], "deployment order is unique after removal and replacement")
    seen[unit.DeploymentOrder] = true
    if unit.Faction == "PLAYER" then
        unit.Hp = unit.DeploymentOrder * 10
    else
        unit.Hp = 0
        unit.IsDead = true
    end
end
session.PlayerAlive = 6
session.EnemyAlive = 0
session.InitialPlayerAlive = 6
session.InitialEnemyAlive = 6
session.Result = "WIN"
session.Phase = "RESULT"
log("[VRF][ResultCardsFixture] PASS remove-replace unique order; six survivors ready")
