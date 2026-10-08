// MCP orchestration bridge: acknowledge each request only after the actual Maker operation passes.
const readline = require("node:readline");
const { withTemporaryMonsterCsv } = require("./monster_catalog_csv_fixture.cjs");
function createAcknowledgementBridge(input, write) {
  let pending;
  let closed = false;
  let nextId = 0;
  input.on("line", line => {
    let reply;
    try { reply = JSON.parse(line); } catch { return; }
    if (!pending || reply?.id !== pending.id) return;
    if (reply.ok === true) pending.settle();
    else pending.settle(new Error(reply.error || "Maker operation failed"));
  });
  input.on("close", () => {
    closed = true;
    pending?.settle(new Error("MCP acknowledgement stream closed"));
  });
  return function request(operation, details, { signal } = {}) {
    if (closed) return Promise.reject(new Error("MCP acknowledgement stream closed"));
    if (pending) return Promise.reject(new Error("a Maker request is already pending"));
    if (signal?.aborted) return Promise.reject(signal.reason || new Error("Maker request cancelled"));
    return new Promise((resolve, reject) => {
      const id = ++nextId;
      const onAbort = () => pending?.id === id && pending.settle(signal.reason || new Error("Maker request cancelled"));
      pending = { id, settle(error) {
        signal?.removeEventListener("abort", onAbort);
        pending = null;
        if (error) reject(error); else resolve();
      } };
      signal?.addEventListener("abort", onAbort, { once: true });
      try { write({ id, request: operation, details }); }
      catch (error) { pending?.settle(error); }
    });
  };
}
async function main() {
  const input = readline.createInterface({ input: process.stdin });
  const request = createAcknowledgementBridge(input, message => process.stdout.write(`${JSON.stringify(message)}\n`));
  try {
    await request("stop", { stage: "before-install" });
    await withTemporaryMonsterCsv(({ signal, ...manifest }) => request("variant-probe", manifest, { signal }), {
      variantStats: { MaxHp: 650, MoveSpeed: 0.7, AttackDamage: 25, AttackIntervalSeconds: 1.3,
        AttackRange: 0.8, ContactCooldownSeconds: 1.3 },
      lifecycle: {
        stop: details => request("stop", { stage: details.stage }),
        refresh: details => request("refresh", { stage: details.stage }),
        verifyRestored: details => request("restored-probe", { sha256: details.originalSha256 }),
      },
      logger: message => process.stdout.write(`${message}\n`),
    });
    process.stdout.write("[VRF][CatalogFixture] PASS\n");
  } finally { input.close(); }
}
if (require.main === module) main().catch(error => { console.error(error); process.exitCode = 1; });
module.exports = { createAcknowledgementBridge };
