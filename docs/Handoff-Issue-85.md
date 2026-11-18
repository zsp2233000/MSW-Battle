# Handoff: finish MSW Battle issue #85

## Publication note

The user subsequently requested this handoff be saved in the project and committed/pushed. That publication is scoped to this handoff document. The #85 implementation remains uncommitted and unverified in the working tree. The implementation-status statements below describe the handoff snapshot.

## Current objective and authorization

The user requested subagents to implement GitHub #85 with mattpocock-skills:implement, including verification, code review and a commit on the current branch. They then explicitly invoked mattpocock-skills:handoff; implementation is now handed off, not complete. Continue the existing uncommitted work. No commit, PR, push, issue comment or issue closure has been performed.

Workspace: D:/Code/Battle (Windows PowerShell).
Current branch: feat/83-gm-panel.
Starting HEAD / review fixed point: 16d2cee892f10fd1b776bc11f3875ce13af545be.
Working tree was clean initially. All current changes belong to this task.

## Sources of truth (read these rather than duplicating the spec)

- Issue #85: https://github.com/zsp2233000/MSW-Battle/issues/85
- Parent #83: https://github.com/zsp2233000/MSW-Battle/issues/83
- Dependency #84 is CLOSED; its implementation is starting HEAD.
- D:/Code/Battle/AGENTS.md
- D:/Code/Battle/CONTEXT.md (營運工具 vocabulary)
- D:/Code/Battle/docs/adr/0009-gm-panel-forced-overwrite-after-audit.md
- D:/Code/Battle/docs/agents/issue-tracker.md (use gh CLI), domain.md
- D:/Code/Battle/docs/Issue-84-GM-Panel.md (existing verification procedure)
- D:/Code/Battle/docs/Issue-85-GM-Panel.md is a draft written this session. Its final verification section is intentionally unfinished. Do not interpret its acceptance checklist as evidence.
- Use git diff from the fixed point for implementation details, not this handoff.

## Suggested skills

Load msw-general then msw-ui-system and the four Foundation references required by AGENTS.md. Target map is RectTile, so also load platform-rect.md. Load msw-scripting with references/verify-checklist.md and references/datastorage.md; UI component-api.md and runtime-patterns.md; builder-protocol.md plus builder-protocol-ui.md for UI work. Map inspection requires builder-protocol-map.md. Use the local files under D:/Code/Battle/.agents/skills/.

Continue mattpocock-skills:implement and ponytail:ponytail full. Testing seams were already explicitly agreed in #83/#85: command-service runtime, Node security/RPC/UI contracts, and connected client ButtonClickEvent UI probes; do not ask again. TDD is appropriate at those seams. At completion apply mattpocock-skills:code-review (separate Standards and Spec reviews), then commit on the existing branch as implement requests. The user authorized subagents. Do not create a new Codex chat.

No Skill/Read/Glob tools were exposed in this session; local skill/file reads used mcp__node_repl__js with node:fs/promises. Use builders for .ui/.map/.model inspection and writes. Do not use CodeGraph (project explicitly opts out). Do not hand-edit .codeblock; Maker Refresh owns it.

## Work ownership and subagents

- Server worker Gauss: 01a1e9c2-5d05-7a90-b559-d6cd171bb773. Owns FormationStorage.mlua, GMCommandService.mlua, server probe. It produced a patch but never delivered a final completed implementation report. On handoff the parent sent an interrupt asking it to stop/save/report. The subsequent wait returned an ERROR that the inherited model was unsupported for this account. Do not rely on this worker continuing; inspect and finish its current patch.
- UI worker Kuhn: 01a1e9cd-0d45-7093-8e7a-794913a8ae77. Completed UI/RPC/contracts/UI probes. Reported full Node suite 150 PASS; parent has not independently rerun that result. Worker reported a coordination message to Gauss was blocked by automatic review, but said server command.action support already existed. Check interfaces in current files. No Maker calls or commit by this worker.
- Parent wrote only the draft docs/Issue-85-GM-Panel.md, prepared verification, and performed an early integration review. Parent did not finish the formal two-axis code review.

## Files changed / added

Modified:
- RootDesk/MyDesk/Formations/FormationStorage.mlua
- RootDesk/MyDesk/GM/GMCommandService.mlua
- RootDesk/MyDesk/GM/GMPanel.mlua
- RootDesk/MyDesk/GM/GMPanelService.mlua
- tests/gm_panel_contract.test.cjs
- ui/GMPanelGroup.ui

Added:
- docs/Issue-85-GM-Panel.md
- tests/gm_level_write_runtime_probe.lua
- tests/gm_panel_edit_ui_client_runtime_probe.lua
- tests/gm_panel_edit_ui_fixture.lua

Temporary tests/_write_contract.cjs and .py appeared during implementation but were absent from the latest git status. No .codeblock changes yet because Refresh has not been run for this patch.

## Verification actually performed

