## Tool usage priority

When working in a project opened in Rider, prefer project-aware tools in this order:

1. Use Rider tools first for project navigation, code search, reads, edits, refactors, formatting, diagnostics, builds, run configurations, debugging, Git status, and database work.
2. Use LSP/Roslyn-backed tools second when Rider tools do not cover the needed operation or when a C#-specific semantic result is required.
3. Use regular file, shell, and text-search tools only as a fallback when Rider and LSP/Roslyn tools are unavailable, insufficient, or not applicable.

Prefer semantic/project-aware operations over plain text operations:

- Use `rider_search_symbol`, `rider_search_text`, `rider_search_regex`, `rider_search_file`, or `rider_skill_search` before `glob`/`grep` when the project is available in Rider.
- Use `rider_read_file` before generic file reads for project files.
- Use Rider refactoring tools such as `rider_rename_refactoring`, `rider_move_type_to_namespace`, `rider_reformat_file`, and `rider_apply_patch` before manual text edits where they fit the task.
- Use `rider_get_file_problems`, `rider_lint_files`, `rider_get_project_problems`, and `rider_build_solution` before CLI build or diagnostic fallbacks.
- Use Rider run/debug tools before invoking project run commands manually.

Do not replace Rider or Roslyn semantic results with `dotnet build` output, shell searches, or other CLI fallbacks unless the higher-priority tools cannot answer the question.

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