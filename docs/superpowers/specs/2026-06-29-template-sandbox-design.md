# Template Sandbox for Stage Prompts — Design

Date: 2026-06-29

## Goal

Add a safe sandbox for testing stage prompt edits before saving them or applying them to a topic.

This is the first slice of `FT-20260623-007`. It covers only stage prompts in the "Промты этапов" section. Product blocks, skill presets, template import/export, and full database backup stay out of scope.

## User Value

The editor can change a stage prompt, run it against an existing topic, and inspect the model output without changing the saved template or the topic version history. This lowers the risk of prompt editing: experiments become reversible because they do not touch persistent article data.

## Scope

In scope:

- Add a "Песочница" action to the stage prompt editor.
- Run the current editor fields, including unsaved text, as a temporary `StageTemplate`.
- Let the user choose an existing topic as test input.
- Show the streamed model output and any error or truncation warning.
- Guarantee the sandbox does not create `GenerationJob`, `ArticleVersion`, or change `Topic.currentVersionID`.
- Add focused unit tests for the non-persistent executor path.

Out of scope:

- Product block sandboxing.
- Skill preset sandboxing.
- Template import/export.
- Full SwiftData backup/export.
- Saving sandbox results into a topic.
- Comparing sandbox output with current text through the accept/reject workflow.

## UI Design

`TemplateEditorView` gets a new secondary button near "Сохранить":

- "Песочница"

The button opens `TemplateSandboxSheet`.

The sheet contains:

- stage title;
- a topic picker listing existing topics;
- a short preview of the selected topic context: title, article type, direction, and whether it has current text;
- a "Запустить" button;
- progress indicator while streaming;
- a read-only output area with the streamed result;
- red error text for failures;
- orange warning text when the model output is truncated.

The sheet does not include save/accept buttons. Closing the sheet discards the transient result.

## Data Flow

`TemplateEditorView` already keeps editable local state:

- `system`
- `user`
- `model`
- `temperature`
- `maxTokens`
- `reasoningEffort`

When opening the sandbox, those local values are passed into the sheet. The sandbox constructs a temporary, unsaved `StageTemplate` object from those values and the original stage.

The sandbox then calls a new transient executor method:

```swift
executeSandbox(stage:topic:template:currentText:in:)
```

The method reuses existing behavior:

- `PromptBuilder` for variable substitution;
- `AIRole` and `ContextBlock` assembly;
- `OpenAIClient` streaming through `StageExecutor.live(...)`;
- the existing warning for `finish(reason: "length")`;
- the existing Keychain error message when the API key is missing.

Unlike `execute(...)`, the sandbox method does not insert or update persistent models.

## Persistence Rules

Sandbox runs must not:

- mutate the selected `StageTemplate`;
- insert `GenerationJob`;
- insert `ArticleVersion`;
- update `Topic.currentVersionID`;
- update `Topic.updatedAt`;
- archive versions;
- save remarks as accepted changes.

It may keep transient data only in `StageExecutor`:

- `streamingText`;
- `isRunning`;
- `lastErrorMessage`;
- `lastWarningMessage`;
- optionally `remarks` for checking stages.

## Checking Stages

If the selected stage is a checking stage, the first implementation may show the raw streamed output in the same output area. It may also populate `remarks` internally if this is cheap to reuse, but the UI does not need accept/reject controls in this slice.

This keeps the sandbox consistent: it previews model behavior, not article editing.

## Architecture Notes

The main reusable unit is the new non-persistent executor path in `StageExecutor`. This avoids duplicating OpenAI streaming, role context, warning, and error handling in SwiftUI.

`TemplateSandboxSheet` should stay separate from `TemplatesView.swift` if possible, because `TemplatesView.swift` is already large. The sheet can live in `Views/TemplateSandboxSheet.swift`.

No SwiftData schema change is required.

## Testing

Automated tests:

- `StageExecutor.executeSandbox` streams output into `streamingText`.
- It does not create `GenerationJob`.
- It does not create `ArticleVersion`.
- It does not change `Topic.currentVersionID`.
- It forwards `reasoningEffort` from the temporary template.
- It uses the passed temporary prompt text, so unsaved editor changes are testable.

Manual checks:

- Open "Шаблоны" → "Промты этапов".
- Edit a prompt without saving.
- Open "Песочница".
- Choose a topic and run.
- Confirm output streams.
- Close the sheet.
- Confirm the template version did not change.
- Confirm the topic version lane did not gain a new version.

## Risks

- `TemplatesView.swift` may become more crowded. Mitigation: put the sheet in a separate file and keep the editor change to a button plus sheet state.
- Running a real model costs tokens. Mitigation: the user must click "Запустить"; there is no automatic run.
- Checking stages produce structured JSON remarks, not normal prose. Mitigation: first slice can show raw output; richer rendering can be a future task.

## Acceptance Criteria

- Stage prompt editor has a sandbox entry point.
- Sandbox runs the current unsaved editor fields.
- Sandbox uses a selected existing topic as input.
- Sandbox output is visible while streaming and after completion.
- No topic version, job log entry, or template save is created by sandbox runs.
- Focused unit tests pass.
