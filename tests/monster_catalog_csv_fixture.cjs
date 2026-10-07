const crypto = require("node:crypto");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const TANK_ID = "monster_tank";
const VARIANT_ID = "probe_tank_variant";
const DEFAULT_PROBE_CANCELLATION_TIMEOUT_MS = 30_000;
const DEFAULT_LIFECYCLE_TIMEOUT_MS = 120_000;

async function settlesWithin(promise, timeoutMs) {
  let timeoutId;
  const settled = await Promise.race([
    Promise.resolve(promise).then(() => true),
    new Promise((resolve) => { timeoutId = setTimeout(() => resolve(false), timeoutMs); }),
  ]);
  clearTimeout(timeoutId);
  return settled;
}

async function callWithTimeout(callback, args, operation, timeoutMs) {
  let timeoutId;
  const callbackPromise = Promise.resolve().then(() => callback(args));
  const timeoutPromise = new Promise((resolve, reject) => {
    timeoutId = setTimeout(() => reject(new Error(
      `lifecycle.${operation} did not complete within ${timeoutMs}ms`,
    )), timeoutMs);
  });
  try {
    return await Promise.race([callbackPromise, timeoutPromise]);
  } finally {
    clearTimeout(timeoutId);
  }
}

function parseMonsterCsv(source) {
  const text = Buffer.isBuffer(source) ? source.toString("utf8") : String(source);
  const bom = text.startsWith("\uFEFF") ? "\uFEFF" : "";
  const withoutBom = bom ? text.slice(1) : text;
  const lines = withoutBom.split(/\r\n|\n/);
  const trailingNewline = lines.length > 1 && lines.at(-1) === "";
  if (trailingNewline) lines.pop();
  if (lines.some((line) => line.includes("\r") || line.includes('"'))) {
    throw new Error("MonsterData fixture expects unquoted UTF-8 CSV rows");
  }
  const header = lines[0]?.split(",");
  if (!header || header.length === 0 || new Set(header).size !== header.length) {
    throw new Error("MonsterData CSV header is missing or has duplicate columns");
  }
  const records = lines.slice(1).map((line, rowIndex) => {
    const values = line.split(",");
    if (values.length !== header.length) {
      throw new Error(`MonsterData row ${rowIndex + 2} has ${values.length} cells; expected ${header.length}`);
    }
    return Object.fromEntries(header.map((name, index) => [name, values[index]]));
  });
  return { bom, header, records, trailingNewline };
}

function createTemporaryFixtureBuffer(originalBytes) {
  const source = Buffer.isBuffer(originalBytes) ? originalBytes : Buffer.from(originalBytes);
  const decoded = source.toString("utf8");
  if (!Buffer.from(decoded, "utf8").equals(source)) throw new Error("MonsterData CSV is not valid UTF-8");
  const parsed = parseMonsterCsv(source);
  const text = decoded.replace(/^\uFEFF/, "");
  const newline = text.includes("\r\n") ? "\r\n" : "\n";
  const lines = text.split(/\r\n|\n/);
  if (parsed.trailingNewline) lines.pop();
  const header = lines[0].split(",");
  const idIndex = header.indexOf("MonsterId");
  const nameIndex = header.indexOf("MonsterName");
  const typeIndex = header.indexOf("MonsterType");
  if (idIndex < 0 || nameIndex < 0 || typeIndex < 0) {
    throw new Error("MonsterData CSV is missing MonsterId, MonsterName, or MonsterType");
  }
  const tankIndexes = [];
  for (let index = 1; index < lines.length; index += 1) {
    if (lines[index].split(",")[idIndex] === TANK_ID) tankIndexes.push(index);
    if (lines[index].split(",")[idIndex] === VARIANT_ID) {
      throw new Error(`${VARIANT_ID} already exists in MonsterData.csv`);
    }
  }
  if (tankIndexes.length !== 1) throw new Error(`expected exactly one ${TANK_ID} row, found ${tankIndexes.length}`);

  const tankCells = lines[tankIndexes[0]].split(",");
  tankCells[nameIndex] = "RenamedTank";
  lines[tankIndexes[0]] = tankCells.join(",");
  const variantCells = [...tankCells];
  variantCells[idIndex] = VARIANT_ID;
  variantCells[nameIndex] = "VariantTank";
  lines.push(variantCells.join(","));
  const result = `${parsed.bom}${lines.join(newline)}${parsed.trailingNewline ? newline : ""}`;
  return Buffer.from(result, "utf8");
}

