// Pi codemode runner for Battle's Maker login-placement regression (P5).
// Open this repository's workspace in Maker, in Edit mode. Prefer formationlobby as the Play start map.
// The lone local player must stay outside Gushan (the offline cases sweep that town).
// Run from the repository root in one functions.codemode call:
//   // @options: {"timeout_ms": 360000}
//   const src = await tools.read({path:"tests/maker-p5-runner.js",offset:null,limit:null});
//   return await Function("tools", "return (async () => {\n" + src + "\n})();")(tools);
// Uses one Play session, 7 virtual-player joins (out of 10), two disposable
// profiles and an isolated town board. Do not interact with Play while it runs.

const probePath = 'tests/faction_war_reconnect_login_runtime_probe.lua';
const suite = ['FRIENDLY', 'FALLEN', 'RETAKEN', 'NOTOWN', 'NOFACTION', 'OFFLINE_FALL', 'OFFLINE_RETAKEN'];
const run = Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
const profileNonce = run.slice(-3);
const profiles = [`p5${profileNonce}a`, `p5${profileNonce}b`];
const storage = `CountryWarProbeP5${run}`;
const tag = `[VRF][P5Runner:${run}]`;
const mcp = 'mcp__msw_maker_mcp__';
const start = Date.now();
const elapsed = (since) => Math.round((Date.now() - since) / 100) / 10;
const report = { run, profiles, storage, joins: 0, cases: [], cleanup: 'NOT RUN', stop: 'NOT RUN' };

async function maker(tool, args = {}, {allowUnavailable = false} = {}) {
  const reply = await tools[mcp + tool](args);
  if (reply.isError) throw new Error(`${tool}: ${reply.content?.[0]?.text || 'MCP error'}`);
  const result = JSON.parse(reply.content[0].text);
  if (allowUnavailable && result.status === 'unavailable') return result;
  if (result.status !== 'ok' || result.stderr?.trim()) {
    throw new Error(`${tool}: ${result.stderr || result.message || result.status || 'missing status'}`);
  }
  return result;
}
const command = (value) => maker('maker_run_command', {command: value});
// During a mode transition there may be no active map to report yet.
const currentMode = () => maker('maker_get_current_map', {}, {allowUnavailable: true});

async function poll(get, accept, label, seconds) {
  const deadline = Date.now() + seconds * 1000;
  do {
    const value = await get();
    if (accept(value)) return value;
    if (Date.now() >= deadline) break;
    const delay = await tools.bash({command: 'sleep 1', timeout: 5});
    if (delay.exit_code !== 0) throw new Error('runner cannot sleep between polls');
  } while (Date.now() < deadline);
  throw new Error(`${label}: no completion signal in ${seconds}s`);
}

const profileList = profiles.map(p => JSON.stringify(p)).join(', ');
const findProfile = `
local function runnerFind(profile)
    for _, user in ipairs(_UserService.UserEntities.Values) do
        if isvalid(user) and isvalid(user.PlayerComponent) and user.PlayerComponent.ProfileCode == profile then return user end
    end
end`;
const absent = `
local function verifyAbsent(ds, key, label)
    local code, value = ds:GetAndWait(key)
    assert(_FactionWar:IsMissing(code, value), label .. ": expected an absent key; code=" .. tostring(code))
end
local function verifyUserKeys()
    for _, profile in ipairs({${profileList}}) do
        local ds = _DataStorageService:GetUserDataStorage(profile)
        verifyAbsent(ds, _FactionWar.FactionKey, profile .. " faction")
        verifyAbsent(ds, _FactionWar.TownKey, profile .. " town")
    end
end
local function verifyTownBoard()
    verifyAbsent(_DataStorageService:GetGlobalDataStorage("${storage}"), _FactionWarTownDocument.TownStorageKey, "isolated town board")
end`;

