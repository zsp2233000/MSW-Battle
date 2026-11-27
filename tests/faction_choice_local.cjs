// Maker-free check of the faction choice screen's rules (#126). Run (use `set -o pipefail` in Bash):
//   node tests/faction_choice_local.cjs | npm exec --yes --package=fengari-node-cli@0.1.0 -- fengari -
// The production Lua bodies of FactionWarTownDocument and FactionWarUI run against fake nodes and a fake FactionWar. This is not Maker; the Maker client
// probe (faction_war_faction_choice_client_runtime_probe.lua) clicks the real buttons.
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
${['FactionWarTownDocument', 'FactionWarUI'].map(name => load(name)).join('\n')}
do\n${read('faction_choice_rules.lua')}\nend
end, debug.traceback)
if not ok then io.stderr:write(failure, "\\n"); os.exit(1) end\n`);
