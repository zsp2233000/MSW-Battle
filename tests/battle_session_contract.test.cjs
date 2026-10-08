const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
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
  const targetingProbe = read("tests/targeting_crowding_runtime_probe.lua");

  assert.match(session, /MonsterDataSetName = "MonsterData"/);
  assert.match(session, /method boolean LoadMonsterData\(\)/);
  assert.match(session, /MonsterType/);
  assert.match(session, /method Entity SpawnMonster\(string monsterId/);
  assert.match(session, /placedRoster/);
  assert.doesNotMatch(session, /BuildFixedEnemyRoster|EnemyMonsterId[1-6]/);
  assert.match(session, /self\.PlayerAlive = 0/);
  assert.match(session, /self\.InitialPlayerAlive = self\.PlayerAlive/);
  assert.match(session, /self\.InitialEnemyAlive = self\.EnemyAlive/);
  assert.doesNotMatch(session, /self\.EnemyAlive\s*=\s*6/);
  assert.match(session, /script\.BattleDeploymentInput/);

  assert.match(unit, /@Sync property string MonsterId = ""/);
  assert.match(unit, /@Sync property string MonsterName = ""/);
  assert.match(unit, /monsterId/);
  assert.match(unit, /MonsterName/);

  for (const fixedRosterMember of [
    "M1_EnemyTank", "M1_EnemyTank2", "M1_EnemyAssault",
    "M1_EnemyAssault2", "M1_EnemyShooter", "M1_EnemyShooter2",
  ]) assert.ok(probe.includes(fixedRosterMember), `${fixedRosterMember} must stay in the formal 6v6 probe`);
  assert.match(probe, /InitialPlayerAlive == 6 and session\.InitialEnemyAlive == 6/);
  for (const scenario of [
    "unit selects the nearest live enemy through Tick",
    "exactly equidistant",
    "explicitly disabled",
    "native lethal HitEvent",
    "both displace toward their target on real physics frames",
    "natural WIN",
    "natural LOSE",
    "natural same-batch DRAW",
    "prevents post-result attacks",
  ]) {
    assert.ok(targetingProbe.includes(scenario), `${scenario} runtime assertion missing`);
  }
  assert.match(probe, /\[M1\]\[SixVsSixProbe\] PASS/);
  assert.match(targetingProbe, /\[M1\]\[TargetCrowdingProbe\] PASS/);
});

test("Issue #14 centralizes BattleSession registration, death, and removal accounting", () => {
  const session = read("RootDesk/MyDesk/Combat/BattleSession.mlua");
  const deploymentProbe = read("tests/deployment_runtime_probe.lua");
  const tankProbe = read("tests/tank_contact_runtime_probe.lua");

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
  const forbiddenCalls = /session\._T|:(?:SpawnUnit|SpawnConfiguredUnit|TryDeployMonster|QueueDamage|QueueKnockback|ApplyPendingKnockbacks)\s*\(/;
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
    assert.match(probe, /\[M1\]\[(?:AttackExecution|AttackClock)Probe\] PASS/,
      `${probePath} must report its successful terminal marker`);
    assert.match(probe, /\[M1\]\[(?:AttackExecution|AttackClock)Probe\] FAILURES=/,
      `${probePath} must report a terminal failure count`);
  }

  const executionProbe = read("tests/attack_execution_runtime_probe.lua");
  assert.match(executionProbe,
    /accepted hit survives same-batch attacker death/,
    "the execution probe must preserve accepted-hit behavior when its attacker dies in the batch");
  assert.match(executionProbe, /attackerDeathAt\s*<\s*outgoingHitAt/,
    "the death scenario must observe the accepted hit resolve after its attacker dies");
  assert.ok(
    executionProbe.indexOf("local runOk, runDetail = pcall(function()") <
      executionProbe.indexOf("if not isvalid(session) then"),
    "the execution probe must protect the missing-session path so it reaches its terminal marker",
  );
});

