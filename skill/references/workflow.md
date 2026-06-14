# grok-bridge — workflow & decision guide

## Which command?

- Plain second-opinion on local changes → `review`.
- Want grok to *stress-test* a design/change, find what breaks → `adversarial-review`.
- Want grok to actually write a focused fix → `rescue "<task>"`.

## grok vs agy (the sibling skill)

- **grok** = stronger reasoning, a genuine second opinion, and a *hard* read-only
  mode. Prefer grok for review, adversarial critique, security-sensitive reads.
- **agy** = fast drafts, docs, tests, bulk edits. No enforced read-only mode.
- If the user wants a trustworthy read-only review, use grok. If they want a quick
  implementation draft and speed matters, agy is fine.

## Presenting results

- `review` / `adversarial-review`: read `result.md` and relay grok's findings.
  Keep grok's severity ordering. Do not start fixing unless the user asks.
- These are a *second opinion*, not ground truth — flag disagreements with your
  own analysis rather than deferring blindly.

## Applying a `rescue` diff (write commands)

grok never touches the live tree. To integrate:

1. Read `changes.diff` and `result.md`; show the user the proposed change.
2. Get explicit approval.
3. Apply from the repo root:
   ```bash
   git apply <repo>/.ai-runs/grok/<job-id>/changes.diff
   ```
   If `git apply` fails (context drift), re-create the edits manually from the
   diff rather than force-applying.
4. Verify (build/tests) before considering it done.

## Iterating

Each run is independent and writes a new `.ai-runs/grok/<job-id>/`. To refine a
rescue, run it again with a sharper task description; compare diffs.