function sha256(bytes) {
  return crypto.createHash("sha256").update(bytes).digest("hex");
}

function insideTempDirectory(candidate, tempRoot = os.tmpdir()) {
  const relative = path.relative(path.resolve(tempRoot), path.resolve(candidate));
  return relative === "" || (!relative.startsWith(`..${path.sep}`) && relative !== ".." && !path.isAbsolute(relative));
}

async function withTemporaryMonsterCsv(runProbe, options = {}) {
  if (typeof runProbe !== "function") throw new TypeError("runProbe must be a function");
  const lifecycle = options.lifecycle || {};
  const lifecycleOperations = ["stop", "refresh", "verifyRestored"];
  const missingLifecycleOperations = lifecycleOperations.filter((operation) => typeof lifecycle[operation] !== "function");
  if (missingLifecycleOperations.length > 0) {
    const missingNames = missingLifecycleOperations.map((operation) => `lifecycle.${operation}`).join(", ");
    throw new TypeError(`required lifecycle callbacks are missing: ${missingNames}`);
  }
  const probeCancellationTimeoutMs = options.probeCancellationTimeoutMs ?? DEFAULT_PROBE_CANCELLATION_TIMEOUT_MS;
  const lifecycleTimeoutMs = options.lifecycleTimeoutMs ?? DEFAULT_LIFECYCLE_TIMEOUT_MS;
  for (const [name, value] of Object.entries({ probeCancellationTimeoutMs, lifecycleTimeoutMs })) {
    if (!Number.isSafeInteger(value) || value < 1) throw new TypeError(`${name} must be a positive integer`);
  }
  const csvPath = path.resolve(options.csvPath || path.join(__dirname, "../RootDesk/MyDesk/Data/MonsterData.csv"));
  const tempRoot = path.resolve(options.tempRoot || os.tmpdir());
  const originalBytes = fs.readFileSync(csvPath);
  const originalSha256 = sha256(originalBytes);
  const fixtureBytes = createTemporaryFixtureBuffer(originalBytes);
  const tempDirectory = fs.mkdtempSync(path.join(tempRoot, "m1-monster-csv-"));
  const backupPath = path.join(tempDirectory, "MonsterData.csv.original");
  const manifestPath = path.join(tempDirectory, "manifest.json");
  const manifest = {
    csvPath,
    backupPath,
    manifestPath,
    originalSha256,
    originalByteLength: originalBytes.length,
    fixtureSha256: sha256(fixtureBytes),
    fixtureByteLength: fixtureBytes.length,
  };
  const logger = options.logger || (() => {});
  const abortController = new AbortController();
  let signalError = null;
  let resolveInterruption;
  const interruption = new Promise((resolve) => { resolveInterruption = resolve; });
  const onSignal = (signalName) => {
    if (signalError) return;
    signalError = new Error(`temporary MonsterData probe interrupted by ${signalName}`);
    abortController.abort(signalError);
    resolveInterruption({ kind: "interrupted", error: signalError });
  };
  const onSigint = () => onSignal("SIGINT");
  const onSigterm = () => onSignal("SIGTERM");
  const externalSignal = options.signal;
  const onExternalAbort = () => onSignal("AbortSignal");
  process.on("SIGINT", onSigint);
  process.on("SIGTERM", onSigterm);
  if (externalSignal) {
    if (externalSignal.aborted) onExternalAbort();
    else externalSignal.addEventListener("abort", onExternalAbort, { once: true });
  }

  let outcome;
  let probePromise = null;
  let fixtureInstalled = false;
  let backupDirectoryRemoved = false;
  const cleanupErrors = [];
  const safeLog = (message) => {
    try {
      logger(message);
    } catch (error) {
      cleanupErrors.push(error);
    }
  };
  try {
    fs.writeFileSync(backupPath, originalBytes, { flag: "wx" });
    fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, { flag: "wx" });
    if (!insideTempDirectory(backupPath, tempRoot) || !fs.readFileSync(backupPath).equals(originalBytes)) {
      throw new Error("OS-temp MonsterData backup failed byte-for-byte verification");
    }
    safeLog(`[M1][CatalogFixture] original bytes=${originalBytes.length} sha256=${originalSha256} backup=${backupPath}`);
    if (signalError) throw signalError;
    fs.writeFileSync(csvPath, fixtureBytes);
    fixtureInstalled = true;
    if (!fs.readFileSync(csvPath).equals(fixtureBytes)) throw new Error("temporary MonsterData fixture failed byte-for-byte verification");

    probePromise = Promise.resolve()
      .then(() => runProbe({ ...manifest, signal: abortController.signal }))
      .then((value) => ({ kind: "success", value }), (error) => ({ kind: "failure", error }));
    outcome = await Promise.race([probePromise, interruption]);
  } catch (error) {
    outcome = { kind: "failure", error };
  } finally {
    let probeQuiesced = outcome?.kind !== "interrupted" || !probePromise;
    if (fixtureInstalled && outcome?.kind === "interrupted" && probePromise) {
      probeQuiesced = await settlesWithin(probePromise, probeCancellationTimeoutMs);
      if (probeQuiesced) safeLog("[M1][CatalogFixture] interrupted probe acknowledged cancellation before rollback");
    }
    if (fixtureInstalled) {
      try {
        await callWithTimeout(lifecycle.stop, { stage: "before-restore", manifest }, "stop", lifecycleTimeoutMs);
      } catch (error) {
        cleanupErrors.push(error);
      }
    }
    if (fixtureInstalled && outcome?.kind === "interrupted" && probePromise && !probeQuiesced) {
      // Maker Stop can release a request that did not settle on AbortSignal alone.
      probeQuiesced = await settlesWithin(probePromise, probeCancellationTimeoutMs);
      if (probeQuiesced) safeLog("[M1][CatalogFixture] interrupted probe settled after Maker Stop");
      else cleanupErrors.push(new Error(
        `probe callback did not acknowledge AbortSignal within ${probeCancellationTimeoutMs}ms before or after Maker Stop`,
      ));
    }
    try {
      const backupBytes = fs.existsSync(backupPath) ? fs.readFileSync(backupPath) : originalBytes;
      fs.writeFileSync(csvPath, backupBytes);
      const restoredBytes = fs.readFileSync(csvPath);
      if (!restoredBytes.equals(originalBytes) || sha256(restoredBytes) !== originalSha256) {
        throw new Error("MonsterData.csv restore failed byte-for-byte SHA-256 verification");
      }
      safeLog(`[M1][CatalogFixture] restored bytes=${restoredBytes.length} sha256=${originalSha256}`);
    } catch (error) {
      cleanupErrors.push(error);
    }
    try {
      await callWithTimeout(lifecycle.refresh, { stage: "after-restore", manifest }, "refresh", lifecycleTimeoutMs);
    } catch (error) {
      cleanupErrors.push(error);
    }
    try {
      await callWithTimeout(lifecycle.verifyRestored, { ...manifest, originalBytes }, "verifyRestored", lifecycleTimeoutMs);
    } catch (error) {
      cleanupErrors.push(error);
    }
    try {
      await callWithTimeout(lifecycle.stop, { stage: "after-restore-verification", manifest }, "stop", lifecycleTimeoutMs);
    } catch (error) {
      cleanupErrors.push(error);
    }
    if (cleanupErrors.length === 0) {
      try {
        fs.rmSync(tempDirectory, { recursive: true, force: false });
        backupDirectoryRemoved = true;
      } catch (error) {
        cleanupErrors.push(error);
      }
    }
    process.removeListener("SIGINT", onSigint);
    process.removeListener("SIGTERM", onSigterm);
    externalSignal?.removeEventListener("abort", onExternalAbort);
  }

  const primaryError = outcome?.kind === "success" && !signalError ? null : outcome?.error || signalError;
  if (cleanupErrors.length > 0) {
    const errors = primaryError ? [primaryError, ...cleanupErrors] : cleanupErrors;
    throw new AggregateError(errors, `temporary MonsterData cleanup failed${backupDirectoryRemoved ? "" : `; backup retained at ${tempDirectory}`}`);
  }
  if (primaryError) throw primaryError;
  return outcome.value;
}

module.exports = {
  TANK_ID,
  VARIANT_ID,
  createTemporaryFixtureBuffer,
  insideTempDirectory,
  parseMonsterCsv,
  sha256,
  withTemporaryMonsterCsv,
};
