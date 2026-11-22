import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  createEditToolDefinition,
  createWriteToolDefinition,
  type ExtensionAPI,
  type ExtensionContext,
  type ToolDefinition,
} from "@earendil-works/pi-coding-agent";
import type { TSchema } from "typebox";

// The command hooks are shared with Codex (including its Windows LSP launcher).
// Do not evaluate commands from another harness's settings file.
const root = fileURLToPath(new URL("../../../", import.meta.url));
const hooks = join(root, ".codex", "hooks");
const refreshTool = "mcp__msw_maker_mcp__maker_refresh_workspace";
const toolNames: Record<string, string> = {
  bash: "Bash", powershell: "Bash", read: "Read", edit: "Edit", write: "Write",
};

type Payload = Record<string, unknown>;
type HookOutput = {
  decision?: string;
  reason?: string;
  systemMessage?: string;
  hookSpecificOutput?: {
    additionalContext?: string;
    permissionDecision?: string;
    permissionDecisionReason?: string;
  };
};

function payload(ctx: ExtensionContext, event: string, fields: Payload = {}): Payload {
  return { cwd: ctx.cwd, session_id: ctx.sessionManager.getSessionId(), hook_event_name: event, ...fields };
}

function runHook(script: string, input: Payload, seconds = 5, signal?: AbortSignal) {
  return new Promise<{ code: number | null; stdout: string; stderr: string }>((done) => {
    if (signal?.aborted) return done({ code: null, stdout: "", stderr: "cancelled" });
    const child = spawn("node", [join(hooks, `${script}.cjs`)], {
      cwd: String(input.cwd), windowsHide: true, timeout: seconds * 1000, signal,
      env: { ...process.env, CLAUDE_PROJECT_DIR: root },
    });
    let stdout = "";
    let stderr = "";
    child.stdout.setEncoding("utf8").on("data", (chunk) => { stdout += chunk; });
    child.stderr.setEncoding("utf8").on("data", (chunk) => { stderr += chunk; });
    child.on("error", (error) => { stderr += error.message; });
    child.on("close", (code) => done({ code, stdout: stdout.trim(), stderr: stderr.trim() }));
    child.stdin.on("error", () => {}); // An early-exiting hook may have closed stdin.
    child.stdin.end(JSON.stringify(input));
  });
}

function output(stdout: string): HookOutput {
  try { return JSON.parse(stdout) ?? {}; } catch { return {}; }
}

function withFilePath(cwd: string, input: Payload): Payload {
  return typeof input.path === "string" ? { ...input, file_path: resolve(cwd, input.path) } : input;
}

