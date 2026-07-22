# Prompts Snapshot

Point-in-time export of user-edited prompt data from the app's local SwiftData
store (`~/Library/Containers/com.zykovsrg.SEOContentCreator/Data/Library/Application Support/default.store`),
which is not otherwise versioned in git.

- `stage_templates.json` — `StageTemplate` rows (per-stage prompts, model, temperature, etc.)
- `context_blocks.json` — `ContextBlock` rows, including `editorialPolicy` (редполитика)
- `ai_roles.json` — `AIRole` rows (mandate text per AI role, decoded `blockKeys`)

This is a manual snapshot, not a live sync. Re-export after significant edits
in the app's "Этапы" screen if you want the repo to reflect the latest state.
