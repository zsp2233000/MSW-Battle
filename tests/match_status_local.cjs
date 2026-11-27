// Run: node tests/match_status_local.cjs | npm exec --yes --package=fengari-node-cli@0.1.0 -- fengari -
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const read = (path) => readFileSync(join(__dirname, path), 'utf8').replace(/\r\n/g, '\n');
const { participantSideLua } = require('./participant_side_source.cjs');
const load = (name) => read(`../RootDesk/MyDesk/Matchmaking/${name}.mlua`)
  .replace(/^@Logic\nscript .* extends Logic\n/, `_${name} = { _T = {} }\n`)
  .replace(/^    @\w+\([^\n]*\)\n/gm, '')
  .replace(/^    property \w+ (\w+ = .+)$/gm, `_${name}.$1`)
  .replace(/^    (?:method \w+|handler) (\w+)\(([^)]*)\)$/gm, (_, method, params) =>
    `function _${name}:${method}(${params.replace(/\b\w+ (\w+)/g, '$1')})`)
  .replace(/\nend\s*$/, '\n');
process.stdout.write(`local ok, failure = xpcall(function()\n${participantSideLua()}\n${load('MatchFlowState')}\n${load('MatchFlow')}\n${load('MatchQueueNative')}
do\n${read('match_status_rules.lua')}\nend\ndo\n${read('match_status_server_rules.lua')}\nend
end, debug.traceback)
if not ok then io.stderr:write(failure, "\\n"); os.exit(1) end\n`);
