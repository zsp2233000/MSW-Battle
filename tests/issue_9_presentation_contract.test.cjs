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
    for (const field of ["StandAnimationRUID", "MoveAnimationRUID", "HitAnimationRUID", "DieAnimationRUID", "OnHitSoundRUID"]) {
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
  assert.match(unit, /self\.HitAnimationRUID = profile\.HitAnimationRUID/);
  assert.match(unit, /self\.AttackSoundRUID = profile\.AttackSoundRUID/);
  assert.match(unit, /session:EmitPresentation\("TARGET_HIT", event\.AttackerEntity, self\.Entity, event\.TotalDamage\)/);
  assert.match(read("TankContactAttack.mlua"), /session:EmitPresentation\("TANK_CONTACT_HIT", self\.Entity, defender, self\.AttackDamage\)/);
});

test("tank contact cannot request a hit effect, even with an assigned RUID", () => {
  const unit = read("BattleUnit.mlua");
  const resolver = unit.match(/method void ApplyResolvedDamage\([^\n]+\)([\s\S]*?)\n\s*end\s*\n\s*@ExecSpace\("ServerOnly"\)\s+method void ConfigurePresentation/);
  assert.ok(resolver, "BattleUnit must present only successfully applied damage");
  assert.match(resolver[1], /attackerUnit\.UnitKind ~= "TANK"/);
  assert.match(resolver[1], /hitEffectRUID = attackerUnit:GetHitEffectRUID\(\)/);
  assert.match(resolver[1], /presentation:PlayHitEffect\(hitEffectRUID\)/);
  assert.match(read("BattleHitEffectPresentation.mlua"), /@ExecSpace\("Multicast"\)\s+method void PlayHitEffect\(string effectRUID\)/);
});

test("each successful same-frame hit keeps its damage event and target sound", () => {
  const session = read("BattleSession.mlua");
  const resolver = session.match(/method void ResolveDamageBatch\(\)([\s\S]*?)\n\s*end\s*\n\s*method void NotifyDeath/);
  assert.ok(resolver, "BattleSession must resolve queued hits");
  assert.match(resolver[1], /for _, hit in ipairs\(pending\)/);
  assert.match(resolver[1], /unit:ApplyResolvedDamage\(hit\.amount, hit\.attacker, not isTankContact\)/);
  assert.doesNotMatch(resolver[1], /found\.amount\s*=|resolved\s*=/);

  const unit = read("BattleUnit.mlua");
  assert.match(unit, /session:EmitPresentation\("DAMAGE", attacker, self\.Entity, amount\)/);
  assert.match(unit, /self\.OnHitSoundSerial = self\.OnHitSoundSerial \+ 1[\s\S]*?self:PlayCombatSound\(self\.OnHitSoundRUID\)/);
  assert.match(unit, /@ExecSpace\("Multicast"\)\s+method void PlayCombatSound\(string soundRUID\)/);
  assert.doesNotMatch(unit, /lastPresentation(?:Attack|Damage)Serial/);
  for (const attack of ["AssaultAttack.mlua", "ShooterAttack.mlua", "TankContactAttack.mlua"]) {
    assert.match(read(attack), /unit:PlayCombatSound\(unit\.AttackSoundRUID\)/, `${attack} must emit attack sound at the server-confirmed attack event`);
  }
});

test("knockback uses collision-aware kinematic velocity", () => {
  const unit = read("BattleUnit.mlua");
  const start = unit.indexOf("method void AdvanceKnockback(number delta)");
  const end = unit.indexOf("handler HandleHitEvent", start);
  assert.ok(start >= 0 && end > start, "BattleUnit must advance knockback in its server simulation");
  const advance = unit.slice(start, end);
  assert.match(advance, /kinematic\.MoveVelocity = Vector2\(velocityX, velocityY\)/);
  assert.match(advance, /kinematic\.SpeedFactor/);
  assert.doesNotMatch(advance, /SetWorldPosition/);
});

test("world HP fill uses synced HP and cached entity references", () => {
  const bar = read("BattleHPBar.mlua");
  assert.match(bar, /battleUnit\.Hp \/ battleUnit\.MaxHp/);
  assert.match(bar, /if not isvalid\(self\._T\.battleUnit\) then/);
  assert.match(bar, /if not isvalid\(self\._T\.fillTransform\) then/);
  assert.match(bar, /fillScale\.x = self\._T\.fillFullScaleX \* ratio/);
});
