// Maker-free check of the production absent-side rules (ADR 0017, #120). Run (use `set -o pipefail` in Bash):
//   node tests/matched_absent_local.cjs | npm exec --yes --package=fengari-node-cli@0.1.0 -- fengari -
// The production Lua bodies of MatchFlowState, MatchFlow, FormationHandoff and MatchedBattle run with a fake room, fake storage and a fake clock.
// This is not Maker and not the native service; the Maker probe matched_absent_e2e_runtime_probe.lua covers the real room.
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const read = (path) => readFileSync(join(__dirname, path), 'utf8').replace(/\r\n/g, '\n');
const load = (dir, name) => read(`../RootDesk/MyDesk/${dir}/${name}.mlua`)
  .replace(/^@(?:Logic|Component)\nscript .* extends (?:Logic|Component)\n/, `_${name} = { _T = {} }\n`)
  .replace(/^    @\w+\([^\n]*\)\n/gm, '')
  .replace(/^    (?:@\w+ )?property \w+ (\w+ = .+)$/gm, `_${name}.$1`)
  .replace(/^    (?:method \w+ |handler )(\w+)\(([^)]*)\)$/gm, (_, method, params) =>
    `function _${name}:${method}(${params.replace(/\b\w+ (\w+)/g, '$1')})`)
  .replace(/\nend\s*$/, '\n');
process.stdout.write(`local ok, failure = xpcall(function()
${load('Matchmaking', 'MatchFlowState')}
${load('Matchmaking', 'MatchFlow')}
${load('Formations', 'FormationHandoff')}
${load('Matchmaking', 'MatchedBattle')}
do\n${read('matched_absent_rules.lua')}\nend
end, debug.traceback)
if not ok then io.stderr:write(failure, "\\n"); os.exit(1) end\n`);
