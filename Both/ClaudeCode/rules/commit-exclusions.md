# Commit Exclusions

## Never Commit Design or Implementation Documents

NEVER include design documents, implementation plans, or similar planning files in git commits. This includes:

- Files in `docs/plans/` directories
- Files with "design" or "implementation" in the filename
- Any planning, architecture, or specification documents created during development

These documents are for local reference only and must not be committed to the repository.

If asked to commit and such files appear in `git status`, explicitly exclude them from staging.