export default function mswHooks(pi: ExtensionAPI) {
  if (!existsSync(hooks)) return;

  const loggedFiles = new Set<string>();
  const starts = new Map<string, number>();
  let pendingStartup = "";
  let refreshQueue: Promise<unknown> = Promise.resolve();

  pi.on("session_start", async (event, ctx) => {
    loggedFiles.clear();
    starts.clear();
    const input = payload(ctx, "SessionStart", { source: event.reason });
    const lsp = await runHook("mlua-lsp/mlua-session-start", input, 120);
    pendingStartup = output(lsp.stdout).hookSpecificOutput?.additionalContext ?? "";
    if (!pendingStartup && lsp.code !== 0) pendingStartup = `[msw-hooks] LSP startup hook failed: ${lsp.stderr}`;
    if ((event.reason === "startup" || event.reason === "resume") && process.env.PI_OFFLINE !== "1") {
      const result = await runHook("update-check/update-check", input, 10);
      const notice = output(result.stdout).systemMessage;
      if (notice) ctx.ui.notify(notice, "info");
    }
  });

  pi.on("session_shutdown", async (event, ctx) => {
    await runHook("mlua-lsp/mlua-session-end", payload(ctx, "SessionEnd", { reason: event.reason }), 20);
  });

  pi.on("before_agent_start", async (event, ctx) => {
    // Pi has no InstructionsLoaded event. Log the actual context files once,
    // when they are first included in a prompt, rather than guessing from disk.
    for (const { path } of event.systemPromptOptions.contextFiles ?? []) {
      if (loggedFiles.has(path)) continue;
      loggedFiles.add(path);
      await runHook("skill-log/skill-log", payload(ctx, "InstructionsLoaded", {
        file_path: path, memory_type: "context", load_reason: "prompt",
      }));
    }
    const sections = event.systemPromptOptions.sections;
    if (event.messageType === "user") {
      // Pi expands /skill:<name> before this event; capture its synthetic block.
      const skill = /^<skill name="([^"]+)" location="[^"]+">\n([\s\S]*?)\n<\/skill>(?:\n\n[\s\S]+)?$/.exec(event.prompt);
      if (skill) await runHook("skill-log/skill-log", payload(ctx, "PostToolUse", {
        tool_name: "Skill", tool_input: { name: skill[1] }, tool_response: skill[2],
      }));
      const { stdout } = await runHook("skill-router-reminder/skill-router-reminder", payload(ctx, "UserPromptSubmit"));
      if (stdout) sections.msw_skill_router = stdout.replace("(Claude Code: 'Skill' tool;", "(Pi: /skill:<name> or its advertised skill file via read; Claude Code: 'Skill' tool;");
    }
    if (pendingStartup) {
      sections.msw_lsp_startup = pendingStartup;
      pendingStartup = "";
    }
  });

  pi.on("tool_call", async (event, ctx) => {
    const name = toolNames[event.toolName];
    if (!name) return;
    const input = payload(ctx, "PreToolUse", { tool_name: name, tool_input: withFilePath(ctx.cwd, event.input) });
    const checks = name === "Bash"
      ? ["skill-read-guard/skill-read-guard", "structured-file-guard/structured-file-guard"]
      : ["structured-file-guard/structured-file-guard"];
    for (const script of checks) {
      const result = await runHook(script, input, 5, ctx.signal);
      const decision = output(result.stdout).hookSpecificOutput;
      if (decision?.permissionDecision === "deny") return { block: true, reason: decision.permissionDecisionReason };
      if (result.code !== 0) return { block: true, reason: result.stderr || `[msw-hooks] ${script} failed or timed out.` };
    }
  });

  pi.on("tool_execution_start", (event) => {
    if (event.toolName === "read" || event.toolName.startsWith("mcp__")) starts.set(event.toolCallId, performance.now());
  });
  pi.on("tool_execution_end", (event) => { starts.delete(event.toolCallId); });

  pi.on("tool_result", async (event, ctx) => {
    const name = event.toolName;
    const toolInput = withFilePath(ctx.cwd, event.input);
    const script = name.startsWith("mcp__") ? "mcp-log/mcp-log"
      : name === "read" && /[\\/]skills[\\/].+\.md$/i.test(String(toolInput.file_path)) ? "skill-log/skill-log"
      : undefined;
    if (!script) return;
    const start = starts.get(event.toolCallId);
    // Match the original asynchronous log hooks. MCP logging receives the actual
    // nested tool result, not the outer codemode script's combined output.
    void runHook(script, payload(ctx, "PostToolUse", {
      tool_name: toolNames[name] ?? name,
      tool_input: toolInput,
      tool_response: { content: event.content, structuredContent: event.structuredContent, isError: event.isError },
      duration_ms: start === undefined ? undefined : Math.round(performance.now() - start),
    }));
  });

  // Only tool execute contexts can call other tools in Pi 1.6. Wrap native
  // mutations so refresh uses Pi's existing Maker MCP connection and tool hooks.
  function afterWrite<T extends TSchema, D, S>(factory: (cwd: string) => ToolDefinition<T, D, S>) {
    const base = factory(root);
    pi.registerTool({
      ...base,
      reachesTools: () => [refreshTool],
      async execute(id, params, signal, onUpdate, ctx) {
        const result = await factory(ctx.cwd).execute(id, params, signal, onUpdate, ctx);
        if (result.isError || signal?.aborted) return result;
        const input = params as { path: string };
        const notes: string[] = [];
        let diagnosticError = false;
        if (/\.mlua$/i.test(input.path)) {
          const diagnosed = await runHook("mlua-lsp/mlua-diagnose-post-tool-use", payload(ctx, "PostToolUse", {
            tool_name: toolNames[base.name], tool_input: withFilePath(ctx.cwd, input),
          }), 120, signal);
          const report = output(diagnosed.stdout);
          const note = report.hookSpecificOutput?.additionalContext ?? report.reason;
          diagnosticError = report.decision === "block";
          if (note) notes.push(diagnosticError ? `File saved, but mLua validation failed:\n${note}` : note);
          else if (diagnosed.code !== 0 && !signal?.aborted) notes.push(`[msw-hooks] mLua diagnostic hook failed: ${diagnosed.stderr}`);
        }
        if (!signal?.aborted && pi.getAllTools().some((tool) => tool.name === refreshTool)) {
          const refresh = refreshQueue.then(async () => !signal?.aborted ? ctx.executeTool(refreshTool, {}, { signal }) : undefined);
          refreshQueue = refresh.catch(() => undefined);
          const refreshed = await refresh;
          const summary = refreshed?.result.content.filter((part) => part.type === "text").map((part) => part.text).join("\n");
          if (refreshed && (refreshed.isError || /unavailable/i.test(summary ?? ""))) {
            notes.push(`[msw-hooks] Maker refresh did not complete: ${summary || "MCP error"}`);
          }
        }
        return notes.length ? {
          ...result, isError: diagnosticError,
          content: [...result.content, { type: "text" as const, text: notes.join("\n") }],
        } : result;
      },
    });
  }

  afterWrite(createEditToolDefinition);
  afterWrite(createWriteToolDefinition);
}
