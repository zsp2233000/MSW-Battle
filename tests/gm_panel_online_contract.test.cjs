const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const read = name => fs.readFileSync(path.join(__dirname, '../RootDesk/MyDesk/GM', name), 'utf8');

test('online player lookup uses the GM-only command path and room-local communication', () => {
  const commands = read('GMCommandService.mlua');
  const authorization = commands.indexOf('if not self:IsGM(requesterProfile)');
  const lookup = commands.indexOf('if command.kind == "LIST_ONLINE_PLAYERS"');
  assert.ok(authorization >= 0 && lookup > authorization);
  const online = read('GMOnlinePlayers.mlua');
  assert.match(online, /@ExecSpace\("ServerOnly"\)\s+method void Read\(/);
  assert.match(online, /@ExecSpace\("ServerOnly"\)\s+@EventSender\("Service", "RoomService"\)/);
  assert.doesNotMatch(online, /_WorldInstanceService|_DataStorageService|@ExecSpace\("Server"\)/);
});
