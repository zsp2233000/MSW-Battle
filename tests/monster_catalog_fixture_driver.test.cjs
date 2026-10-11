const assert = require("node:assert/strict");
const { EventEmitter } = require("node:events");
const test = require("node:test");
const { createAcknowledgementBridge } = require("./monster_catalog_fixture_driver.cjs");

test("a cancelled probe acknowledgement cannot complete the following Maker Stop", async () => {
  const input = new EventEmitter();
  const requests = [];
  const request = createAcknowledgementBridge(input, message => requests.push(message));
  const controller = new AbortController();
  const probe = request("variant-probe", {}, { signal: controller.signal });
  const cancelled = assert.rejects(probe, /cancelled/);
  controller.abort(new Error("probe cancelled"));
  await cancelled;

  let stopped = false;
  const stop = request("stop", { stage: "before-restore" }).then(() => { stopped = true; });
  input.emit("line", JSON.stringify({ id: requests[0].id, ok: true }));
  await Promise.resolve();
  assert.equal(stopped, false, "stale acknowledgement must not authorize CSV rollback");
  input.emit("line", JSON.stringify({ id: requests[1].id, ok: true }));
  await stop;
  assert.equal(stopped, true);
  assert.notEqual(requests[0].id, requests[1].id);
});

test("the bridge rejects overlapping requests, Maker failure, and a closed stream", async () => {
  const input = new EventEmitter();
  const requests = [];
  const request = createAcknowledgementBridge(input, message => requests.push(message));
  const refresh = request("refresh", {});
  await assert.rejects(request("stop", {}), /pending/);
  const failed = assert.rejects(refresh, /refresh failed/);
  input.emit("line", JSON.stringify({ id: requests[0].id, ok: false, error: "refresh failed" }));
  await failed;
  const stop = request("stop", {});
  const closed = assert.rejects(stop, /stream closed/);
  input.emit("close");
  await closed;
  await assert.rejects(request("refresh", {}), /stream closed/);
});
