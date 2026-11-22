const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');
const read = name => fs.readFileSync(`RootDesk/MyDesk/Matchmaking/${name}.mlua`, 'utf8');
const methods = source => [...source.matchAll(/^    method \w+ (\w+)\(/gm)].map(m => m[1]);
const body = (source, name) => source.match(new RegExp(`method \\w+ ${name}\\([^]*?(?=\\n    @|\\nend)`))?.[0] || '';

// The seam between the match flow and whatever finds opponents. MatchFlow owns the flow; adapters own the variation.
const QUEUE_PORT = ['Kind', 'Configured', 'Enqueue', 'Poll', 'Cancel', 'Lookup', 'Destinations', 'Warp', 'Withdraw', 'Release', 'Reclaim'];
const TRANSFER_PORT = ['MoveToMatch', 'MoveToLobby', 'MoveToTown', 'FindRoom'];

test('every queue adapter implements the whole queue port', () => {
  for (const adapter of ['MatchQueueLocal', 'MatchQueueNative', 'MatchFaults']) {
    const have = methods(read(adapter));
    for (const name of QUEUE_PORT) assert.ok(have.includes(name), `${adapter} implements ${name}`);
  }
});

test('every transfer adapter implements the whole transfer port', () => {
  for (const adapter of ['MatchTransfer', 'MatchFaults']) {
    const have = methods(read(adapter));
    for (const name of TRANSFER_PORT) assert.ok(have.includes(name), `${adapter} implements ${name}`);
  }
});

test('the match flow reaches matchmaking only through its adapters', () => {
  const flow = read('MatchFlow');
  assert.doesNotMatch(flow, /_MatchmakingService|MatchmakingResultCode/, 'native service calls live in MatchQueueNative');
  assert.doesNotMatch(flow, /localQueue|localMatches/, 'the Maker FIFO lives in MatchQueueLocal');
  assert.doesNotMatch(flow, /ConfigureMaker|cancelFailures|entryFailures|returnFailures/, 'fault injection lives in MatchFaults');
  assert.doesNotMatch(flow, /adapter == "local"|adapter == nil|"local-"/, 'ticket adapter kinds are judged by the adapter');
  assert.doesNotMatch(flow, /_MatchTransferReady|MoveUser\(|MoveUserToStaticRoom/, 'room movement lives in MatchTransfer');
  const allowed = new Set(['OnBeginPlay', 'Player']);
  for (const name of methods(flow)) {
    if (!allowed.has(name)) assert.doesNotMatch(body(flow, name), /IsMakerPlay/, `${name} does not branch on the environment`);
  }
});

test('queue outcomes reach the flow only as MATCHED, EXPIRED, FAILED or REJECTED', () => {
  const result = body(read('MatchFlow'), 'QueueResult');
  for (const outcome of ['MATCHED', 'EXPIRED', 'REJECTED']) assert.match(result, new RegExp(`outcome == "${outcome}"`));
  assert.doesNotMatch(result, /MatchmakingResultCode/);
});

test('fault injection is Maker only and wraps the live adapters instead of editing the flow', () => {
  const faults = read('MatchFaults');
  for (const name of ['ConfigureCancel', 'ConfigureTransfer', 'ConfigureWithdraw', 'ConfigureRooms']) {
    assert.match(body(faults, name), /Environment:IsMakerPlay\(\)/, `${name} refuses to arm outside Maker`);
  }
  assert.match(body(faults, 'Install'), /_MatchFlow:UseAdapters\(/);
});
