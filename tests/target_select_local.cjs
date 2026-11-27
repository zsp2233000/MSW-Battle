// Maker-free check of the world map's target selection (#124). Run (use `set -o pipefail` in Bash):
//   node tests/target_select_local.cjs | npm exec --yes --package=fengari-node-cli@0.1.0 -- fengari -
// The production Lua bodies of FactionWarAttack (SelectFor, AttackFor), FactionWarMap (WatchMap and the push) and FactionWarMapUI (ShowSelect, Pick,
// ConfirmAttack, ShowAttackResult, the board, the confirmation window and (#127) the message window with the NPC guard) and both town NPC handlers run against fakes (board read, gates, players, UI nodes, RPC targets).
// This is not Maker; tests/target_select_client_runtime_probe.lua covers the real window and its buttons.
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const read = (path) => readFileSync(join(__dirname, path), 'utf8').replace(/\r\n/g, '\n');
const load = (name, folder = 'Formations') => read(`../RootDesk/MyDesk/${folder}/${name}.mlua`)
  .replace(/^@(?:Logic|Component)\nscript .* extends (?:Logic|Component)\n/, `_${name} = { _T = {} }\n`)
  .replace(/^    @\w+\([^\n]*\)\n/gm, '')
  .replace(/^    (?:@\w+ )?property \w+ (\w+ = .+)$/gm, `_${name}.$1`)
  .replace(/^    (?:method \w+ |handler )(\w+)\(([^)]*)\)$/gm, (_, method, params) =>
    `function _${name}:${method}(${params.replace(/\b\w+ (\w+)/g, '$1')})`)
  .replace(/\nend\s*$/, '\n');
process.stdout.write(`local ok, failure = xpcall(function()
Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
${['FactionWarTownDocument', 'FactionWarAttack', 'FactionWarMap', 'FactionWarMapUI', 'FactionWarNpc', 'FactionWarLobbyNpc'].map(name => load(name)).join('\n')}
do\n${read('target_select_rules.lua')}\nend
end, debug.traceback)
if not ok then io.stderr:write(failure, "\\n"); os.exit(1) end\n`);
