const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const root = path.resolve(__dirname, "..");

function read(relativePath) {
  return fs.readFileSync(path.join(root, relativePath), "utf8");
}

// This harness exercises the externally observable Issue #3 rules without depending on Maker state.
function createContactScenario(enemyPositions) {
  const rules = {
    damage: 40,
    cooldown: 2.0,
    contactSize: { x: 1.2, y: 1.2 },
    knockback: 0.8,
    bounds: { minX: -5.5, maxX: 3.5, minY: -3.5, maxY: 1.5 },
  };
  const state = {
    phase: "BATTLE",
    tank: { x: 0, y: 0, hp: 500 },
    enemies: enemyPositions.map((position, index) => ({
      id: `enemy-${index + 1}`,
      x: position.x,
      y: position.y,
      hp: 220,
      alive: true,
      stunned: false,
      cooldown: 0,
    })),
    events: [],
  };

  function clamp(value, minimum, maximum) {
    return Math.max(minimum, Math.min(maximum, value));
  }

  function placeEnemy(id, x, y) {
    const enemy = state.enemies.find((candidate) => candidate.id === id);
    enemy.x = x;
    enemy.y = y;
  }

  function contact(elapsed) {
    for (const enemy of state.enemies) enemy.cooldown = Math.max(0, enemy.cooldown - elapsed);
    if (state.phase !== "BATTLE") return;
    for (const enemy of state.enemies) {
      const overlaps =
        Math.abs(enemy.x - state.tank.x) <= rules.contactSize.x / 2 &&
        Math.abs(enemy.y - state.tank.y) <= rules.contactSize.y / 2;
      if (!enemy.alive || !overlaps || enemy.cooldown > 0) continue;

      enemy.hp -= rules.damage;
      enemy.cooldown = rules.cooldown;
      state.events.push({ type: "TANK_CONTACT_HIT", target: enemy.id, amount: rules.damage });
      state.events.push({ type: "DAMAGE", target: enemy.id, amount: rules.damage });

      let dx = enemy.x - state.tank.x;
      let dy = enemy.y - state.tank.y;
      const length = Math.sqrt(dx * dx + dy * dy) || 1;
      if (length === 1 && dx === 0 && dy === 0) dx = 1;
      const directionLength = Math.sqrt(dx * dx + dy * dy) || 1;
      enemy.x = clamp(enemy.x + (dx / directionLength) * rules.knockback, rules.bounds.minX, rules.bounds.maxX);
      enemy.y = clamp(enemy.y + (dy / directionLength) * rules.knockback, rules.bounds.minY, rules.bounds.maxY);
    }
  }

  return { rules, state, contact, placeEnemy };
}

test("Tank contact applies fixed damage once, then again only after 2 seconds", () => {
  const scenario = createContactScenario([{ x: 0.4, y: 0 }]);
  const enemy = scenario.state.enemies[0];
  scenario.contact(0);
  assert.equal(enemy.hp, 180);
  const tankPositionAfterFirstHit = { x: scenario.state.tank.x, y: scenario.state.tank.y };

  scenario.placeEnemy(enemy.id, 0.4, 0);
  scenario.contact(1.99);
  assert.equal(enemy.hp, 180);
  scenario.placeEnemy(enemy.id, 0.4, 0);
  scenario.contact(0.02);
  assert.equal(enemy.hp, 140);
  assert.deepEqual({ x: scenario.state.tank.x, y: scenario.state.tank.y }, tankPositionAfterFirstHit);
});

test("Tank contact damages every overlapping enemy with independent cooldowns", () => {
  const scenario = createContactScenario([
    { x: 0.4, y: 0.4 },
    { x: 0.4, y: -0.4 },
  ]);
  scenario.contact(0);
  assert.deepEqual(scenario.state.enemies.map((enemy) => enemy.hp), [180, 180]);
  assert.equal(scenario.state.events.filter((event) => event.type === "DAMAGE").length, 2);

  for (const enemy of scenario.state.enemies) scenario.placeEnemy(enemy.id, 0.4, enemy.id === "enemy-1" ? 0.4 : -0.4);
  scenario.contact(2.0);
  assert.deepEqual(scenario.state.enemies.map((enemy) => enemy.hp), [140, 140]);
  assert.ok(scenario.state.enemies.every((enemy) => enemy.stunned === false));
});

test("Tank contact knocks back only the enemy and clamps the destination", () => {
  const scenario = createContactScenario([{ x: 3.4, y: 0 }]);
  const enemy = scenario.state.enemies[0];
  scenario.state.tank.x = 3.0;
  const tankPosition = { x: scenario.state.tank.x, y: scenario.state.tank.y };
  scenario.contact(0);

  assert.equal(enemy.x, 3.5);
  assert.equal(enemy.y, 0);
  assert.deepEqual({ x: scenario.state.tank.x, y: scenario.state.tank.y }, tankPosition);
  assert.ok(enemy.x >= scenario.rules.bounds.minX && enemy.x <= scenario.rules.bounds.maxX);
  assert.equal(enemy.stunned, false);
});

test("Tank contact emits semantic hit/damage events and stops after RESULT", () => {
  const scenario = createContactScenario([{ x: 0.4, y: 0 }]);
  const enemy = scenario.state.enemies[0];
  scenario.contact(0);
  assert.deepEqual(scenario.state.events.slice(0, 2), [
    { type: "TANK_CONTACT_HIT", target: "enemy-1", amount: 40 },
    { type: "DAMAGE", target: "enemy-1", amount: 40 },
  ]);

  scenario.state.phase = "RESULT";
  scenario.placeEnemy(enemy.id, 0.4, 0);
  const eventCount = scenario.state.events.length;
  scenario.contact(10);
  assert.equal(enemy.hp, 180);
  assert.equal(scenario.state.events.length, eventCount);
});

test("Tank behavior contract stays aligned with the configured MSW scripts", () => {
  const session = read("RootDesk/MyDesk/Combat/BattleSession.mlua");
  const contact = read("RootDesk/MyDesk/Combat/TankContactAttack.mlua");
  assert.match(session, /TankMaxHp = 500/);
  assert.match(session, /TankMoveSpeed = 1\.1/);
  assert.match(session, /TankContactDamage = 40/);
  assert.match(session, /TankContactCooldown = 2\.0/);
  assert.match(session, /TankKnockbackDistance = 0\.8/);
  assert.match(contact, /self:AttackFrom\(self\.ContactSize/);
  assert.match(contact, /targetCooldowns/);
});
