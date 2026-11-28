# MSW hooks for Pi 1.6

Pi auto-loads `index.ts` when the project is trusted. In an open session, use `/reload`. The bridge needs `node` on `PATH` and reuses the scripts in `.codex/hooks/`; it does not run Claude and Codex configurations in parallel.

| Original behavior | Pi integration |
| --- | --- |
| Skill and structured-file guards | `tool_call` on native Bash/PowerShell and file tools, including calls nested under codemode |
| Skill/reference and MCP logging | Logs Pi `/skill:` expansions, successful or failed executed `read`/MCP calls as applicable; writes under `.mswai/logs/` |
| `InstructionsLoaded` | Logs the actual context files the first time they're included in a prompt in the session |
| Skill-router reminder | `before_agent_start` on user prompts |
| LSP startup and cleanup | `session_start` / `session_shutdown` (including reload) |
| MSW CLI update notice | Startup/resume; skipped with `--offline` |
| mLua diagnosis and Maker refresh | After successful native `edit`/`write`; diagnostics are returned with the write result and do not undo the write |

Maker refresh uses Pi's existing `msw-maker-mcp` connection. It is skipped if the tool is not registered; Maker must be in edit mode to refresh. Shell commands and external programs that mutate files are not native `edit`/`write` calls and do not trigger the post-write hooks. The guards retain the shared scripts' existing matcher scope; they are not a filesystem sandbox.
