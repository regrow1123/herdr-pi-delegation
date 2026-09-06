---
name: herdr
description: Operate and configure herdr, the tmux-style terminal workspace manager built for AI coding agents — pane/tab/workspace keybindings, config.toml editing, live reload without restart, verify-reload loop.
---

# herdr — terminal workspace manager for AI coding agents

Tmux-like persistent session manager (client/server) with panes, tabs, workspaces, and agent labels in pane borders. Single static binary, e.g. `~/.local/bin/herdr`.

## Key facts
- Config file: `~/.config/herdr/config.toml`
- Full commented defaults: `herdr --default-config` (authoritative keybinding reference — use this before guessing)
- Live reload without restart: `herdr server reload-config` — JSON result: `{"status":"applied","diagnostics":[]}` = OK; `"status":"partial"` + diagnostics = bad keys
- Launch/attach: bare `herdr`; status: `herdr status`; update: `herdr update`; named sessions: `--session <name>`; remote attach: `--remote <ssh-target>`

## Default keybindings (prefix = ctrl+b)
- Split vertical (RIGHT): `prefix+v`
- Split horizontal (BOTTOM): `prefix+minus`
- Focus panes: `prefix+h` / `j` / `k` / `l`; cycle: `prefix+tab` / `prefix+shift+tab`
- Close pane: `prefix+x`; zoom: `prefix+z`; resize mode: `prefix+r`; sidebar: `prefix+b`
- Help: `prefix+?`; settings: `prefix+s`; detach: `prefix+q`; reload config: `prefix+shift+r`
- Tabs: new `prefix+c`, rename `prefix+shift+t`, prev/next `prefix+p` / `prefix+n`, close `prefix+shift+x`
- Workspaces: picker `prefix+w`, new `prefix+shift+n`, rename `prefix+shift+w`, close `prefix+shift+d`

Binding syntax: `"prefix+v"` = prefix-mode chord; `"ctrl+alt+n"` = direct terminal-mode shortcut. Named punctuation (minus, comma, ampersand, plus, backtick) accepted.

## Agent integrations & state reporting (verified)
- `herdr integration install pi` writes `~/.pi/agent/extensions/herdr-agent-state.ts` — pi then reports lifecycle to herdr over the socket (`pane.report_agent` JSON-RPC): `agent_start`→working, `agent_settled`+isIdle→idle, `herdr:blocked`→blocked. Requires `HERDR_ENV=1` + `HERDR_SOCKET_PATH` + `HERDR_PANE_ID` (auto-injected when herdr launches the agent).
- After install, `agent prompt <name> "task" --wait --timeout MS` works reliably (before: `agent_prompt_stalled` after 5s due to state desync with pi). Verify integration ownership via `screen_detection_skipped: true` in agent list output.
- Agent names are **server-globally unique** (source: `agent_name_conflicts` filters `collect_agent_infos()` with NO workspace/tab scope; `except_terminal_id` only excludes self). `agent start pi` fails with `agent_name_taken` if ANY registered agent is named pi → use `pi-$(date +%s)` per pane. However, agents started manually in a pane (e.g. user types `pi`) are NOT registered and don't count — they show as `null`/unknown agent and can duplicate freely.
- hermes integration lives at `~/.hermes/plugins/herdr-agent-state/__init__.py` (v4, current). `herdr integration status` lists all (claude/codex use hook scripts, session-identity only).

