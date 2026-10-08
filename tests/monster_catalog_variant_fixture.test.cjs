const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const { createTemporaryFixtureBuffer, parseMonsterCsv } = require("./monster_catalog_csv_fixture.cjs");

test("same-type catalog fixture varies combat values without changing shared assets or the source bytes", () => {
  const source = fs.readFileSync(path.join(__dirname, "../RootDesk/MyDesk/Data/MonsterData.csv"));
  const before = Buffer.from(source);
  const fixture = createTemporaryFixtureBuffer(source, { MaxHp: 650, MoveSpeed: 0.7, AttackDamage: 25,
    AttackIntervalSeconds: 1.3, AttackRange: 0.8, ContactCooldownSeconds: 1.3 });
  const rows = parseMonsterCsv(fixture).records;
  const primary = rows.find(row => row.MonsterId === "monster_tank");
  const variant = rows.find(row => row.MonsterId === "probe_tank_variant");
  assert.equal(primary.MaxHp, "500");
  assert.equal(variant.MaxHp, "650");
  assert.equal(variant.AttackDamage, "25");
  assert.equal(variant.MoveSpeed, "0.7");
  assert.equal(variant.AttackIntervalSeconds, "1.3");
  assert.equal(variant.AttackRange, "0.8");
  assert.equal(variant.ContactCooldownSeconds, "1.3");
  assert.equal(primary.MonsterType, variant.MonsterType);
  for (const field of Object.keys(primary).filter(field => field.endsWith("RUID"))) {
    assert.equal(variant[field], primary[field]);
  }
  assert.deepEqual(source, before);
});

test("variant fixture rejects identity overrides and values that would corrupt CSV cells", () => {
  const source = fs.readFileSync(path.join(__dirname, "../RootDesk/MyDesk/Data/MonsterData.csv"));
  for (const overrides of [{ MonsterId: "bad" }, { MaxHp: NaN }, { AttackDamage: "1,2" }]) {
    assert.throws(() => createTemporaryFixtureBuffer(source, overrides));
  }
});
