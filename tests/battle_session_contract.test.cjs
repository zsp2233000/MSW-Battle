const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const root = path.resolve(__dirname, "..");
const { MapBuilder } = require(path.join(root, ".agents/skills/msw-general/scripts/map/msw_map_builder.cjs"));
const { ModelBuilder } = require(path.join(root, ".agents/skills/msw-general/scripts/model/msw_model_builder.cjs"));

function read(relativePath) {
  return fs.readFileSync(path.join(root, relativePath), "utf8");
}

test("M1 map keeps RectTile and exposes the session boundary", () => {
  const map = MapBuilder.read(path.join(root, "map/map01.map"));
  assert.equal(map.getMapInfo().TileMapMode, 1);
  const rootEntity = map.listEntities().find((entity) => entity.path === "/maps/map01");
  assert.ok(rootEntity);
  assert.match(rootEntity.componentNames, /script\.BattleSession/);
  assert.match(rootEntity.componentNames, /script\.BattleDeploymentInput/);
});

test("M1 unit model has the RectTile movement contract", () => {
  const snapshot = ModelBuilder.snapshot(path.join(root, "RootDesk/MyDesk/Models/Monsters/BattleUnit.model"));
  const requiredComponents = [
    "MOD.Core.TransformComponent",
    "MOD.Core.SpriteRendererComponent",
    "MOD.Core.KinematicbodyComponent",
    "MOD.Core.MovementComponent",
    "MOD.Core.StateComponent",
    "MOD.Core.HitComponent",
  ];
  for (const component of requiredComponents) assert.ok(snapshot.components.includes(component), `missing ${component}`);
  const values = new Map(snapshot.values.map((value) => [`${value.target_type}.${value.name}`, value.value]));
  assert.equal(values.get("MOD.Core.MovementComponent.InputSpeed"), 2.4);
  assert.equal(values.get("MOD.Core.KinematicbodyComponent.EnableTileCollision"), true);
  assert.equal(values.get("MOD.Core.HitComponent.ColliderType"), 1);
  assert.equal(values.get("MOD.Core.HitComponent.IsLegacy"), false);
  assert.equal(values.get("MOD.Core.HitComponent.CollisionGroup").Id, "MOD@HitBox");
  const collisionGroups = JSON.parse(read("Global/CollisionGroupSet.collisiongroupset"));
  assert.ok(collisionGroups.ContentProto.Json.Groups.some((group) => group.Id === "MOD@HitBox"));
  assert.ok(values.get("MOD.Core.SpriteRendererComponent.SpriteRUID"));
});

