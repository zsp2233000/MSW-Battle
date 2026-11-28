// The production BattleSession:ParticipantSide, lowered to a plain Lua function `ParticipantSideOf(self, profile)`.
// Local suites hang it on their fake battle, so the rule under test is the shipped one and never a copy of it.
// Only the declaration line is lowered; the body is the production text.
const { readFileSync } = require('node:fs');
const { join } = require('node:path');

function participantSideLua() {
  const source = readFileSync(join(__dirname, '../RootDesk/MyDesk/Combat/BattleSession.mlua'), 'utf8').replace(/\r\n/g, '\n');
  const match = source.match(/    method string ParticipantSide\(string profile\)\n([^]*?)\n    end\n/);
  if (!match) throw new Error('BattleSession:ParticipantSide was not found');
  return `function ParticipantSideOf(self, profile)\n${match[1]}\nend\n`;
}

module.exports = { participantSideLua };
