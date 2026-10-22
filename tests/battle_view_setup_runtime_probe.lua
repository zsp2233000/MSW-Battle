-- Run in server_main with battleviewprototype open in Maker. Change away to true for the second real client view.
local away = false
local map = _EntityService:GetEntityByPath('/maps/battleviewprototype')
assert(isvalid(map), 'open battleviewprototype in Maker before Play')
local session = map:GetComponent('script.BattleSession')
local view = map:GetComponent('script.BattleViewPrototype')
assert(isvalid(session) and isvalid(view) and view:IsPrototype())
local user = _UserService.UserEntities.Values[1]
assert(isvalid(user), 'a real local client is required')
_TeleportService:TeleportToMapPosition(user, Vector3(-5, 3, 0), 'battleviewprototype')
local id = user.PlayerComponent.UserId
view.HomeUserId = away and 'prototype-opponent' or id
view.AwayUserId = away and id or 'prototype-opponent'
session.HomeProfile = away and 'prototype-opponent' or user.PlayerComponent.ProfileCode
session.AwayProfile = away and user.PlayerComponent.ProfileCode or 'prototype-opponent'
assert(session:BeginManualSimulation(), 'could not acquire initialization clock')
local ok, failure = pcall(function()
    assert(session:PrepareBattleForTest({
        { monsterId = 'monster_tank', name = 'HomeTank', position = Vector3(-3, 0.5, 0) },
        { monsterId = 'monster_warrior', name = 'HomeWarrior', position = Vector3(-4, -1.5, 0) }
    }, {
        { monsterId = 'monster_warrior', name = 'AwayWarrior', position = Vector3(2, 0, 0) },
        { monsterId = 'monster_shooter', name = 'AwayShooter', position = Vector3(3, -2, 0) }
    }), 'catalog scenario initialization failed')
end)
session:EndManualSimulation()
assert(ok, tostring(failure))
assert(session.Phase == 'DEPLOYMENT')
log('[VRF][BattleView] SETUP_PASS local='..(away and 'AWAY' or 'HOME')..' snapshot='..session:GetDebugSnapshot())
-- Capture opening after the client probe, then start natural combat with session:TryStartBattle().
