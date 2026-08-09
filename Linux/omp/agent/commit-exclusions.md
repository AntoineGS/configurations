# Commit Exclusions

NEVER commit design documents, implementation documents, implementation plans, or similar planning artifacts. This includes:

- Files in `docs/plans/`, `docs/specs/`, or equivalent planning directories
- Files with `design`, `implementation`, `plan`, `spec`, or `architecture` in the filename when they are planning artifacts
- Any planning or specification documents created during development

These documents are for local reference only. If they appear in `git status`, explicitly exclude them from staging and commits, including when the user asks to commit all changes.
