---
name: dev-loop
description: Work the Findly backlog (docs/implementation-handoff.md) with strict TDD plus a mandatory code + security review gate per task. "parallel N" runs up to N isolated coding agents concurrently while respecting task dependencies; a task ID (e.g. B2) runs only that task; no args = sequential loop. Use when the user invokes /dev-loop or asks to work through / implement the backlog tasks.
argument-hint: "[parallel N] [taskId ...]"
---

# dev-loop — dependency-safe backlog executor

You are the **orchestrator**. You never write implementation code in this session — coding happens in spawned agents inside isolated git worktrees. You schedule waves, run the review gate, merge, and keep the ledger (`docs/implementation-handoff.md`).

## 1. Parse arguments

- `parallel N` → concurrency cap of N coding agents per wave (N ≥ 1). Default: 1.
- Task IDs (e.g. `B2 B3`) → restrict the loop to exactly those tasks; their dependencies must already be `done` (if not, stop and say which are missing — do NOT pull dependencies in implicitly).
- Both may combine (`parallel 2 B2 B3`). Unrecognized input → ask.

## 2. Preconditions — hard-stop if any fails

1. **Committed baseline.** `git status` clean AND at least one commit exists (worktrees need one). If not: STOP and ask the user to commit first — never commit their working tree yourself without approval.
2. **Backlog parses.** The Backlog table in `docs/implementation-handoff.md` has rows `| ID | Scope | Depends on | Status |`, status ∈ `todo|in-progress|review|done|blocked|human|failed`. Rows with status `in-progress`/`review` from a previous interrupted run: list them and ask the user whether to resume (re-review their branches) or reset to `todo`.
3. **Green baseline.** `cd backend && npm ci && npm test` passes. A red baseline is never built upon — STOP and report.

## 3. Wave loop — repeat until nothing is runnable

1. **Select.** Runnable = status `todo` AND every *Depends on* ID has status `done` (a `human` dependency counts only after the **user** confirmed it done). Take up to N, lowest ID first. Note: N is a **cap** — early waves may have fewer unblocked tasks (e.g. a fresh backlog runs B1 alone before B2/B3 can start). If nothing is runnable and nothing is in flight → §6.
2. **Mark** selected tasks `in-progress` in the backlog table immediately (makes an interrupted loop resumable).
3. **Spawn** all selected coding agents in ONE message: Agent tool, `isolation: "worktree"`, `run_in_background: true`, `model: "sonnet"` (implementation never needs a premium model), prompt from §5.
4. **As each agent completes** (don't barrier the wave): set its task to `review`, run the review gate (§4). Other agents keep running meanwhile.
5. **Merge approved tasks** one at a time, lowest ID first, from the main checkout:
   - `git merge --no-ff <branch>` (branch name comes from the agent's report).
   - Conflicts: if trivial, resolve yourself against the specs; otherwise `SendMessage` the task's coding agent (it still holds its worktree) to rebase onto current `main`, re-run its gates, and report the new state — then merge again.
   - **Integration gate after every merge:** `cd backend && npm test && npm run mutation && npm run build`. Red → revert the merge (`git reset --hard` to pre-merge), send the agent the failure output, one retry. Red again → task `failed`.
6. **Ledger** after each terminal task: status → `done` (or `failed` — leave the branch **and its worktree** for inspection and keep looping with the rest), append to `## Dev-loop log`: date · task · agent rounds · review findings fixed · merge commit. For a `done` task, only now (the branch is merged and no further review rounds can need the worktree) reclaim it: `git worktree remove <worktree-path> --force` (path from the agent's report), then `git branch -d <branch>`.
7. Newly-`done` tasks unblock dependents → recompute and start the next wave.

## 4. Review gate — per task, before merge, NEVER skipped

Spawn **two reviewer agents in one message** (read-only — they must not edit), giving each the task ID, spec sections, and branch name. Reviewers work from the main checkout via git (`git diff $(git merge-base main <branch>)..<branch>`, `git show <branch>:<path>`) — no worktree access needed.

- **Code reviewer** — verify: wire shapes/error codes match `specs/001` exactly (codes only from §10); the agent's report shows **red-before-green** TDD evidence; the test set covers the spec's test checklist for this scope; mutation gate passed; no scope creep; no spec divergence (a "better" implementation that differs from spec is a finding — spec changes go through a spec PR first).
- **Security reviewer** — execute `docs/security-review-checklist.md` **in full** (secrets scan with its grep, newly-tracked-file check, CI/CD rules if `.github/` changed, auth-guard/validation/logging rules, dependency audit). The user's hard requirements: no sensitive secrets in the codebase, ever; CI/CD stays OIDC + least-privilege + injection-safe.

Both must return an explicit **"approve"** or a findings list — silence is not approval. Findings → `SendMessage` to the ORIGINAL coding agent (it still has its worktree) with the exact findings; it fixes, re-runs its gates, reports. Re-review the disputed points only. **Two failed rounds → task `failed`**, branch **and worktree** kept intact for inspection (never reclaimed for a `failed` task), user informed at §6.

## 5. Coding-agent prompt (fill {…}, include verbatim)

> You are implementing task **{ID}** — {scope} — of the Findly backlog, alone, in an isolated git worktree. **First thing: `git checkout -b devloop/{ID}`** so your branch name is deterministic — the orchestrator merges and messages you by it; do all work there and never touch `main`.
> Read in order: `CLAUDE.md`, your task's row and any per-task checklist in `docs/implementation-handoff.md`, then every spec section your task references ({spec refs}). The specs are the contract: if anything is ambiguous or contradictory, STOP and report the ambiguity instead of guessing — the orchestrator will resolve it via a spec fix.
> Non-negotiable process: strict TDD. Write failing tests first, RUN them and capture the red output, implement minimally, refactor. All of `npm test`, `npm run mutation`, `npm run build` must pass in `backend/` before you finish. Never commit secrets or realistic-looking placeholder credentials (`docs/security-review-checklist.md` — your diff will be security-reviewed against it). Do not touch anything outside your task's scope.
> Commit in small, spec-referencing commits on your branch; leave zero uncommitted changes.
> Your final report is machine-consumed — include: task ID; branch name (`git rev-parse --abbrev-ref HEAD`); worktree path; files changed; test names + the red-run proof and final green tail; mutation score; open questions/blockers (empty if none).

## 6. End of loop — report

- Per task: `done` (merge commit) / `failed` (why, branch name) / still blocked (on which IDs).
- Review-gate totals: findings raised and fixed, by category.
- Backlog table and Dev-loop log are updated; remind the user of `human` tasks (e.g. H1 Azure setup) that now block the frontier, and of `failed` branches awaiting a decision.
- **Worktree hygiene:** confirm every `done` task's worktree+branch was reclaimed (§3.6); run `git worktree list` and surface anything still on disk (expected only for `failed`/interrupted tasks) so nothing lingers silently.
- Suggest the natural next invocation (e.g. "H1 unblocks A1/I1; run `/dev-loop parallel 2 A1 I1` after completing it").

## Notes

- Two backend tasks may touch the same files (`src/http`, `src/ports`); worktree isolation + sequential merging with the integration gate is the conflict strategy — do not pre-serialize tasks just because overlap is possible.
- If the user interrupts mid-wave, the backlog table's `in-progress`/`review` markers plus surviving branches are the resume state (§2.2).
- Never lower mutation thresholds, never skip the review gate, never merge with a red integration gate — no exceptions, including "just this once".
