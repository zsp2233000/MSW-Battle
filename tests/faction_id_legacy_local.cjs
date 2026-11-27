// ADR 0018 / #125: every place that reads a stored faction value must accept the retired colour ids (RED / BLUE) and hand back A / B.
// Run: node tests/faction_id_legacy_local.cjs | npm exec --yes --package=fengari-node-cli@0.1.0 -- fengari -
// Executes the production FactionWarTownDocument, FactionWar and AbsentResult bodies with their declaration syntax lowered to Lua 5.3
// against a fake storage. This is not an MSW transpiler or a Maker runtime check.
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
function load(path, name) {
  return readFileSync(join(__dirname, '..', path), 'utf8')
    .replace(/\r\n/g, '\n')
    .replace(/^@(?:Logic|Component)\nscript \w+ extends \w+\n/, `_${name} = { _T = {} }\n`)
    .replace(/^    @\w+\([^\n]*\)\n/gm, '')
    .replace(/^    (?:@Sync )?property \w+ (\w+ = .+)$/gm, `_${name}.$1`)
    .replace(/^    (?:method \w+ |handler )(\w+)\(([^)]*)\)$/gm, (_, method, params) =>
      `function _${name}:${method}(${params.replace(/\b\w+ (\w+)/g, '$1')})`)
    .replace(/\nend\s*$/, '\n');
}
const rules = readFileSync(join(__dirname, 'faction_id_legacy_rules.lua'), 'utf8');
process.stdout.write(`local ok, failure = xpcall(function()
log = function() end
log_error = print
${load('RootDesk/MyDesk/Formations/FactionWarTownDocument.mlua', 'FactionWarTownDocument')}
${load('RootDesk/MyDesk/Formations/FactionWar.mlua', 'FactionWar')}
${load('RootDesk/MyDesk/Matchmaking/AbsentResult.mlua', 'AbsentResult')}
do
${rules}
end
end, function(message) return debug.traceback(message) end)
if not ok then io.stderr:write(failure .. "\\n") os.exit(1) end
`);