- Parent ran initial baseline: node --test tests/*.test.cjs => 149/149 PASS before implementation.
- UI worker reports 150 PASS after its changes (not independently confirmed by parent).
- node --test tests is the WRONG command here (module not found); use the glob above.
- No separate mLua typecheck script: Maker Refresh conversion/build logs are compiler checks.
- Maker connection verified against this workspace: formationlobby, root id def3147d-fd1d-449e-b9e8-ff1debff051b, TileMapMode=1 via MapBuilder. The map/root IDs match. All four workspace maps inspected had mode 1.
- Maker initially was in Play. Parent called stop before modifications. Latest handoff get_current_map confirms mode EDIT at formationlobby. No Refresh, Play or runtime probe has been run for #85. No #85 runtime PASS evidence exists. Do not claim it works yet.

## Early integration findings sent to workers — confirm fixes in current code

These findings refer to an intermediate patch; some may already be fixed. Do not blindly reapply.

Server/storage:
1. Appending pending audit used an empty CAS expectation even when prior records existed, so the second action would fail. Pending append must CAS against actual read audit bytes; outcome update against pending bytes.
2. Audit read treated error + nil as missing. Only NotFound or successful nil is missing; timeout/Credit failure must stop mutation.
3. Raw repair branch could overwrite settled matches of a healthy document. Repair only corruption, or retain the healthy document's settled list server-side. Rows cannot edit settled.
4. Guarded absent-key unconditional Set with ambiguous failure released the cross-instance guard. Preserve the existing FormationStorage uncertain-write safety so a late Set cannot overwrite a newer write.
5. An intermediate FormationStorage patch had duplicate ExecSpace on ReadAudit and missing ServerOnly on WriteAudit.
6. Delete audit after-content should describe deletion, not an internal temporary marker. Actual before-content must be recoverable.
7. Row payload needs boundary validation: dense array, nonempty/known IDs, no duplicate IDs, valid level/experience. Do not encode a document the shared decoder would reject.
8. Delete has no native CAS API. Current design is exclusive cross-instance GM guard + CAS corrupt bytes to unique marker + delete marker. Normal settlement must reject marker and other GM mutations must not race the delete. Review the whole ownership/error path.

UI/RPC:
9. Intermediate Submit used editable targetInput.Text, allowing loading A then typing B and writing A's edits to B. UI worker says fixed to the loaded target. Reload must also use the loaded target.
10. Reset/Delete conflict initially forced an empty SAVE, losing original action. Worker says Force now preserves SAVE_LEVELS/RESET_LEVELS/DELETE_LEVELS via command.action. Confirm server and RPC forwarding agree, and deletion still refuses a now-healthy save.
11. RPC payload was any (invalid across RPC); worker changed it to table. Preserve existing sender-only identity derivation and private reply routing.

Probe safety:
12. Initial server probe touched real requester's GMAuditV1 key and deleted it during cleanup. Parent refused to execute it and requested a synthetic target player, separate from the real whitelisted requester. VERIFY THIS IS FIXED BEFORE RUNNING. Use short synthetic ProfileCode (e.g. prefix + 8 GUID chars), not full GUID, to keep hex-encoded guard name <=100 chars. Every command.profile must explicitly use synthetic target; empty means the real requester.
13. Initial retention loop accidentally used first read return (code) as expected bytes. Fix/read current probe. Prefer pre-seeding 20 audit records and 2 mutations instead of 25 write/read cycles to conserve Credit.
14. Probe must test corrupt repair as well as delete, invalid progress, CAS conflict/reload/force, reset preserving latest settled list, audit-first failure leaving save unchanged, cap20, and read/write errors. Initial probe was incomplete; check coverage.

## Next actions

1. Review current server patch and probes, fix outstanding findings; validate UI/server command payload agreement. Do not overwrite another agent's changes with an old copy.
2. Read UI worker fixture/probe fully before executing. Worker-provided order: server_main gm_panel_edit_ui_fixture.lua => READY; client gm_panel_edit_ui_client_runtime_probe.lua => PASS; always rerun fixture with CLEANUP=true => CLEANUP_PASS. Inspect isolation first, including audit storage.
3. Run appropriate Node contracts, UIBuilder lint, and Maker Refresh/build (also normal logs for conversion errors). One successful fresh Play should cover all turn changes; failures may require another cycle. Enumerate context keys before scripts. maker_execute_script dispatch OK is not completion: inspect logs for terminal PASS and cleanup markers.
4. Run server probe tests/gm_level_write_runtime_probe.lua in server_main only after its isolation is safe. Run existing #84 regression probes as appropriate; UI now uses editable inputs, so old read-only expectations may need the smallest update.
5. Always cleanup fixtures, restore storage key overrides/fault settings and stop Maker. No screenshots needed unless requested/for input coordinate targeting.
6. Apply formal code-review skill against starting HEAD and #85 spec, fix findings, rerun checks affected by fixes; run full Node suite once at end. Update draft verification doc with actual evidence and limitations.
7. Commit task files on feat/83-gm-panel. Do not push or post messages to GitHub unless requested. User asked for implementation, not publication.

## Tool / environment notes

Use functions.exec to discover metadata in ALL_TOOLS, printing only relevant entries. Tool names available through tools include multi_agent_v1__*, mcp__node_repl__js, mcp__msw_maker_mcp__maker_*. No runtime claims without actual Maker calls.

gh read network failed in sandbox; require_escalated gh issue view worked. This environment's gh rejects --comments combined with --json; use --json ...,comments. For shell operations use PowerShell-safe quoting and forward-slash paths. Git reports LF-to-CRLF warnings; these alone are not test failures.

No credentials or secrets belong in handoff artifacts. Whitelist details are already in source and #84 documentation; consult those rather than copying identities here.
