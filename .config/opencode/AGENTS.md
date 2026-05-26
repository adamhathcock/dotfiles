## Tool usage priority

When working in a project opened in Rider, prefer project-aware tools before generic filesystem or shell tools.

1. Use `rider_execute_tool` first for Rider-backed project navigation, code search, file reads, edits, refactors, formatting, diagnostics, builds, run configurations, debugging, Git status, and database work.
2. Use regular file, shell, and text-search tools only when Rider tools are unavailable, insufficient, or not applicable.

Prefer semantic/project-aware operations over plain text operations:

- Use `rider_execute_tool` for Rider searches before `glob`/`grep` when the project is available in Rider.
- Use `rider_execute_tool` for project file reads before generic file reads.
- Use `rider_execute_tool` for Rider refactors, formatting, and patches before manual text edits where they fit the task.
- Use `rider_execute_tool` for Rider diagnostics, linting, project problems, and solution builds before CLI build or diagnostic fallbacks.
- Use `rider_execute_tool` for Rider run/debug actions before invoking project run commands manually.

Do not replace Rider semantic results with `dotnet build` output, shell searches, or other CLI fallbacks unless Rider cannot answer the question.

## Git Staging Guidance for AI Agents

When modifying this repository:

- Do **not** treat staged files (`git add`) as finalized or protected.
- Staged changes may represent **work-in-progress or local review**, not completed work.
- You may freely modify, update, or overwrite staged files if required.
- Do **not** attempt to preserve staged state or infer intent from the staging area.
- Do **not** run `git restore --staged`, `git reset`, or similar commands unless explicitly instructed.
- Focus on the **working tree content**, not Git index state, when making decisions.

Rationale: Staging is used locally as part of an iterative workflow and does not signal completion.
s
