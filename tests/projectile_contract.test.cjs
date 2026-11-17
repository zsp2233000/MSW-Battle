const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const read = p => fs.readFileSync(path.join(__dirname, '..', p), 'utf8');

function monsterRows() {
  const [header, ...rows] = read('RootDesk/MyDesk/Data/MonsterData.csv')
    .replace(/^﻿/, '').trim().split(/\r?\n/).map(line => line.split(','));
  return { header, rows: rows.map(cells => Object.fromEntries(header.map((name, i) => [name, cells[i]]))) };
}

test('projectile columns are required and optional per row', () => {
  const { header, rows } = monsterRows();
  const catalog = read('RootDesk/MyDesk/Combat/MonsterCatalog.mlua');
  const required = catalog.match(/local requiredColumns = \{([\s\S]*?)\n        \}/)[1];
  for (const field of ['ProjectileRUID', 'ProjectileSpeed']) {
    assert.ok(header.includes(field), `missing ${field}`);
    assert.ok(required.includes(`"${field}"`), `${field} must be a required column`);
  }
  assert.match(catalog, /ProjectileRUID = ResourceType\.AnimationClip/);
  assert.match(catalog, /ProjectileRUID = true/);
  for (const row of rows) {
    const hasProjectile = row.ProjectileRUID !== '';
    if (hasProjectile) {
      assert.notEqual(row.MonsterType, 'TANK', `${row.MonsterId} tank cannot fire projectiles`);
      assert.ok(Number(row.ProjectileSpeed) > 0, `${row.MonsterId} needs a positive ProjectileSpeed`);
    }
  }
});

test('the three pixies fire their ball clip while instant shooters stay blank', () => {
  const { rows } = monsterRows();
  const byId = Object.fromEntries(rows.map(row => [row.MonsterId, row]));
  const balls = {
    monster_moon_pixie: '0cd8e0bdda0b41a49a8a8eb89d77291c',
    monster_sun_pixie: 'a8027b68b20046db93b19fd53331fa99',
    monster_star_pixie: '3123b59475a148a49f940749531c5fad',
  };
  for (const [id, ruid] of Object.entries(balls)) assert.equal(byId[id].ProjectileRUID, ruid, id);
  for (const id of ['monster_shooter', 'monster_monkey']) assert.equal(byId[id].ProjectileRUID, '', id);
});

test('projectiles are owned by the attacker and resolve through the native hit pipeline', () => {
  const composition = read('RootDesk/MyDesk/Combat/BattleAttackComposition.mlua');
  const single = read('RootDesk/MyDesk/Combat/SingleTargetAttack.mlua');
  const presentation = read('RootDesk/MyDesk/Combat/BattleProjectilePresentation.mlua');
  const session = read('RootDesk/MyDesk/Combat/BattleSession.mlua');

  assert.match(composition, /method void LaunchProjectile\(/);
  assert.match(composition, /method void AdvanceProjectiles\(number delta\)/);
  assert.match(composition, /method void ClearProjectiles\(\)/);
  const cancel = composition.match(/method void Cancel\(\)([\s\S]*?)\n    end/)[1];
  assert.match(cancel, /ClearProjectiles\(\)/, 'cancelling the actor discards its projectiles');
  const advance = composition.match(/method void Advance\(number delta\)([\s\S]*?)\n    end/)[1];
  assert.match(advance, /AdvanceProjectiles\(delta\)/);
  const engage = composition.match(/method void TryEngage\(Entity target, boolean targetInRange\)([\s\S]*?)\n    end/)[1];
  assert.match(engage, /if self:UsesProjectile\(\) then resolveDelay = profile\.AttackEffectDelaySeconds or 0 end/,
    'projectiles launch on AttackEffectFrame instead of AttackDamageFrame');

  assert.match(single, /method void ResolveProjectileArrival\(Entity target\)/);
  assert.match(single, /self:Attack\(/, 'arrival damage uses the native Attack to Hit pipeline');
  const arrival = single.match(/method void ResolveProjectileArrival\(Entity target\)([\s\S]*?)\n    end/)[1];
  assert.doesNotMatch(arrival, /\.Hp\s*=|QueueDamage/, 'arrival never subtracts HP directly');

  assert.match(presentation, /@ExecSpace\("Multicast"\)\s*\n\s*method void LaunchProjectile\(/);
  assert.match(presentation, /@ExecSpace\("Multicast"\)\s*\n\s*method void EndProjectile\(/);
  assert.match(session, /AddComponent\("script\.BattleProjectilePresentation"\)/);
});

test('mirrored viewers present projectiles with the same reflection as unit visuals', () => {
  const presentation = read('RootDesk/MyDesk/Combat/BattleProjectilePresentation.mlua');
  assert.match(presentation, /GetLocalFaction\(\)/);
  assert.match(presentation, /_FormationMapLayout:MirrorX\(/);
  assert.doesNotMatch(presentation, /AttackComponent|:Attack\(|QueueDamage|\.Hp\b/, 'presentation only draws');
});