## Pane/tab ID naming (verified on 0.8.0)
- `pane_id` = `{workspace_id}:p{encoded}` — NO per-tab index (unlike tmux). N is a **per-workspace creation counter** (source-verified src/workspace.rs): root pane of a workspace gets 1, every new pane (split OR a new tab's root pane) takes `next_public_pane_number` which bumps via `max(number+1)` — strictly increasing, NEVER reused after close, shared across all tabs of the workspace. Each workspace restarts at p1 independently. Example from live state: tab t1 held `w6:p1`+`w6:p3`, tab t2 held `w6:p2`.
- ⚠️ NOT plain decimal: numbers use bijective base-32 (alphabet `123456789ABCDEFGHJKMNPQRSTVWXYZ0`). p1..p9 look decimal, but the 10th pane = `pA`, 31st = `pZ`, 32nd = `p10`. Same encoding applies to workspace ids (`w6` = 6th workspace; 10th = `wA`) and tab ids.
- Counters are workspace state: they survive server restarts with the persisted session state (`reserve_workspace_ids` resumes the workspace counter on load).
- `tab_id` = `{workspace_id}:t{N}` — N IS the tab number (matches label/number).
- Always address panes by full `pane_id` (`herdr pane split w6:p3 --direction down`); never by "position in tab".
- Split directions: `--direction right|down` only (right=vertical split left/right, down=horizontal split top/bottom). Target: positional PANE_ID or `--current`.
- Detect the Hermes session pane in scripts: `pane.agent == "hermes"`; other agents (`pi`, etc.) have their own `agent` value; bare shells report `agent_status:"unknown"` with no agent field.
- Spawn an agent in a fresh pane: `herdr agent start <NAME> --kind pi --pane <ID>` (needs shell prompt) then `herdr agent prompt <NAME> "<task>"`.

## Agent state reporting (event channel — preferred over polling)
- The robust way to know an agent's lifecycle is the **reporting channel**, not output polling. `herdr integration install pi` installs `~/.pi/agent/extensions/herdr-agent-state.ts` (by Prime) → pi reports working/idle/blocked via extension events instead of herdr's screen-manifest guessing.
- **`agent_prompt_stalled` after 5s (pi stalls while hermes works fine) = missing pi integration.** hermes has its own integration installed (`~/.hermes/plugins/herdr-agent-state/` — that's why hermes shows `working`), pi does not → herdr can't see pi's state changes. Fix: `herdr integration install pi`, verify with `herdr integration status`.
- Once integrated: `herdr agent prompt <name> "task" --wait --timeout 120000` works without stall; completion wait = `herdr agent wait <name> --until idle|done|blocked --timeout MS`; read result via `herdr agent read <name> --source recent-unwrapped`. CLI guide: "pane wait-output doesn't interpret lifecycle (polling); use agent wait".
- State model: idle / done (background task finished, same as idle until tab viewed) / working / blocked (approval/question UI) / unknown.
- Reporting API behind the scenes: `herdr pane report-agent $HERDR_PANE_ID --source herdr:pi --agent pi --state working|idle|blocked [--seq N]`, pane `release-agent` on exit; env: HERDR_ENV, HERDR_PANE_ID, HERDR_BIN_PATH, HERDR_SOCKET_PATH. Socket methods: pane.report_agent / pane.report_agent_session / pane.release_agent.
- pi native completion signals (if driving pi as a subprocess instead of via herdr): `pi --mode json` / `--mode rpc` emit JSONL events including `agent_end` and `agent_settled` ("Pi will not continue running automatically" — the definitive done signal), `turn_end`, `tool_execution_end`. Extension hook: `pi.on("agent_settled", ...)`.
- Completion detection with pi (all verified on 0.8.0):
  - `herdr pane wait-output --match/--regex` is BROKEN in 0.8.0 — `unknown option: Took` parse error. Don't use it.
  - Poll `herdr pane read <ID> --source recent-unwrapped` (softwrap truncates lines without `--source recent-unwrapped`, hiding markers) and grep for pi's `Took` performance marker.
  - CRITICAL: poll the pane pi is ACTUALLY working in — if reusing an existing agent (`herdr agent list` → existing pi pane), that's the reuse pane, NOT the freshly split pane (empty shell, never shows `Took`). Reference script `~/.hermes/bin/herdr-spawn-pi.sh` handles this via $WORK_PANE.
- Find the just-created pane: diff `herdr pane list` pane_ids before/after split (`comm -13 <(sort before) <(sort after)`). Reference script: `~/.hermes/bin/herdr-spawn-pi.sh` (1 pane → split right; multiple → split down from the bottom-right-most pane; start pi, fire-and-forget prompt, poll `pane read --source recent-unwrapped` for the `Took` completion marker). See "Agent wait & completion detection" below.
- `herdr pane layout` (PaneInfo) has NO position fields (x/y/w/h, direction). Position comes from `herdr pane layout` → `.panes[].rect {x,y,width,height}`. Bottom-right-most pane (predictable for "hermes left full-height, workers stacked right" layouts):
  ```bash
  herdr pane layout | jq -r '.result.layout.panes | sort_by(.rect.x + .rect.width, .rect.y + .rect.height) | last | .pane_id'
  ```
  `herdr pane neighbor --pane <id> --direction right/left/up/down` returns the adjacent pane_id directly.
- **Equal-height stacking (verified)**: repeated `split down` on the bottom pane yields UNEQUAL heights (1/2, 1/4, 1/4, ...). To equalize, set each down-split ratio by leaf count: `ratio = first_leaves / total_leaves` for every split node in the right column (recursively). CLI has no set-ratio command (`pane resize` only does deltas); call the socket directly: `layout.set_split_ratio {tab_id, path: bool[] (false=first,true=second), ratio}`. Split node path = its position in the binary tree (root.second = `[true]`, root.second.second = `[true,true]`...). Reference implementation: `~/.hermes/bin/herdr-equalize.py` (also invoked by herdr-spawn-pi.sh after each split).

## Agent wait & completion detection (0.8.0 quirks — polling fallback)
> NOTE: this section is the POLLING FALLBACK for when the pi integration is not installed. The preferred path is the event channel above (`herdr integration install pi` → `agent prompt --wait` / `agent wait`). Keep both; the fallback still works.
- With NO integration, `herdr agent prompt <name> <task> --wait` is unreliable for pi: a fresh pi usually needs >5s before its first response, so herdr bails with `agent_prompt_stalled` ("no observed state change within 5000 ms") even though the task runs fine. `--timeout` does NOT help — it applies only AFTER the 5s stall check. Working pattern: fire-and-forget `herdr agent prompt pi "<task>"`, then poll the pane for a completion marker.
- `herdr pane wait-output --match/--regex`: flags are documented in --help but 0.8.0's CLI rejects them (`unknown option: Took`, exit 2) — parsed as unknown options. Don't design around it; poll instead (below).
- Working completion poll (2s x 60 = 120s cap):
  ```bash
  for i in $(seq 1 60); do
    herdr pane read "$PANE" --source recent-unwrapped 2>/dev/null | grep -qE 'Took' && break
    sleep 2
  done
  ```
- ⚠️ SOFTWRAP (user-confirmed): pi replies render wrapped to pane width, so plain `herdr pane read` (default `recent` source) truncates lines and grep misses markers. ALWAYS pass `--source recent-unwrapped` when matching output text.
- Freshly started agents take ~10s+ to become interactive even after `agent start` returns `interactive_ready:true` — don't prompt immediately; the poll loop absorbs this.
- Reusing an existing agent pane (`herdr agent list | jq -r '.result.agents[]? | select(.agent=="pi" and .agent_status!="unknown") | .pane_id'`) leaves the freshly split pane EMPTY — decide upfront: reuse (and close the empty split) or always spawn a new agent per pane.

## Pitfalls
- PREFIX AND ALL KEY BINDINGS MUST BE INSIDE THE `[keys]` TOML SECTION. A top-level `prefix = "ctrl+a"` is silently ignored: reload reports `unknown config key prefix; ignoring key`. Correct shape:
  ```toml
  [keys]
  prefix = "ctrl+a"
  ```
- After editing config.toml run `herdr server reload-config` and check diagnostics is EMPTY, not just exit code 0 (exit=0 even on partial failures).
- If a binding still doesn't fire in an open session after a clean reload, restart herdr — input capture can lag a reload.

## CLI surface
Subcommands over the socket API: `herdr pane`, `tab`, `workspace`, `worktree`, `session`, `agent`, `notification`, `integration`, `api` (inspect live runtime state).

## References
- `references/pi-parallel-delegation.md` — verified end-to-end recipe for the split→start-pi→delegate loop, with the `agent_prompt_stalled` and `wait-output` error transcripts, softwrap fix, and agent-reuse wrinkle.
- `references/multi-agent-orchestration-patterns.md` — completion signaling per agent (claude/codex/pi hooks vs events vs polling, with config paths and done-signal names), cross-review ecosystem survey (superpowers/ARIS/delegate-skills/MCO/omux… with stars), 5 handoff patterns, safety invariants. Consult before building cross-review or multi-agent workflows.