test("Issue #17 combat probes use controlled rosters and natural native outcomes", () => {
  const controlledProbes = [
    ["tests/tank_contact_runtime_probe.lua", "TankProbe"],
    ["tests/shooter_runtime_probe.lua", "ShooterProbe"],
    ["tests/targeting_crowding_runtime_probe.lua", "TargetCrowdingProbe"],
  ];
  const forbiddenBypasses = /session\._T|:(?:SpawnUnit|SpawnConfiguredUnit|QueueDamage|QueueKnockback|ApplyPendingKnockbacks)\s*\(/;
  const mutableSessionOutcomes = /session\.(?:Phase|Result|PlayerAlive|EnemyAlive|InitialPlayerAlive|InitialEnemyAlive)\s*=(?!=)/;

  for (const [probePath, probeTag] of controlledProbes) {
    const probe = read(probePath);
    assert.match(probe, /session:BeginManualSimulation\(\)/, `${probePath} must check clock acquisition`);
    assert.match(probe, /session:PrepareBattleForTest\(/, `${probePath} must prepare controlled rosters`);
    assert.match(probe, /session:TryStartBattle\(\)/, `${probePath} must start via the session API`);
    assert.match(probe, /session:EndManualSimulation\(\)/, `${probePath} must release the owned clock`);
    assert.doesNotMatch(probe, forbiddenBypasses, `${probePath} must use native attacks and session settlement`);
    assert.doesNotMatch(probe, mutableSessionOutcomes, `${probePath} must not write outcome state`);
    assert.ok(probe.includes(`[M1][${probeTag}] PASS`),
      `${probePath} must emit its matching PASS verdict`);
    assert.ok(probe.includes(`[M1][${probeTag}] FAILURES=`),
      `${probePath} must emit its matching failure verdict`);
    assert.match(probe, /local runOk, runDetail = pcall\(function\(\)/,
      `${probePath} must capture whole-script errors`);
    assert.ok(probe.indexOf("local runOk, runDetail = pcall(function()") <
      probe.indexOf('_EntityService:GetEntityByPath("/maps/map01")'),
    `${probePath} must capture map/session setup errors too`);
  }

  const tankProbe = read("tests/tank_contact_runtime_probe.lua");
  const shooterProbe = read("tests/shooter_runtime_probe.lua");
  const targetingProbe = read("tests/targeting_crowding_runtime_probe.lua");
  assert.match(tankProbe, /DamageTakenSerial == firstSerial \+ 4/,
    "tank contact must reach lethal damage through repeated native contacts");
  assert.match(tankProbe, /independently/,
    "tank contact must distinguish each target's cooldown");
  assert.match(shooterProbe, /actor\.ImpactDelay/,
    "shooter must use its profile impact timing");
  assert.match(shooterProbe, /defender\.DamageTakenSerial > 0/,
    "shooter must verify the native hit event");
  assert.match(targetingProbe, /nearestB:SetEnable\(false\)/,
    "only the explicit invalid-target case may disable a target");
  assert.match(targetingProbe, /AttackSerial > 0 and enemyUnit\.AttackSerial > 0/,
    "DRAW must resolve both already accepted attacks");

  const sixVsSixProbe = read("tests/six_vs_six_runtime_probe.lua");
  assert.equal((sixVsSixProbe.match(/session:TryDeployMonster\(/g) || []).length, 1,
    "formal 6v6 probe must deploy through the official command in its roster loop");
  assert.doesNotMatch(sixVsSixProbe, /session\._T|:(?:SpawnUnit|SpawnConfiguredUnit)\s*\(/,
    "formal 6v6 probe must retain registered map units and natural settlement");
  assert.match(sixVsSixProbe, /InitialPlayerAlive == 6 and session\.InitialEnemyAlive == 6/);
  assert.ok(sixVsSixProbe.indexOf("local runOk, runDetail = pcall(function()") <
    sixVsSixProbe.indexOf('_EntityService:GetEntityByPath("/maps/map01")'),
  "formal 6v6 probe must capture map/session setup errors");
});

test("Issue #18 verifies same-batch outcomes and natural 6v6 settlement", () => {
  const batchProbe = read("tests/six_vs_six_batch_outcome_probe.lua");
  const fullBattleProbe = read("tests/six_vs_six_full_battle_probe.lua");

  for (const scenario of [
    "one accepted lethal hit produces WIN",
    "one accepted lethal hit produces LOSE",
    "same-batch lethal hits produce DRAW in player-first order",
    "same-batch lethal hits produce DRAW in enemy-first order",
    "two accepted hits retain separate HP, serial, sound, and damage-event observations",
    "DRAW rejects later battle commands and remains stable after a full step",
  ]) {
    assert.ok(batchProbe.includes(scenario), `${scenario} runtime assertion missing`);
  }
  assert.match(fullBattleProbe, /result matches final alive counts/);
  assert.match(fullBattleProbe, /terminal state is stable for one second of real frames/);
});

test("Issue #19 probes renamed and same-type catalog identities through production APIs", () => {
  const sourceBytes = fs.readFileSync(path.join(root, "RootDesk/MyDesk/Data/MonsterData.csv"));
  const fixture = require(path.join(root, "tests/monster_catalog_csv_fixture.cjs"));
  const original = fixture.parseMonsterCsv(sourceBytes);
  const temporary = fixture.parseMonsterCsv(fixture.createTemporaryFixtureBuffer(sourceBytes));
  const originalTank = original.records.find((row) => row.MonsterId === "monster_tank");
  const renamedTank = temporary.records.find((row) => row.MonsterId === "monster_tank");
  const variantTank = temporary.records.find((row) => row.MonsterId === "probe_tank_variant");

  assert.equal(temporary.records.length, original.records.length + 1);
  assert.equal(renamedTank.MonsterName, "RenamedTank");
  assert.equal(variantTank.MonsterName, "VariantTank");
  assert.deepEqual(renamedTank, { ...originalTank, MonsterName: "RenamedTank" });
  assert.deepEqual(variantTank, {
    ...originalTank,
    MonsterId: "probe_tank_variant",
    MonsterName: "VariantTank",
  });

  const probe = read("tests/monster_catalog_identity_runtime_probe.lua");
  for (const expected of [
    'map:GetComponent("script.MonsterCatalog")',
    'catalog:GetProfile("monster_tank")',
    'catalog:GetProfile("probe_tank_variant")',
    'session:TryDeployMonster("monster_tank"',
    'session:TryDeployMonster("probe_tank_variant"',
    "primaryUnit.MonsterId == \"monster_tank\"",
    "variantUnit.MonsterId == \"probe_tank_variant\"",
    "[M1][CatalogIdentityProbe] PASS",
    "[M1][CatalogIdentityProbe] FAILURES=",
  ]) {
    assert.ok(probe.includes(expected), `${expected} runtime assertion missing`);
  }
  assert.doesNotMatch(probe,
    /session\._T|catalog:Load\(|session:GetMonsterProfile\(|PrepareBattleForTest\(|\w+Profile\.\w+\s*=(?!=)/,
    "the identity probe must only query the loaded catalog and use production deployment");
});

test("Issue #19 requires Maker lifecycle verification before modifying the catalog", async () => {
  const fixture = require(path.join(root, "tests/monster_catalog_csv_fixture.cjs"));
  const sourceBytes = fs.readFileSync(path.join(root, "RootDesk/MyDesk/Data/MonsterData.csv"));
  const sandbox = fs.mkdtempSync(path.join(os.tmpdir(), "m1-monster-csv-lifecycle-test-"));
  const csvPath = path.join(sandbox, "MonsterData.csv");

  try {
    fs.writeFileSync(csvPath, sourceBytes);
    await assert.rejects(fixture.withTemporaryMonsterCsv(async () => {
      throw new Error("probe must not run without lifecycle verification");
    }, { csvPath, logger: () => {} }),
    /required lifecycle callbacks are missing: lifecycle\.stop, lifecycle\.refresh, lifecycle\.verifyRestored/);
    assert.deepEqual(fs.readFileSync(csvPath), sourceBytes);
    assert.deepEqual(fs.readdirSync(sandbox), ["MonsterData.csv"],
      "validation happens before creating backup or fixture files");
  } finally {
    fs.rmSync(sandbox, { recursive: true, force: true });
  }
});

test("Issue #19 temporary CSV guard restores exact original bytes after success or probe failure", async () => {
  const fixture = require(path.join(root, "tests/monster_catalog_csv_fixture.cjs"));
  const sourceBytes = fs.readFileSync(path.join(root, "RootDesk/MyDesk/Data/MonsterData.csv"));
  const sandbox = fs.mkdtempSync(path.join(os.tmpdir(), "m1-monster-csv-guard-test-"));
  const csvPath = path.join(sandbox, "MonsterData.csv");

  try {
    for (const shouldThrow of [false, true]) {
      fs.writeFileSync(csvPath, sourceBytes);
      let manifestPath = "";
      const lifecycleStages = [];
      const runProbe = async (manifest) => {
        manifestPath = manifest.manifestPath;
        const activeBytes = fs.readFileSync(csvPath);
        assert.notDeepEqual(activeBytes, sourceBytes);
        assert.equal(path.dirname(manifest.backupPath), path.dirname(manifest.manifestPath));
        assert.ok(path.resolve(manifest.backupPath).startsWith(path.resolve(os.tmpdir())));
        if (shouldThrow) throw new Error("simulated probe failure");
        return "probe complete";
      };
      const lifecycle = {
        stop: async ({ stage }) => lifecycleStages.push(`stop:${stage}`),
        refresh: async ({ stage }) => lifecycleStages.push(`refresh:${stage}`),
        verifyRestored: async ({ originalBytes }) => {
          assert.deepEqual(fs.readFileSync(csvPath), originalBytes);
          lifecycleStages.push("verify:formal-catalog");
        },
      };

      if (shouldThrow) {
        await assert.rejects(fixture.withTemporaryMonsterCsv(runProbe, { csvPath, lifecycle, logger: () => {} }),
          /simulated probe failure/);
      } else {
        assert.equal(await fixture.withTemporaryMonsterCsv(runProbe, { csvPath, lifecycle, logger: () => {} }), "probe complete");
      }
      assert.deepEqual(fs.readFileSync(csvPath), sourceBytes);
      assert.equal(fs.existsSync(manifestPath), false, "successful cleanup removes its OS-temp backup");
      assert.deepEqual(lifecycleStages, [
        "stop:before-restore",
        "refresh:after-restore",
        "verify:formal-catalog",
        "stop:after-restore-verification",
      ]);
    }

    const abortController = new AbortController();
    let interruptedManifest = "";
    let continueAfterCancellation = false;
    let startProbe;
    const probeStarted = new Promise((resolve) => { startProbe = resolve; });
    const interruptionStages = [];
    const interruptedRun = fixture.withTemporaryMonsterCsv(async ({ manifestPath, signal }) => {
      interruptedManifest = manifestPath;
      startProbe();
      await new Promise((resolve, reject) => {
        signal.addEventListener("abort", () => {
          setTimeout(() => {
            continueAfterCancellation = true;
            reject(signal.reason);
          }, 20);
        }, { once: true });
      });
    }, {
      csvPath,
      signal: abortController.signal,
      lifecycle: {
        stop: async ({ stage }) => {
          interruptionStages.push(`stop:${stage}`);
          if (stage === "before-restore") {
            assert.equal(continueAfterCancellation, true, "Maker stops only after the probe acknowledges cancellation");
          }
        },
        refresh: async ({ stage }) => interruptionStages.push(`refresh:${stage}`),
        verifyRestored: async () => interruptionStages.push("verify:formal-catalog"),
      },
      logger: () => {},
    });
    await probeStarted;
    abortController.abort();
    await assert.rejects(interruptedRun, /interrupted by AbortSignal/);
    assert.deepEqual(fs.readFileSync(csvPath), sourceBytes);
    assert.equal(fs.existsSync(interruptedManifest), false, "interruption cleanup removes its OS-temp backup after verification");
    assert.deepEqual(interruptionStages, [
      "stop:before-restore",
      "refresh:after-restore",
      "verify:formal-catalog",
      "stop:after-restore-verification",
    ]);

    const cleanupAbortController = new AbortController();
    const beforeSigintListeners = process.listeners("SIGINT");
    const beforeSigtermListeners = process.listeners("SIGTERM");
    let cleanupManifest = "";
    const cleanupSignalStages = [];
    await assert.rejects(fixture.withTemporaryMonsterCsv(async (manifest) => {
      cleanupManifest = manifest.manifestPath;
      return "probe complete";
    }, {
      csvPath,
      signal: cleanupAbortController.signal,
      lifecycle: {
        stop: async ({ stage }) => {
          cleanupSignalStages.push(`stop:${stage}`);
          assert.ok(process.listeners("SIGINT").some((listener) => !beforeSigintListeners.includes(listener)),
            "SIGINT handler remains installed during Maker cleanup");
          assert.ok(process.listeners("SIGTERM").some((listener) => !beforeSigtermListeners.includes(listener)),
            "SIGTERM handler remains installed during Maker cleanup");
          if (stage === "before-restore") cleanupAbortController.abort();
        },
        refresh: async ({ stage }) => cleanupSignalStages.push(`refresh:${stage}`),
        verifyRestored: async () => cleanupSignalStages.push("verify:formal-catalog"),
      },
      logger: () => {},
    }), /interrupted by AbortSignal/);
    assert.deepEqual(fs.readFileSync(csvPath), sourceBytes);
    assert.equal(fs.existsSync(cleanupManifest), false, "a signal during cleanup still completes rollback");
    assert.deepEqual(process.listeners("SIGINT"), beforeSigintListeners, "SIGINT handler is removed after cleanup");
    assert.deepEqual(process.listeners("SIGTERM"), beforeSigtermListeners, "SIGTERM handler is removed after cleanup");
    assert.deepEqual(cleanupSignalStages, [
      "stop:before-restore",
      "refresh:after-restore",
      "verify:formal-catalog",
      "stop:after-restore-verification",
    ]);

    const loggerAbortController = new AbortController();
    let loggerFailureManifest = "";
    let startLoggerFailureProbe;
    const loggerFailureProbeStarted = new Promise((resolve) => { startLoggerFailureProbe = resolve; });
    const loggerFailureStages = [];
    const loggerFailureSigintListeners = process.listeners("SIGINT");
    const loggerFailureSigtermListeners = process.listeners("SIGTERM");
    const loggerFailureRun = fixture.withTemporaryMonsterCsv(async ({ manifestPath, signal }) => {
      loggerFailureManifest = manifestPath;
      startLoggerFailureProbe();
      await new Promise((resolve, reject) => {
        signal.addEventListener("abort", () => reject(signal.reason), { once: true });
      });
    }, {
      csvPath,
      signal: loggerAbortController.signal,
      lifecycle: {
        stop: async ({ stage }) => loggerFailureStages.push(`stop:${stage}`),
        refresh: async ({ stage }) => loggerFailureStages.push(`refresh:${stage}`),
        verifyRestored: async ({ originalBytes }) => {
          assert.deepEqual(fs.readFileSync(csvPath), originalBytes);
          loggerFailureStages.push("verify:formal-catalog");
        },
      },
      logger: (message) => {
        if (message.includes("acknowledged cancellation")) throw new Error("logger failed during cancellation acknowledgement");
      },
    });
    await loggerFailureProbeStarted;
    loggerAbortController.abort();
    let loggerFailure;
    await assert.rejects(loggerFailureRun, (error) => {
      loggerFailure = error;
      return error instanceof AggregateError && /cleanup failed; backup retained at/.test(error.message);
    });
    const loggerFailureDirectory = path.dirname(loggerFailureManifest);
    try {
      assert.deepEqual(fs.readFileSync(csvPath), sourceBytes, "logger failure does not interrupt CSV restoration");
      assert.deepEqual(fs.readFileSync(path.join(loggerFailureDirectory, "MonsterData.csv.original")), sourceBytes,
        "a logger failure retains the recovery backup");
      assert.ok(loggerFailure.errors.some((error) => /logger failed during cancellation acknowledgement/.test(error.message)),
        "the logger failure is reported as incomplete cleanup");
      assert.deepEqual(loggerFailureStages, [
        "stop:before-restore",
        "refresh:after-restore",
        "verify:formal-catalog",
        "stop:after-restore-verification",
      ], "all Maker cleanup callbacks run despite a logger exception");
      assert.deepEqual(process.listeners("SIGINT"), loggerFailureSigintListeners,
        "SIGINT handler is removed after logger failure cleanup");
      assert.deepEqual(process.listeners("SIGTERM"), loggerFailureSigtermListeners,
        "SIGTERM handler is removed after logger failure cleanup");
    } finally {
      if (fixture.insideTempDirectory(loggerFailureDirectory)) fs.rmSync(loggerFailureDirectory, { recursive: true, force: true });
    }

    const pendingAbortController = new AbortController();
    let pendingManifest = "";
    let startPendingProbe;
    const pendingProbeStarted = new Promise((resolve) => { startPendingProbe = resolve; });
    const pendingCleanupStages = [];
    const pendingRun = fixture.withTemporaryMonsterCsv(async ({ manifestPath }) => {
      pendingManifest = manifestPath;
      startPendingProbe();
      return new Promise(() => {});
    }, {
      csvPath,
      signal: pendingAbortController.signal,
      probeCancellationTimeoutMs: 10,
      lifecycleTimeoutMs: 100,
      lifecycle: {
        stop: async ({ stage }) => pendingCleanupStages.push(`stop:${stage}`),
        refresh: async ({ stage }) => pendingCleanupStages.push(`refresh:${stage}`),
        verifyRestored: async ({ originalBytes }) => {
          assert.deepEqual(fs.readFileSync(csvPath), originalBytes);
          pendingCleanupStages.push("verify:formal-catalog");
        },
      },
      logger: () => {},
    });
    await pendingProbeStarted;
    pendingAbortController.abort();
    let pendingCleanupError;
    await assert.rejects(pendingRun, (error) => {
      pendingCleanupError = error;
      return error instanceof AggregateError && /cleanup failed; backup retained at/.test(error.message);
    });
    const retainedDirectory = path.dirname(pendingManifest);
    try {
      assert.equal(fixture.insideTempDirectory(retainedDirectory), true, "incomplete rollback retains an OS-temp backup");
      assert.deepEqual(fs.readFileSync(csvPath), sourceBytes, "bounded recovery restores formal CSV bytes");
      assert.deepEqual(fs.readFileSync(path.join(retainedDirectory, "MonsterData.csv.original")), sourceBytes,
        "incomplete cancellation preserves the original backup for recovery");
      assert.ok(pendingCleanupError.errors.some((error) => /did not acknowledge AbortSignal/.test(error.message)),
        "a timed-out callback is reported as incomplete cleanup");
      assert.deepEqual(pendingCleanupStages, [
        "stop:before-restore",
        "refresh:after-restore",
        "verify:formal-catalog",
        "stop:after-restore-verification",
      ]);
    } finally {
      if (fixture.insideTempDirectory(retainedDirectory)) fs.rmSync(retainedDirectory, { recursive: true, force: true });
    }
  } finally {
    fs.rmSync(sandbox, { recursive: true, force: true });
  }
});

test("Issue #19 server runtime probes do not bypass BattleSession settlement state", () => {
  const serverProbePaths = [
    "tests/six_vs_six_runtime_probe.lua",
    "tests/deployment_runtime_probe.lua",
    "tests/attack_execution_runtime_probe.lua",
    "tests/attack_clock_runtime_probe.lua",
    "tests/tank_contact_runtime_probe.lua",
    "tests/shooter_runtime_probe.lua",
    "tests/targeting_crowding_runtime_probe.lua",
    "tests/six_vs_six_batch_outcome_probe.lua",
    "tests/six_vs_six_full_battle_probe.lua",
    "tests/controlled_scenario_runtime_probe.lua",
    "tests/monster_catalog_identity_runtime_probe.lua",
    "tests/monster_catalog_restored_runtime_probe.lua",
  ];
  const forbidden = /session\._T|session\.(?:Phase|Result|PlayerAlive|EnemyAlive|InitialPlayerAlive|InitialEnemyAlive)\s*=(?!=)|table\.remove\s*\(|session:(?:RemoveDeployedUnit|SpawnUnit|SpawnConfiguredUnit|QueueDamage|QueueKnockback|ApplyPendingKnockbacks|ResolveDamageBatch|DetermineResult|EvaluateResult|EnterResult|ForceResult|SetResult)\s*\(/;

  for (const probePath of serverProbePaths) {
    const probe = read(probePath);
    assert.doesNotMatch(probe, forbidden, `${probePath} must observe the public session seam without mutating or staging settlement`);
  }

  for (const [probePath, tag] of [
    ["tests/deployment_runtime_probe.lua", "DeploymentProbe"],
    ["tests/controlled_scenario_runtime_probe.lua", "ControlledScenarioProbe"],
  ]) {
    const probe = read(probePath);
    assert.match(probe, /local runOk, runDetail = pcall\(function\(\)/,
      `${probePath} must capture setup and execution exceptions`);
    assert.ok(probe.indexOf("local runOk, runDetail = pcall(function()")
      < probe.indexOf('_EntityService:GetEntityByPath("/maps/map01")'),
    `${probePath} must protect the missing-map/session path too`);
    assert.match(probe, new RegExp(`\\[M1\\]\\[${tag}\\] FAILURES=`),
      `${probePath} must emit a terminal failure marker after exceptions`);
  }
});
