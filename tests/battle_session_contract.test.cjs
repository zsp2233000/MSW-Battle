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

test("M1 map keeps RectTile and exposes only the fixed battle session", () => {
  const map = MapBuilder.read(path.join(root, "map/map01.map"));
  assert.equal(map.getMapInfo().TileMapMode, 1);
  const rootEntity = map.listEntities().find((entity) => entity.path === "/maps/map01");
  assert.ok(rootEntity);
  assert.match(rootEntity.componentNames, /script\.BattleSession/);
  assert.doesNotMatch(rootEntity.componentNames, /BattleDeploymentInput/);
});

test("M1 unit model has the RectTile movement and native hit contract", () => {
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

test("Issue #3 starts one tank and one assault with the fixed tank profile", () => {
  const session = read("RootDesk/MyDesk/Combat/BattleSession.mlua");
  const unit = read("RootDesk/MyDesk/Combat/BattleUnit.mlua");
  const contact = read("RootDesk/MyDesk/Combat/TankContactAttack.mlua");
  const presentation = read("RootDesk/MyDesk/Combat/TankPresentation.mlua");
  const assault = read("RootDesk/MyDesk/Combat/AssaultAttack.mlua");

  assert.match(session, /SpawnUnit\(self\.PlayerModelId, "M1_PlayerTank", "PLAYER", "TANK"/);
  assert.match(session, /SpawnUnit\(self\.EnemyModelId, "M1_EnemyAssault", "ENEMY", "ASSAULT"/);
  assert.match(session, /TankMaxHp = 500/);
  assert.match(session, /TankMoveSpeed = 1\.1/);
  assert.match(session, /TankContactDamage = 40/);
  assert.match(session, /TankContactCooldown = 2\.0/);
  assert.match(session, /TankKnockbackDistance = 0\.8/);
  assert.match(session, /QueueTankContactKnockback/);
  assert.match(session, /ApplyPendingKnockbacks/);
  assert.match(session, /ArenaMinX/);
  assert.match(session, /CameraZoomPercent = 70/);
  assert.match(session, /CameraOffset = Vector2\(0, -1\.0\)/);
  assert.match(session, /self:EmitPresentation\("RESULT"/);
  assert.match(session, /self\._T\.resultEntered == true/);

  assert.match(unit, /@Sync property string UnitKind = "ASSAULT"/);
  assert.match(unit, /if self\.UnitKind == "TANK" then/);
  assert.match(unit, /contact:TryContact\(target\)/);
  assert.match(unit, /self\.CombatState = "IDLE"/);
  assert.match(unit, /session:QueueDamage\(self\.Entity, event\.TotalDamage, event\.AttackerEntity\)/);
  assert.doesNotMatch(unit, /SetWorldPosition|SetPosition\(/);

  assert.match(contact, /extends AttackComponent/);
  assert.match(contact, /ContactDamage = 40/);
  assert.match(contact, /ContactCooldown = 2\.0/);
  assert.match(contact, /self:AttackFrom\(self\.ContactSize/);
  assert.match(contact, /targetCooldowns/);
  assert.match(contact, /return self\.ContactDamage/);
  assert.match(contact, /session:QueueTankContactKnockback/);
  assert.doesNotMatch(contact, /_SoundService|VFX|Effect/);

  assert.match(presentation, /a95cfed2c8fe4d2cb64cbb62db051f92/);
  assert.match(presentation, /8257566e41aa4234929e81c6c2dab2e4/);
  assert.match(presentation, /5ebbdaf503964f3e87de155d16650805/);
  assert.match(presentation, /dddbe2f162184ec89add7440da56eb75/);
  assert.match(presentation, /6eb2ef8a783c4393bd7ee6a2c199bda7/);
  assert.match(presentation, /c49646f7299e4c6e81e953c96e20b294/);
  assert.match(presentation, /PlaySoundAtPos/);
  assert.doesNotMatch(presentation, /AttackSound|ContactSound/);

  assert.match(assault, /extends AttackComponent/);
  assert.match(assault, /return self\.AttackDamage/);
});

test("Issue #3 keeps the existing battle group UI available without binding it to runtime", () => {
  const uiPath = path.join(root, "ui/BattleGroup.ui");
  assert.ok(fs.existsSync(uiPath));
  const ui = read("ui/BattleGroup.ui");
  assert.match(ui, /BtnTank/);
  const parsed = JSON.parse(ui);
  assert.equal(parsed.ContentProto.Entities[0].jsonString.visible, false);
});
