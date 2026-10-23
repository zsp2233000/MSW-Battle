const assert = require("node:assert/strict");
const fs = require("node:fs");
const test = require("node:test");
const { MapBuilder } = require("../.agents/skills/msw-general/scripts/map/msw_map_builder.cjs");

test("matched battlefield owns the formal viewer presentation", () => {
  const map = MapBuilder.read("map/matchprobe.map");
  const root = map.listEntities().find((entity) => entity.name === "matchprobe");
  assert.ok(root.componentNames.includes("script.BattleView"));
  assert.equal(map.component("matchprobe", "script.BattleSession").RequireMatchedFormations, true);
  assert.equal(map.getTileMapMode(), 1);

  const source = fs.readFileSync("RootDesk/MyDesk/Combat/BattleView.mlua", "utf8");
  assert.match(source, /session\.HomeProfile/);
  assert.match(source, /session\.AwayProfile/);
  assert.doesNotMatch(source, /BattleViewPrototype|battleviewprototype|IsPrototype/);
  assert.match(source, /SpawnByModelId\("battleviewvisual"/);
  assert.match(source, /SpawnByModelId\("battleviewavatar"/);
  assert.doesNotMatch(source, /Color\(1, 0, 0, 1\)[\s\S]*unit\.Faction == "ENEMY"/);

  for (const file of [
    "RootDesk/MyDesk/Combat/BattleUnit.mlua",
    "RootDesk/MyDesk/Combat/BattleHitEffectPresentation.mlua",
    "RootDesk/MyDesk/Combat/BattleUIController.mlua",
  ]) {
    assert.doesNotMatch(fs.readFileSync(file, "utf8"), /BattleViewPrototype/, file);
  }
});
