// Emit the production AbsentResult script with its declaration syntax lowered to Lua 5.3, followed by the local rules.
// Run: node tests/absent_result_local.cjs | npm exec --yes --package=fengari-node-cli@0.1.0 -- fengari -
// This is not an MSW transpiler or a Maker runtime check. Only the declaration syntax of this module is lowered; the bodies are production code.
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const logic = readFileSync(join(__dirname, '../RootDesk/MyDesk/Matchmaking/AbsentResult.mlua'), 'utf8')
  .replace(/\r\n/g, '\n')
  .replace(/^@Logic\nscript AbsentResult extends Logic\n/, 'local doc = { _T = {} }\n')
  .replace(/^    @\w+\([^\n]*\)\n/gm, '')
  .replace(/^    property \w+ (\w+ = .+)$/gm, 'doc.$1')
  .replace(/^    (?:method \w+ |handler )(\w+)\(([^)]*)\)$/gm, (_, name, params) =>
    `function doc:${name}(${params.replace(/\b\w+ (\w+)/g, '$1')})`)
  .replace(/\nend\s*$/, '\n_AbsentResult = doc');
const rules = readFileSync(join(__dirname, 'absent_result_rules.lua'), 'utf8');
process.stdout.write(`local ok, failure = xpcall(function()\nlog = print\nlog_error = print\n${logic}\ndo\n${rules}\nend\nend, function(message) return debug.traceback(message) end)\nif not ok then io.stderr:write(failure .. "\\n") os.exit(1) end\n`);
