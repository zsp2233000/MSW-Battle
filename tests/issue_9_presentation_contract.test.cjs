const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const combat = path.resolve(__dirname, "../RootDesk/MyDesk/Combat");
const read = (name) => fs.readFileSync(path.join(combat, name), "utf8");

test("MonsterData assets reach the owning unit and semantic hit events", () => {
  const csv = fs.readFileSync(path.resolve(combat, "../Data/MonsterData.csv"), "utf8").trim().split(/\r?\n/);
  const headers = csv[0].split(",");
  const rows = csv.slice(1).map((line) => Object.fromEntries(line.split(",").map((value, index) => [headers[index], value])));
  assert.equal(rows.length, 3);
  for (const row of rows) {
    for (const field of ["StandAnimationRUID", "MoveAnimationRUID", "HurtAnimationRUID", "DieAnimationRUID", "HurtSoundRUID"]) {
      assert.ok(row[field], `${row.MonsterId} needs ${field}`);
    }
    if (row.MonsterType !== "TANK") {
      for (const field of ["AttackAnimationRUID", "HitEffectRUID", "AttackSoundRUID"]) {
        assert.ok(row[field], `${row.MonsterId} needs ${field}`);
      }
    }
  }

  const session = read("BattleSession.mlua");
  const unit = read("BattleUnit.mlua");
  assert.match(session, /unit:SetMonsterIdentity\(profile\.MonsterId, profile\.MonsterName, profile\.HitEffectRUID\)/);
  assert.match(session, /unit:ConfigurePresentation\(profile\)/);
  assert.match(unit, /self\.HurtAnimationRUID = profile\.HurtAnimationRUID/);
  assert.match(unit, /self\.AttackSoundRUID = profile\.AttackSoundRUID/);
  assert.match(unit, /session:EmitPresentation\("TARGET_HIT", event\.AttackerEntity, self\.Entity, event\.TotalDamage\)/);
  assert.match(read("BattleHitEffectPresentation.mlua"), /@ExecSpace\("Multicast"\)\s+method void PlayHitEffect\(string effectRUID\)/);
});

test("each successful hit keeps its damage event and target sound", () => {
  const unit = read("BattleUnit.mlua");
  assert.match(unit, /session:EmitPresentation\("DAMAGE", attacker, self\.Entity, amount\)/);
  assert.match(unit, /self\.OnHitSoundSerial = self\.OnHitSoundSerial \+ 1[\s\S]*?self:PlayCombatSound\(self\.HurtSoundRUID\)/);
  assert.match(unit, /@ExecSpace\("Multicast"\)\s+method void PlayCombatSound\(string soundRUID\)/);
  assert.doesNotMatch(unit, /lastPresentation(?:Attack|Damage)Serial/);
});

test("attack effects are optional clips dispatched once at attack start on the owner's visual", () => {
  const { parseMonsterCsv } = require("./monster_catalog_csv_fixture.cjs");
  const csv = parseMonsterCsv(fs.readFileSync(path.resolve(combat, "../Data/MonsterData.csv")));
  assert.equal(csv.header[csv.header.indexOf("HitEffectRUID") - 1], "AttackEffectRUID");
  for (const row of csv.records) assert.equal(row.AttackEffectRUID, "");

  const catalog = read("MonsterCatalog.mlua");
  assert.match(catalog, /local requiredColumns = \{[\s\S]*?"AttackEffectRUID"/);
  assert.match(catalog, /local optionalAssetFields = \{[\s\S]*?AttackEffectRUID = true/);
  assert.match(catalog, /AttackEffectRUID = ResourceType\.AnimationClip/);

  const attack = read("BattleAttackComposition.mlua");
  const start = attack.slice(attack.indexOf("method void PublishAttackStart("), attack.indexOf("method number GetTargetDirection("));
  assert.equal((attack.match(/presentation:PlayAttackEffect\(/g) || []).length, 1);
  assert.match(start, /unit:FaceTarget\(target\)[\s\S]*?presentation:PlayAttackEffect\(self\._T\.profile\.AttackEffectRUID\)/);
  const effect = read("BattleHitEffectPresentation.mlua");
  assert.match(effect, /@ExecSpace\("Multicast"\)\s+method void PlayAttackEffect\(string effectRUID\)[\s\S]*?self:PlayAttachedEffect\(effectRUID, "ATTACK"\)/);
  assert.match(effect, /self:PlayAttachedEffect\(effectRUID, "HIT"\)/);
  assert.match(effect, /local target = self\.Entity[\s\S]*?target = view:GetVisual\(self\.Entity\)/);
  assert.match(effect, /if effectKind == "ATTACK" then options = \{ SyncFlip = true \} end/);
  assert.match(effect, /PlayEffectAttached\(effectRUID, target, Vector3\(0, 0, 0\), 0, Vector3\(1, 1, 1\), false, options\)/);
  assert.match(effect, /if serial == 0 then[\s\S]*?CREATE_FAILED/);
});
