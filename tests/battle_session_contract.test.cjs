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

test("M1 map keeps RectTile and exposes the fixed battle session camera", () => {
  const map = MapBuilder.read(path.join(root, "map/map01.map"));
  assert.equal(map.getMapInfo().TileMapMode, 1);
  const rootEntity = map.listEntities().find((entity) => entity.path === "/maps/map01");
  assert.ok(rootEntity);
  assert.match(rootEntity.componentNames, /script\.BattleSession/);
  assert.match(rootEntity.componentNames, /script\.BattleFixedCamera/);
  assert.doesNotMatch(rootEntity.componentNames, /BattleDeploymentInput/);
});

test("fixed battlefield camera has one client-only CameraComponent owner", () => {
  const combatPath = path.join(root, "RootDesk/MyDesk/Combat");
  const combatScripts = fs.readdirSync(combatPath)
    .filter((file) => file.endsWith(".mlua"))
    .map((file) => ({ file, source: fs.readFileSync(path.join(combatPath, file), "utf8") }));
  const cameraOwners = combatScripts
    .filter(({ source }) => source.replace(/--[^\r\n]*/g, "").includes("CameraComponent"))
    .map(({ file }) => file);

  assert.deepEqual(cameraOwners, ["BattleFixedCamera.mlua"]);

  const camera = read("RootDesk/MyDesk/Combat/BattleFixedCamera.mlua");
  for (const method of ["OnBeginPlay", "OnUpdate", "OnEndPlay", "TryConfigureCamera", "RestoreCamera"]) {
    assert.match(camera, new RegExp(`@ExecSpace\\("ClientOnly"\\)\\s+method [^\\n]+ ${method}\\(`));
  }
  assert.match(camera, /property number CameraZoomPercent/);
  assert.match(camera, /property Vector2 CameraOffset/);
  assert.match(camera, /originalDeadZone = camera\.DeadZone/);
  assert.match(camera, /camera\.DeadZone = self\._T\.originalDeadZone/);
  assert.match(camera, /camera\.CameraOffset = self\.CameraOffset/);
  assert.match(camera, /camera\.CameraOffset = self\._T\.originalCameraOffset/);
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

test("fixed battle keeps the tank profile and adds the shooter roster", () => {
  const session = read("RootDesk/MyDesk/Combat/BattleSession.mlua");
  const unit = read("RootDesk/MyDesk/Combat/BattleUnit.mlua");
  const contact = read("RootDesk/MyDesk/Combat/TankContactAttack.mlua");
  const presentation = read("RootDesk/MyDesk/Combat/TankPresentation.mlua");
  const assault = read("RootDesk/MyDesk/Combat/AssaultAttack.mlua");
  const runtimeProbe = read("tests/tank_contact_runtime_probe.lua");

  assert.match(session, /SpawnUnit\(self\.PlayerModelId, "M1_PlayerTank", "PLAYER", "TANK"/);
  assert.match(session, /SpawnUnit\(self\.PlayerModelId, "M1_PlayerShooter", "PLAYER", "SHOOTER"/);
  assert.match(session, /SpawnUnit\(self\.EnemyModelId, "M1_EnemyAssault", "ENEMY", "ASSAULT"/);
  assert.match(session, /self\.PlayerAlive = 2/);
  assert.match(session, /TankMaxHp = 500/);
  assert.match(session, /TankMoveSpeed = 1\.1/);
  assert.match(session, /TankContactDamage = 40/);
  assert.match(session, /TankContactCooldown = 2\.0/);
  assert.match(session, /TankKnockbackDistance = 0\.8/);
  assert.match(session, /HitStopDuration = 0\.2/);
  assert.match(session, /QueueKnockback/);
  assert.match(session, /ApplyPendingKnockbacks/);
  assert.match(session, /ArenaMinX/);
  assert.doesNotMatch(session, /CameraComponent|CameraZoomPercent|CameraOffset/);
  assert.match(session, /self:EmitPresentation\("RESULT"/);
  assert.match(session, /self\._T\.resultEntered == true/);

  assert.match(unit, /@Sync property string UnitKind = "ASSAULT"/);
  assert.match(unit, /if self\.UnitKind == "TANK" then/);
  assert.match(unit, /self:DriveAttack\(target, false\)/);
  assert.match(unit, /self:DriveAttack\(target, true\)/);
  assert.match(unit, /HitStopDuration = 0\.2/);
  assert.match(unit, /hitStopRemaining/);
  assert.match(unit, /hitStopMovement:Stop\(\)/);
  assert.match(unit, /self\.CombatState = "IDLE"/);
  assert.match(unit, /session:QueueDamage\(self\.Entity, event\.TotalDamage, event\.AttackerEntity\)/);
  assert.doesNotMatch(unit, /SetWorldPosition|SetPosition\(/);

  assert.match(contact, /extends AttackComponent/);
  assert.match(contact, /ContactDamage = 40/);
  assert.match(contact, /ContactCooldown = 2\.0/);
  assert.match(contact, /self:AttackFrom\(self\.ContactSize/);
  assert.doesNotMatch(contact, /TryContact\(Entity target\)/);
  assert.match(contact, /targetCooldowns/);
  assert.match(contact, /return self\.ContactDamage/);
  assert.match(contact, /session:QueueKnockback/);
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
  assert.match(runtimeProbe, /session:SpawnUnit/);
  assert.match(runtimeProbe, /_TimerService:SetTimerOnce/);
  assert.match(runtimeProbe, /session:EnterResult\("WIN"\)/);
  assert.match(runtimeProbe, /\[M1\]\[TankProbe\] PASS/);
});

test("Issue #4 adds a configurable hitscan shooter adapter", () => {
  const session = read("RootDesk/MyDesk/Combat/BattleSession.mlua");
  const composition = read("RootDesk/MyDesk/Combat/BattleAttackComposition.mlua");
  const unit = read("RootDesk/MyDesk/Combat/BattleUnit.mlua");
  const shooter = read("RootDesk/MyDesk/Combat/ShooterAttack.mlua");
  const runtimeProbe = read("tests/shooter_runtime_probe.lua");

  assert.match(session, /ShooterMaxHp = 120/);
  assert.match(session, /ShooterMoveSpeed = 0\.8/);
  assert.match(session, /ShooterDamage = 30/);
  assert.match(session, /ShooterAttackInterval = 0\.8/);
  assert.match(session, /ShooterAttackRange = 4\.0/);
  assert.match(session, /ShooterImpactDelay/);
  assert.match(session, /unitKind == "SHOOTER"/);
  assert.match(session, /self\.ShooterMaxHp/);
  assert.match(session, /self\.ShooterAttackRange/);

  assert.match(composition, /unitKind == "SHOOTER"/);
  assert.match(composition, /script\.ShooterAttack/);
  assert.match(unit, /unitKind == "TANK"/);
  assert.match(unit, /self\.Entity\.Enable ~= false/);
  assert.doesNotMatch(unit, /Projectile|projectile/);

  assert.match(shooter, /extends AttackComponent/);
  assert.match(shooter, /AttackDamage = 30/);
  assert.match(shooter, /AttackRange = 4\.0/);
  assert.match(shooter, /AttackInterval = 0\.8/);
  assert.match(shooter, /method void TryEngage\(Entity target, boolean targetInRange\)/);
  assert.match(shooter, /method void Advance\(number delta\)/);
  assert.match(shooter, /@ExecSpace\("ServerOnly"\)\s+method void OnUpdate\(number delta\)/);
  assert.match(shooter, /method void Cancel\(\)/);
  assert.match(shooter, /AttackFrom\(Vector2\(0\.2, 0\.2\), Vector2\(targetPosition\.x, targetPosition\.y\), "shooter", nil\)/);
  assert.match(shooter, /impactTarget/);
  assert.match(shooter, /return dx \* dx \+ dy \* dy <= self\.AttackRange \* self\.AttackRange/);
  assert.doesNotMatch(shooter, /AttackRange \+ 0\.05/);
  assert.match(shooter, /return self\.AttackDamage/);
  assert.match(shooter, /session:EmitPresentation\("HIT"/);
  assert.doesNotMatch(shooter, /SpawnService|Projectile|projectile/);

  assert.match(runtimeProbe, /SpawnUnit\(session\.EnemyModelId, "M1_ShooterProbeTarget"/);
  assert.match(runtimeProbe, /AdvanceForTest/);
  assert.match(runtimeProbe, /pre-impact/);
  assert.match(runtimeProbe, /target dies before impact/);
  assert.match(runtimeProbe, /target leaves range before impact/);
  assert.match(runtimeProbe, /SetEnable\(false\)/);
  assert.match(runtimeProbe, /replacementTarget/);
  assert.match(runtimeProbe, /ATTACK_START/);
  assert.match(runtimeProbe, /AttackSerial/);
  assert.match(runtimeProbe, /Children:ToTable/);
  assert.match(runtimeProbe, /\[M1\]\[ShooterProbe\] PASS/);
});

test("BattleUnit owns attack dispatch while BattleSession stays adapter-agnostic", () => {
  const session = read("RootDesk/MyDesk/Combat/BattleSession.mlua");
  const unit = read("RootDesk/MyDesk/Combat/BattleUnit.mlua");
  const composition = read("RootDesk/MyDesk/Combat/BattleAttackComposition.mlua");
  const contact = read("RootDesk/MyDesk/Combat/TankContactAttack.mlua");
  const assault = read("RootDesk/MyDesk/Combat/AssaultAttack.mlua");
  const runtimeProbe = read("tests/tank_contact_runtime_probe.lua");

  assert.match(composition, /method Component CreateAdapter\(Entity owner, string unitKind\)/);
  assert.match(composition, /owner:AddComponent\(adapterType\)/);
  assert.match(unit, /method void BindAttackFactory\(Component factory\)/);
  assert.match(unit, /method void DriveAttack\(Entity target, boolean targetInRange\)/);
  assert.match(unit, /method void AdvanceAttack\(number delta\)/);
  assert.match(unit, /method void CancelAttack\(\)/);
  assert.match(unit, /attackAdapter/);
  assert.match(session, /entity:AddComponent\("script\.BattleAttackComposition"\)/);
  assert.doesNotMatch(unit, /self\.Entity:AddComponent\(adapterType\)/);
  assert.match(assault, /method void TryEngage\(Entity target, boolean targetInRange\)/);
  assert.match(assault, /method void Cancel\(\)/);
  assert.match(contact, /method void TryEngage\(Entity target, boolean targetInRange\)/);
  assert.match(contact, /method void Cancel\(\)/);
  assert.match(contact, /session:QueueKnockback\(/);
  assert.match(runtimeProbe, /tankUnit:DriveAttack\(tank, true\)/);
  assert.doesNotMatch(runtimeProbe, /GetComponent\("script\.(TankContactAttack|AssaultAttack)"\)/);
  assert.match(session, /record\.unit:AdvanceAttack\(delta\)/);
  assert.doesNotMatch(session, /script\.AssaultAttack|script\.TankContactAttack/);
  assert.doesNotMatch(session, /QueueTankContactKnockback/);
});

test("Issue #3 keeps the existing battle group UI available without binding it to runtime", () => {
  const uiPath = path.join(root, "ui/BattleGroup.ui");
  assert.ok(fs.existsSync(uiPath));
  const ui = read("ui/BattleGroup.ui");
  assert.match(ui, /BtnTank/);
  const parsed = JSON.parse(ui);
  assert.equal(parsed.ContentProto.Entities[0].jsonString.visible, false);
});
