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
  assert.match(rootEntity.componentNames, /script\.BattleDeploymentInput/);
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

test("battle phase keeps the Tank profile and adds Shooter to the player formation", () => {
  const session = read("RootDesk/MyDesk/Combat/BattleSession.mlua");
  const unit = read("RootDesk/MyDesk/Combat/BattleUnit.mlua");
  const contact = read("RootDesk/MyDesk/Combat/TankContactAttack.mlua");
  const presentation = read("RootDesk/MyDesk/Combat/TankPresentation.mlua");
  const shooterPresentation = read("RootDesk/MyDesk/Combat/ShooterPresentation.mlua");
  const hitEffectPresentation = read("RootDesk/MyDesk/Combat/BattleHitEffectPresentation.mlua");
  const assault = read("RootDesk/MyDesk/Combat/AssaultAttack.mlua");
  const shooterAttack = read("RootDesk/MyDesk/Combat/ShooterAttack.mlua");
  const runtimeProbe = read("tests/tank_contact_runtime_probe.lua");
  const monsterData = read("RootDesk/MyDesk/Combat/MonsterData.csv");

  assert.match(session, /EnemyMonsterId3 = "monster_warrior"/);
  assert.match(session, /self\.PlayerAlive = 0/);
  assert.match(session, /self\.EnemyAlive = 6/);
  assert.match(session, /EventHistory/);
  assert.match(monsterData, /monster_tank,Tank,TANK,battleunit,500,1\.1,40,2\.0,0\.65/);
  assert.match(monsterData, /monster_warrior,Warrior,ASSAULT,battleunit,220,2\.0,35,0\.7,0\.6/);
  assert.match(monsterData, /monster_shooter,Shooter,SHOOTER,battleunit,120,0\.8,30,2,4\.0/);
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
  assert.match(unit, /@Sync property integer HitEffectSerial = 0/);
  assert.match(unit, /@Sync property string LastHitEffectRUID = "TBD"/);
  assert.match(unit, /method string GetHitEffectRUID\(\)/);
  assert.match(unit, /self\.LastHitEffectRUID = hitEffectRUID/);
  assert.match(unit, /self\.HitEffectSerial = self\.HitEffectSerial \+ 1/);
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
  assert.doesNotMatch(contact, /_SoundService|VFX|PlayEffect/);

  assert.match(presentation, /a95cfed2c8fe4d2cb64cbb62db051f92/);
  assert.match(presentation, /8257566e41aa4234929e81c6c2dab2e4/);
  assert.match(presentation, /OnHitAnimationRUID/);
  assert.match(presentation, /5ebbdaf503964f3e87de155d16650805/);
  assert.match(presentation, /dddbe2f162184ec89add7440da56eb75/);
  assert.match(presentation, /AttackSoundRUID/);
  assert.match(presentation, /OnHitSoundRUID/);
  assert.match(presentation, /6eb2ef8a783c4393bd7ee6a2c199bda7/);
  assert.match(presentation, /c49646f7299e4c6e81e953c96e20b294/);
  assert.match(presentation, /lastAttackSerial/);
  assert.match(presentation, /PlaySoundAtPos/);
  assert.match(presentation, /@ExecSpace\("ClientOnly"\)\s+method void OnBeginPlay\(/);
  assert.match(presentation, /@ExecSpace\("ClientOnly"\)\s+method void OnUpdate\(/);
  assert.match(presentation, /unit\.DamageTakenSerial[\s\S]*self:PlayAtEntity\(self\.OnHitSoundRUID\)/);
  assert.match(presentation, /unit\.IsDead == true and self\._T\.deathSoundPlayed ~= true/);
  assert.match(presentation, /soundRUID == nil[\s\S]*soundRUID == "TBD"[\s\S]*soundRUID == "N\/A"/);

  assert.match(session, /entity:AddComponent\("script\.BattleHitEffectPresentation"\)/);
  assert.match(hitEffectPresentation, /@ExecSpace\("ClientOnly"\)\s+method void OnUpdate\(/);
  assert.match(hitEffectPresentation, /unit\.HitEffectSerial/);
  assert.match(hitEffectPresentation, /unit\.LastHitEffectRUID/);
  assert.match(hitEffectPresentation, /PlayEffectAttached\(effectRUID, self\.Entity/);
  assert.match(hitEffectPresentation, /effectRUID == nil[\s\S]*effectRUID == "TBD"[\s\S]*effectRUID == "N\/A"/);

  assert.match(session, /entity:AddComponent\("script\.ShooterPresentation"\)/);
  assert.match(shooterPresentation, /AttackSoundRUID/);
  assert.match(shooterPresentation, /OnHitSoundRUID/);
  assert.match(shooterPresentation, /DeathSoundRUID/);
  assert.match(shooterPresentation, /lastAttackSerial/);
  assert.match(shooterPresentation, /lastDamageSerial/);
  assert.match(shooterPresentation, /PlaySoundAtPos/);
  assert.match(shooterPresentation, /@ExecSpace\("ClientOnly"\)\s+method void OnBeginPlay\(/);
  assert.match(shooterPresentation, /@ExecSpace\("ClientOnly"\)\s+method void OnUpdate\(/);
  assert.match(shooterPresentation, /unit\.DamageTakenSerial[\s\S]*self:PlayAtEntity\(self\.OnHitSoundRUID\)/);
  assert.match(shooterPresentation, /unit\.IsDead == true and self\._T\.deathSoundPlayed ~= true/);
  assert.match(shooterPresentation, /soundRUID == nil[\s\S]*soundRUID == "TBD"[\s\S]*soundRUID == "N\/A"/);
  assert.match(shooterAttack, /property string HitEffectRUID = "1f2bdb3b15a145ea8f3db3fbfb61296b"/);


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
  const monsterData = read("RootDesk/MyDesk/Combat/MonsterData.csv");

  assert.match(monsterData, /monster_shooter,Shooter,SHOOTER,battleunit,120,0\.8,30,2,4\.0,9,/);
  assert.match(session, /profile\.MonsterType == "SHOOTER"/);
  assert.match(session, /profile\.MaxHp/);
  assert.match(session, /profile\.AttackRange/);

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
  assert.match(shooter, /method void CancelImpact\(\)[\s\S]*self\.CooldownRemaining = 0/);
  assert.match(shooter, /AttackFrom\(Vector2\(0\.2, 0\.2\), Vector2\(targetPosition\.x, targetPosition\.y\), "shooter", nil\)/);
  assert.match(shooter, /impactTarget/);
  assert.match(shooter, /return dx \* dx \+ dy \* dy <= self\.AttackRange \* self\.AttackRange/);
  assert.doesNotMatch(shooter, /AttackRange \+ 0\.05/);
  assert.match(shooter, /return self\.AttackDamage/);
  assert.match(shooter, /session:EmitPresentation\("HIT"/);
  assert.match(unit, /session:EmitPresentation\("TARGET_HIT"/);
  assert.match(session, /while #self\._T\.eventHistory > 24/);
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

test("Issue #7 uses the delivered option template, start button, and result entities", () => {
  const { UIBuilder } = require(path.join(root, ".agents/skills/msw-ui-system/scripts/msw_ui_builder.cjs"));
  const ui = UIBuilder.read(path.join(root, "ui/BattleGroup.ui"));
  for (const name of ["MonsterOptionContainer", "MonsterOptionTemplate", "Portrait", "MonsterName", "SelectedGlow", "BtnStart", "ResultWin", "ResultLose", "ResultDraw"]) {
    assert.ok(ui.listEntities().some((entity) => entity.name === name), `${name} is missing`);
  }
  for (const name of ["ResultWin", "ResultLose", "ResultDraw"]) {
    assert.equal(ui.listEntities().find((entity) => entity.name === name).enable, false);
  }
});

test("Issue #7 keeps deployment authority on the map session and uses IDs for cards", () => {
  const session = read("RootDesk/MyDesk/Combat/BattleSession.mlua");
  const input = read("RootDesk/MyDesk/Combat/BattleDeploymentInput.mlua");
  const probe = read("tests/deployment_runtime_probe.lua");
  const uiProbe = read("tests/deployment_ui_runtime_probe.lua");
  assert.match(session, /@Sync property string Phase = "DEPLOYMENT"/);
  assert.match(session, /method void RequestMonsterOptions\(\)/);
  assert.match(session, /table\.insert\(options, \{ profile\.MonsterId, profile\.MonsterName, profile\.StandAnimationRUID \}\)/);
  assert.match(session, /@ExecSpace\("Server"\)\s+method void RequestBattlefieldClick\(string monsterId, Vector3 position\)/);
  assert.match(session, /method boolean TryDeployMonster\(string monsterId, Vector3 position\)/);
  assert.match(session, /self:GetMonsterProfile\(monsterId\)/);
  assert.match(session, /DeploymentMinDistance = 0\.6/);
  assert.match(session, /DeploymentMaxUnits = 6/);
  assert.match(session, /method boolean TryStartBattle\(\)/);
  assert.match(session, /method boolean CanStartBattleWithPlayerCount\(integer playerCount\)/);
  assert.match(input, /self\.optionTemplate:Clone\(/);
  assert.match(input, /portrait\.ImageRUID = DataRef\(standRUID\)/);
  assert.match(input, /self\.selectedMonsterId = monsterId/);
  assert.match(input, /self\.session:RequestBattlefieldClick\(self\.selectedMonsterId/);
  assert.doesNotMatch(input, /BtnTank|BtnAssault|BtnShooter|RequestSelectUnit/);
  for (const scenario of ["zero player units", "unknown MonsterId", "seventh unit", "removal after start"]) {
    assert.ok(probe.includes(scenario), `${scenario} runtime assertion missing`);
  }
  assert.match(uiProbe, /#adapter\.optionCards == #adapter\.optionData/);
  assert.match(uiProbe, /portrait\.ImageRUID\.DataId == option\[3\]/);
  assert.match(uiProbe, /enabledGlows == 1/);
  assert.match(input, /method void SyncDeploymentControls\(\)/);
  assert.match(input, /self\.optionContainer:SetEnable\(enabled\)/);
  assert.match(input, /self\.startButton:SetEnable\(enabled\)/);
  assert.match(input, /glow = glowEntity, clickAction = clickAction/);
  assert.match(input, /method void HandleBattlefieldClick\(Vector3 position\)/);
  assert.match(uiProbe, /selectedCard\.clickAction\(\)/);
  assert.match(uiProbe, /HandleBattlefieldClick\(Vector3\(-4, 0, 0\)\)/);
  assert.match(uiProbe, /startButtonAction\(\)/);
  assert.match(uiProbe, /natural one-unit battle reaches a result/);
  assert.match(uiProbe, /exactly its matching result entity/);
  assert.match(probe, /for playerCount = 1, 6 do/);
});

test("Issue #5 publishes one strict MonsterData dataset for the three initial monsters", () => {
  const metadata = JSON.parse(read("RootDesk/MyDesk/Combat/MonsterData.userdataset"));
  const dataset = metadata.ContentProto.Json;
  const csvRows = read("RootDesk/MyDesk/Combat/MonsterData.csv")
    .trim()
    .split(/\r?\n/)
    .map((line) => line.split(","));
  const [header, ...rows] = csvRows;
  const requiredColumns = [
    "MonsterId",
    "MonsterName",
    "MonsterType",
    "ModelId",
    "MaxHp",
    "MoveSpeed",
    "AttackDamage",
    "AttackIntervalSeconds",
    "AttackRange",
    "AttackImpactFrame",
    "ContactDamage",
    "ContactCooldownSeconds",
    "ContactSizeX",
    "ContactSizeY",
    "KnockbackDistance",
    "StandAnimationRUID",
    "MoveAnimationRUID",
    "AttackAnimationRUID",
    "HitAnimationRUID",
    "DieAnimationRUID",
    "HitEffectRUID",
    "AttackSoundRUID",
    "OnHitSoundRUID",
    "DieSoundRUID",
  ];

  assert.equal(dataset.name, "MonsterData");
  assert.equal(dataset.serveronly, true);
  assert.match(metadata.EntryKey, new RegExp(dataset.id));
  for (const column of requiredColumns) assert.ok(header.includes(column), `missing ${column}`);
  assert.equal(rows.length, 3);

  const columnIndex = new Map(header.map((column, index) => [column, index]));
  const value = (row, column) => row[columnIndex.get(column)];
  const ids = rows.map((row) => value(row, "MonsterId"));
  assert.equal(new Set(ids).size, ids.length);
  assert.deepEqual(
    rows.map((row) => value(row, "MonsterType")).sort(),
    ["ASSAULT", "SHOOTER", "TANK"],
  );
  for (const row of rows) {
    assert.ok(value(row, "MonsterName"));
    assert.ok(value(row, "ModelId"));
    for (const column of ["MaxHp", "MoveSpeed", "AttackDamage", "AttackIntervalSeconds", "AttackRange"]) {
      assert.ok(Number(value(row, column)) > 0, `${column} must be positive`);
    }
  }
});

test("Issue #7 preserves the data-driven battle core behind deployment", () => {
  const session = read("RootDesk/MyDesk/Combat/BattleSession.mlua");
  const unit = read("RootDesk/MyDesk/Combat/BattleUnit.mlua");
  const probe = read("tests/six_vs_six_runtime_probe.lua");

  assert.match(session, /MonsterDataSetName = "MonsterData"/);
  assert.match(session, /method boolean LoadMonsterData\(\)/);
  assert.match(session, /_DataService:GetTable\(self\.MonsterDataSetName\)/);
  assert.match(session, /MonsterType/);
  assert.match(session, /AttackFramesPerSecond = 60/);
  assert.match(session, /profile\.ImpactDelaySeconds = profile\.AttackImpactFrame/);
  assert.match(session, /duplicate MonsterId/);
  assert.match(session, /invalid MonsterType/);
  assert.match(session, /invalid numeric value/);
  assert.match(session, /method Entity SpawnMonster\(string monsterId/);
  assert.match(session, /fixedEnemyRoster/);
  assert.match(session, /self\.PlayerAlive = 0/);
  assert.match(session, /self\.EnemyAlive = 6/);
  assert.match(session, /self:EmitPresentation\("RESULT"/);
  assert.match(session, /self\._T\.resultEntered == true/);
  assert.match(session, /script\.BattleDeploymentInput/);

  assert.match(unit, /@Sync property string MonsterId = ""/);
  assert.match(unit, /@Sync property string MonsterName = ""/);
  assert.match(unit, /monsterId/);
  assert.match(unit, /MonsterName/);

  for (const scenario of [
    "same-distance target is retained",
    "dead target is reacquired",
    "crowded units do not block or push each other",
    "WIN",
    "LOSE",
    "same-batch DRAW",
    "RESULT stops the battle",
  ]) {
    assert.match(probe, new RegExp(scenario.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
  }
  assert.match(probe, /\[M1\]\[SixVsSixProbe\] PASS/);
});
