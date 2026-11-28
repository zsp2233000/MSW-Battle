// Maker-free check of the team preview and the siege panel rules (#118, #123). Run (use `set -o pipefail` in Bash):
//   node tests/siege_panels_local.cjs | npm exec --yes --package=fengari-node-cli@0.1.0 -- fengari -
// The production Lua bodies of FactionWarMap, FactionWarTeam, FactionWarUI, FactionWarTownDocument and MatchFlowState run against fakes
// (board read, gates, players, RPC targets). This is not Maker; the Maker client probes cover the real panels.
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
Vector2 = function(x, y) return { x = x, y = y } end
${['FactionWarTownDocument', 'FactionWarMap', 'FactionWarTeam', 'FactionWarUI'].map(name => load(name)).concat(load('MatchFlowState', 'Matchmaking')).join('\n')}
do\n${read('siege_panels_rules.lua')}\nend
end, debug.traceback)
if not ok then io.stderr:write(failure, "\\n"); os.exit(1) end\n`);
