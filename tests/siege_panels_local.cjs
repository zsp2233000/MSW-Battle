// Maker-free check of the attack panel and the team preview rules (#117, #118). Run (use `set -o pipefail` in Bash):
//   node tests/siege_panels_local.cjs | npm exec --yes --package=fengari-node-cli@0.1.0 -- fengari -
// The production Lua bodies of FactionWarAttack, FactionWarMap, FactionWarTeam, FactionWarUI and FactionWarTownDocument run against fakes
// (board read, gates, players, RPC targets). This is not Maker; the Maker client probes cover the real panels.
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const read = (path) => readFileSync(join(__dirname, path), 'utf8').replace(/\r\n/g, '\n');
const load = (name) => read(`../RootDesk/MyDesk/Formations/${name}.mlua`)
  .replace(/^@(?:Logic|Component)\nscript .* extends (?:Logic|Component)\n/, `_${name} = { _T = {} }\n`)
  .replace(/^    @\w+\([^\n]*\)\n/gm, '')
  .replace(/^    (?:@\w+ )?property \w+ (\w+ = .+)$/gm, `_${name}.$1`)
  .replace(/^    (?:method \w+ |handler )(\w+)\(([^)]*)\)$/gm, (_, method, params) =>
    `function _${name}:${method}(${params.replace(/\b\w+ (\w+)/g, '$1')})`)
  .replace(/\nend\s*$/, '\n');
process.stdout.write(`local ok, failure = xpcall(function()
${['FactionWarTownDocument', 'FactionWarAttack', 'FactionWarMap', 'FactionWarTeam', 'FactionWarUI'].map(load).join('\n')}
do\n${read('siege_panels_rules.lua')}\nend
end, debug.traceback)
if not ok then io.stderr:write(failure, "\\n"); os.exit(1) end\n`);