// Correlate all probe output with this run AND the dispatch. Never clear the Console.
async function stage(name, script, passes, seconds = 30) {
  const token = `${tag}[${name}] `;
  const wrapped = `
local emit, emitError = log, log_error
local function log(message) emit(${JSON.stringify(token)} .. message) end
local function log_error(message) emitError(${JSON.stringify(token)} .. message) end
local runnerOk, runnerErr = pcall(function()
${script}
end)
if not runnerOk then log_error("RUNNER FAIL " .. tostring(runnerErr)) end`;
  await maker('maker_execute_script', {context: 'server_main', script: wrapped});
  return poll(async () => (await maker('maker_console_logs', {space: 'server', search: token.trimEnd()})).logs, logs => {
    const messages = logs.filter(l => l.message.startsWith(token)).map(l => l.message.slice(token.length));
    const failed = messages.find(m => /\bFAIL\b/.test(m));
    if (failed) throw new Error(`${name}: ${failed}`);
    return messages.some(passes);
  }, name, seconds);
}

let playRequested = false;
let fixturesOwned = false;
try {
  const source = await tools.read({path: probePath, offset: null, limit: null});
  if (typeof source !== 'string') throw new Error('P5 probe is not a text file');
  function replaceOne(body, before, after) {
    const parts = body.split(before);
    if (parts.length !== 2) throw new Error(`P5 probe changed: expected one ${before}`);
    return parts.join(after);
  }
  const fixture = replaceOne(source, 'local STORAGE = "CountryWarProbe109V1"', `local STORAGE = "${storage}"`)
    .replaceAll('wp2625', profiles[0]).replaceAll('wp2626', profiles[1]);
  const probe = (scenario, step) => replaceOne(replaceOne(fixture,
    'local CASE = "FRIENDLY"', `local CASE = "${scenario}"`), 'local STEP = 1', `local STEP = ${step}`);
  // Validate the probe interface before Play or any storage writes.
  probe(suite[0], 1);
  if (!fixture.includes(`profile = "${profiles[0]}"`) || !fixture.includes(`profile = "${profiles[1]}"`)) {
    throw new Error('P5 probe changed: could not isolate its profiles');
  }

  const map = await maker('maker_get_current_map');
  if (map.mode !== 'edit' || !/^[a-z0-9_-]+$/i.test(map.name)) throw new Error('open Battle in Maker Edit mode first');
  const identity = await tools.bash({command: `node -e 'const {MapBuilder}=require("./.agents/skills/msw-general/scripts/map/msw_map_builder.cjs"); const n=process.argv[1]; console.log(MapBuilder.read("map/"+n+".map").find("/maps/"+n)?.id);' "${map.name}"`, timeout: 10});
  if (identity.exit_code !== 0 || identity.output.trim() !== map.id) throw new Error('Maker map does not match Battle');
  await maker('maker_refresh_workspace');
  async function checkBuild() {
    const build = await maker('maker_build_logs');
    const errors = build.logs.filter(l => l.logType === 'Error');
    if (errors.length) throw new Error('Maker build error: ' + errors[0].message);
    report.buildErrors = errors.length;
  }
  await checkBuild();
  playRequested = true;
  await command('play');
  await poll(currentMode, r => r.mode === 'play', 'Play startup', 35);
  await poll(() => command('list_contexts'), r => /\bserver_main\b/.test(r.output + ' ' + r.log), 'server_main startup', 25);
  await stage('preflight', `
${findProfile}
${absent}
assert(Environment:IsMakerPlay(), "Maker Play required")
local users = {}
for _ = 1, 150 do
    users = {}
    for _, user in ipairs(_UserService.UserEntities.Values) do
        if isvalid(user) then table.insert(users, user) end
    end
    if _FactionWarLanding._T.slots ~= nil and #users > 0 then break end
    wait(0.1)
end
assert(_FactionWarLanding._T.slots ~= nil, "FactionWar startup incomplete")
assert(_FactionWarTownDocument.TownStorageName == "CountryWarV1", "town board already overridden")
assert(#users == 1, "expected one local player, got " .. tostring(#users))
local localPlayer = users[1]
local localId = localPlayer.PlayerComponent.UserId
for _ = 1, 120 do
    if _MatchFlow._T.arrivalTimers[localId] == nil and not _MatchFlow._T.busy[localId]
        and not _MatchFlow._T.pendingRecover[localId] and not _FactionWarLanding:IsJudging(localId) then break end
    wait(0.1)
end
assert(not _FactionWarAttack:IsEngaged(localId), "local player must not have a live match ticket")
assert(localPlayer.CurrentMapName ~= "gushan", "local player must stay outside Gushan during the sweep")
for _, profile in ipairs({${profileList}}) do assert(runnerFind(profile) == nil, "fixture profile is occupied") end
verifyUserKeys()
verifyTownBoard()
log("PREFLIGHT PASS")`, m => m === 'PREFLIGHT PASS');
  fixturesOwned = true;

  for (const scenario of suite) {
    const since = Date.now();
    const profile = profiles[scenario === 'NOFACTION' || scenario.startsWith('OFFLINE_') ? 1 : 0];
    const prefix = `[VRF][ReconnectLogin] ${scenario}`;
    const row = { scenario, result: 'FAIL' };
    report.cases.push(row);
    try {
      await stage(`${scenario}/seed`, probe(scenario, 1), m => m.startsWith(`${prefix} SEEDED;`));
      if (report.joins >= 10) throw new Error('virtual player budget exhausted');
      report.joins++; // An attempted addition counts; never retry blindly.
      await command(`add_virtual_player -profile_code ${profile} -nickname Login109`);
      await stage(`${scenario}/check`, `${findProfile}
for _ = 1, 250 do
    if isvalid(runnerFind("${profile}")) then break end
    wait(0.1)
end
assert(isvalid(runnerFind("${profile}")), "virtual player did not join: ${profile}")
${probe(scenario, 2)}`, m => m === `${prefix} PASS`, 80);
      await stage(`${scenario}/kick`, probe(scenario, 3), m => m === `[VRF][ReconnectLogin] kicked ${profile}`);
      row.result = 'PASS';
    } finally {
      row.seconds = elapsed(since);
    }
  }
  await checkBuild();
} catch (error) {
  report.failure = String(error);
} finally {
  if (fixturesOwned) {
    const since = Date.now();
    try {
      await stage('cleanup', `
${findProfile}
${absent}
_FactionWarTownDocument.TownStorageName = "CountryWarV1"
for _, profile in ipairs({${profileList}}) do
    local user = runnerFind(profile)
    if isvalid(user) then _UserService:KickUser(user.PlayerComponent.UserId, KickReason.ETC) end
end
for _ = 1, 100 do
    if runnerFind("${profiles[0]}") == nil and runnerFind("${profiles[1]}") == nil then break end
    wait(0.1)
end
local code = _DataStorageService:DeleteGlobalDataStorageAndWait("${storage}")
for _, profile in ipairs({${profileList}}) do
    local ds = _DataStorageService:GetUserDataStorage(profile)
    ds:DeleteAndWait(_FactionWar.FactionKey)
    ds:DeleteAndWait(_FactionWar.TownKey)
end
assert(code == 0 or code == 1000002, "isolated board deletion code=" .. tostring(code))
assert(runnerFind("${profiles[0]}") == nil and runnerFind("${profiles[1]}") == nil, "fixture player still connected")
assert(_FactionWarTownDocument.TownStorageName == "CountryWarV1", "town storage name not restored")
verifyUserKeys()
verifyTownBoard()
log("CLEANUP PASS")`, m => m === 'CLEANUP PASS');
      report.cleanup = 'PASS';
    } catch (error) {
      report.cleanup = `FAIL: ${error}`;
    } finally {
      report.cleanupSeconds = elapsed(since);
    }
  }
  if (playRequested) {
    try {
      const mode = await poll(currentMode, r => r.status === 'ok', 'Maker mode', 20);
      if (mode.mode !== 'edit') await command('stop');
      await poll(currentMode, r => r.mode === 'edit', 'return to Edit', 20);
      report.stop = 'PASS';
    } catch (error) {
      report.stop = `FAIL: ${error}`;
    }
  }
}
report.seconds = elapsed(start);
report.result = !report.failure && report.cases.length === suite.length && report.cleanup === 'PASS' && report.stop === 'PASS' ? 'PASS' : 'FAIL';
return report;