test("M1 battle scripts expose the observable elapsed-time contract", () => {
  const session = read("RootDesk/MyDesk/Combat/BattleSession.mlua");
  const unit = read("RootDesk/MyDesk/Combat/BattleUnit.mlua");
  const attack = read("RootDesk/MyDesk/Combat/AssaultAttack.mlua");

  assert.match(session, /method void AdvanceForTest\(number elapsed\)/);
  assert.match(session, /method string GetDebugSnapshot\(\)/);
  assert.match(session, /method string GetUnitSnapshots\(\)/);
  assert.match(session, /WorldPosition/);
  assert.match(session, /UnitSnapshots/);
  assert.match(session, /hp=/);
  assert.match(session, /alive=/);
  assert.match(session, /x=/);
  assert.match(session, /y=/);
  assert.match(session, /self\._T\.resultEntered == true/);
  assert.match(session, /self\.Phase = "RESULT"/);
  assert.match(session, /self:EmitPresentation\("RESULT"/);
  assert.match(session, /camera\.DeadZone = Vector2\(1, 1\)/);
  assert.match(session, /camera\.IsAllowZoomInOut = false/);
  assert.match(session, /trigger\.Enable = false/);
  assert.match(session, /physicsCollider\.Enable = false/);
  assert.match(session, /UnitMaxHp = 220/);
  assert.match(session, /UnitMoveSpeed = 2\.0/);
  assert.match(session, /UnitDamage = 35/);
  assert.match(session, /UnitAttackInterval = 0\.7/);
  assert.match(session, /UnitAttackRange = 0\.6/);
  assert.match(session, /RetargetInterval = 0\.5/);
  assert.match(session, /EnemyOpeningDelay = 0\.12/);
  assert.match(session, /PlayerSpawnPosition = Vector3\(-2\.4, 0, 0\)/);

  assert.match(unit, /movement:MoveToDirection\(direction, delta\)/);
  assert.match(unit, /movement\.InputSpeed = self\.MoveSpeed \* 1\.2/);
  assert.match(unit, /session:QueueDamage\(self\.Entity, event\.TotalDamage, event\.AttackerEntity\)/);
  assert.match(attack, /self:AttackFrom\(Vector2\(1\.2, 1\.2\)/);
  assert.match(attack, /return self\.AttackDamage/);
  assert.match(attack, /openingDelayPending/);
  assert.match(attack, /self\.CooldownRemaining = self\._T\.openingDelay/);
  assert.match(attack, /self\.PendingTarget = target/);

  assert.doesNotMatch(unit, /SetWorldPosition|SetPosition\(/);
  assert.doesNotMatch(attack, /Hp\s*[-+]=/);
});

test("M1 Phase 2 exposes server-owned deployment and roster gates", () => {
  const session = read("RootDesk/MyDesk/Combat/BattleSession.mlua");
  const unit = read("RootDesk/MyDesk/Combat/BattleUnit.mlua");

  assert.match(session, /@Sync property integer PlayerRosterCount = 0/);
  assert.match(session, /@Sync property string SelectedUnitKind = ""/);
  assert.match(session, /DeploymentMinX = -5\.0/);
  assert.match(session, /DeploymentMaxX = -2\.0/);
  assert.match(session, /DeploymentMinY = -3\.0/);
  assert.match(session, /DeploymentMaxY = 1\.0/);
  assert.match(session, /DeploymentMinDistance = 0\.6/);
  assert.match(session, /DeploymentMaxUnits = 6/);
  assert.match(session, /method void RequestSelectUnit\(string unitKind\)/);
  assert.match(session, /method void RequestDeployAtWorld\(Vector3 requestedPosition\)/);
  assert.match(session, /method void RequestRemoveUnit\(string unitName\)/);
  assert.match(session, /method void RequestStartBattle\(\)/);
  assert.match(session, /method void BeginBattle\(\)/);
  assert.match(session, /method string FindPlayerUnitAtPosition\(Vector3 position\)/);
  assert.match(session, /method boolean RemovePlayerUnitByName\(string unitName\)/);
  assert.match(session, /self:RemovePlayerUnitByName\(existingName\)/);
  assert.match(session, /self:SpawnFixedEnemies\(\)/);
  assert.match(session, /record\.unit:ActivateForBattle\(\)/);
  assert.match(session, /battleStarting/);
  assert.match(session, /self\.Phase = "BATTLE"\s+self\._T\.battleStarting = false/);
  assert.match(session, /self:IsAuthorizedRequester\(senderUserId\)/);
  assert.match(session, /self\.Phase ~= "DEPLOYMENT"/);
  assert.match(unit, /@Sync property string UnitKind = "ASSAULT"/);
  assert.match(unit, /method void ActivateForBattle\(\)/);
});

test("M1 Phase 2 client adapter binds named UI and world deployment input", () => {
  const input = read("RootDesk/MyDesk/Combat/BattleDeploymentInput.mlua");

  for (const buttonName of ["BtnTank", "BtnAssault", "BtnShooter", "BtnStart"]) {
    assert.match(input, new RegExp(buttonName));
  }
  assert.match(input, /@ExecSpace\("ClientOnly"\)\s+method void OnBeginPlay\(\)/);
  assert.match(input, /ConnectEvent\(ButtonClickEvent/);
  assert.match(input, /ConnectEvent\(ScreenTouchEvent/);
  assert.match(input, /ScreenToWorldPosition\(event\.TouchPoint\)/);
  assert.match(input, /IsPointerOverUI\(event\.TouchId\)/);
  assert.match(input, /DisconnectEvent\(ButtonClickEvent/);
  assert.match(input, /DisconnectEvent\(ScreenTouchEvent/);
  assert.match(input, /session:RequestDeployAtWorld\(Vector3\(worldPosition\.x, worldPosition\.y, 0\)\)/);
  assert.match(input, /method void ConfigureClientCamera\(\)/);
  assert.match(input, /camera\.ScreenOffset = Vector2\(0\.5, 0\.5\)/);
  assert.match(input, /camera\.CameraOffset = Vector2\(0, 0\)/);
  assert.match(input, /self\.cameraConfigured == true/);
});
