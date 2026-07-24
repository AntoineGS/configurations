# LSP-First Code Intelligence

When an LSP is available for a language involved in a task, use the LSP first for every operation it supports, including symbol navigation, definitions, references, diagnostics, hover and type information, and workspace symbol searches.

Fall back to text search or manual inspection only when the LSP is unavailable, fails, or does not support the required operation. Do not skip the LSP merely because another approach appears faster.
