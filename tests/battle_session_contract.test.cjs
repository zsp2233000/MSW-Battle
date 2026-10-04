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

function readCsvRows(relativePath) {
  return read(relativePath)
    .replace(/^\uFEFF/, "")
    .trim()
    .split(/\r?\n/)
    .map((line) => line.split(",").map((cell) => cell.trim()));
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
  const metadata = JSON.parse(read("RootDesk/MyDesk/Data/MonsterData.userdataset"));
  const dataset = metadata.ContentProto.Json;
  const csvRows = readCsvRows("RootDesk/MyDesk/Data/MonsterData.csv");
  const [header, ...rows] = csvRows;
  assert.doesNotMatch(header.join(","), /\bContactDamage\b/);
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
  assert.match(session, /MonsterType/);
  assert.match(session, /method Entity SpawnMonster\(string monsterId/);
  assert.match(session, /fixedEnemyRoster/);
  assert.match(session, /self\.PlayerAlive = 0/);
  assert.match(session, /self\.InitialPlayerAlive = self\.PlayerAlive/);
  assert.match(session, /self\.InitialEnemyAlive = self\.EnemyAlive/);
  assert.doesNotMatch(session, /self\.EnemyAlive\s*=\s*6/);
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

test("Issue #14 centralizes BattleSession registration, death, and removal accounting", () => {
  const session = read("RootDesk/MyDesk/Combat/BattleSession.mlua");
  const deploymentProbe = read("tests/deployment_runtime_probe.lua");
  const tankProbe = read("tests/tank_contact_runtime_probe.lua");
  const batchProbe = read("tests/six_vs_six_batch_outcome_probe.lua");

  assert.match(session, /@ExecSpace\("ServerOnly"\)\s+method boolean TryRemoveDeployedUnitAt\(Vector3 position\)/);
  assert.doesNotMatch(deploymentProbe, /session\._T|:RemoveDeployedUnit\(/);
  for (const scenario of [
    "deployment starts empty against six fixed enemies",
    "zero player units cannot start",
    "first unit",
    "sixth unit",
    "seventh unit is rejected",
    "profile lookups return distinct outer tables",
    "editing a profile copy does not mutate catalog",
    "removal with a NaN z coordinate is rejected",
    "position-based removal selects the deployed unit",
    "redeployment registers exactly one replacement unit",
    "removal after start is rejected",
  ]) {
    assert.ok(deploymentProbe.includes(scenario), `${scenario} runtime assertion missing`);
  }
  assert.doesNotMatch(tankProbe, /EnemyAlive\s*=\s*session\.EnemyAlive\s*\+/);
  for (const scenario of [
    "registered spawns own the synchronized faction counts",
    "disabling a living unit does not count as death",
    "a fully resolved lethal damage batch decrements the enemy count once",
    "synchronized counts and the existing snapshot expose the resolved death",
    "duplicate death notification and damage to a dead unit do not decrement again",
  ]) {
    assert.ok(batchProbe.includes(scenario), `${scenario} runtime assertion missing`);
  }
});

test("Issue #15 exposes an atomic server-only controlled battle-scene seam", () => {
  const session = read("RootDesk/MyDesk/Combat/BattleSession.mlua");
  const probe = read("tests/controlled_scenario_runtime_probe.lua");

  assert.match(
    session,
    /@ExecSpace\("ServerOnly"\)\s+method boolean PrepareBattleForTest\(table playerRoster, table enemyRoster\)/,
  );
  assert.match(session, /Environment:IsMakerPlay\(\)/);
  assert.match(session, /method boolean TryStartBattle\(\)/);

  for (const scenario of [
    "valid 1v1 scene",
    "zero-player scene cannot start",
    "overlapping deployment positions",
    "arena boundary position",
    "preparation without a manual clock",
    "unknown MonsterId",
    "zero-enemy roster",
    "duplicate team name",
    "seventh unit",
    "invalid arena coordinates",
    "foreign userdata is rejected as a position",
    "unknown profile override",
    "invalid numeric overrides",
    "scene switch discards queued old-scene work",
    "throwing case releases its owned clock",
    "partial spawn failure clears every new unit",
  ]) {
    assert.ok(probe.includes(scenario), `${scenario} runtime assertion missing`);
  }

  assert.doesNotMatch(probe, /session\._T/);
  assert.match(probe, /\[M1\]\[ControlledScenarioProbe\] PASS/);
});

test("Issue #16 attack probes use prepared battle scenes and public session stepping", () => {
  const probePaths = [
    "tests/attack_execution_runtime_probe.lua",
    "tests/attack_clock_runtime_probe.lua",
  ];
  const forbiddenCalls = /session\._T|:(?:SpawnUnit|SpawnConfiguredUnit|TryDeployMonster|QueueDamage|QueueKnockback|ApplyPendingKnockbacks|ResolveDamageBatch|EvaluateResult|EnterResult)\s*\(/;
  const mutableSessionOutcomes = /session\.(?:Phase|Result|PlayerAlive|EnemyAlive|InitialPlayerAlive|InitialEnemyAlive)\s*=(?!=)/;

  for (const probePath of probePaths) {
    const probe = read(probePath);
    assert.match(probe, /session:PrepareBattleForTest\(/, `${probePath} must prepare a complete controlled scene`);
    assert.match(probe, /session:TryStartBattle\(\)/, `${probePath} must start the prepared battle`);
    assert.match(probe, /session:AdvanceForTest\(/, `${probePath} must verify through full session steps`);
    assert.doesNotMatch(probe, forbiddenCalls, `${probePath} must not bypass roster or settlement APIs`);
    assert.doesNotMatch(probe, mutableSessionOutcomes, `${probePath} must not write session outcome state`);
    assert.doesNotMatch(probe, /:\s*SetEnable\s*\(\s*false\s*\)/,
      `${probePath} must keep every prepared battle unit enabled`);
  }
});
