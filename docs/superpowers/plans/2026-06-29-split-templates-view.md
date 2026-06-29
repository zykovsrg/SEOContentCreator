# Split TemplatesView Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split `TemplatesView.swift` into focused editor files without changing app behavior.

**Architecture:** Keep `TemplatesView.swift` responsible for the sidebar, selection, sorting, and detail routing. Move each editor view into `Views/Templates/` as an internal SwiftUI view so the main view can instantiate it across file boundaries.

**Tech Stack:** SwiftUI, SwiftData, macOS AppKit file picker, Xcode 16 file-system-synced project.

---

### Task 1: Preserve Main Templates Screen

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Views/TemplatesView.swift`

- [ ] **Step 1: Keep only main-screen code in `TemplatesView.swift`**

Remove the editor view declarations from the bottom of the file, leaving imports, `TemplateSelection`, `TemplatesView`, sorting helpers, detail routing, and `ensureSelection()`.

- [ ] **Step 2: Trim imports**

Keep only imports used by the main screen:

```swift
import SwiftUI
import SwiftData
```

### Task 2: Create Editor Files

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Views/Templates/TemplateEditorView.swift`
- Create: `SEOContentCreator/SEOContentCreator/Views/Templates/RoleEditorView.swift`
- Create: `SEOContentCreator/SEOContentCreator/Views/Templates/ContextBlockEditorView.swift`
- Create: `SEOContentCreator/SEOContentCreator/Views/Templates/ImagePromptEditorView.swift`
- Create: `SEOContentCreator/SEOContentCreator/Views/Templates/ImageStylePresetEditorView.swift`
- Create: `SEOContentCreator/SEOContentCreator/Views/Templates/EditorDictionaryEditorView.swift`
- Create: `SEOContentCreator/SEOContentCreator/Views/Templates/SkillEditorView.swift`
- Create: `SEOContentCreator/SEOContentCreator/Views/Templates/ProductBlockEditorView.swift`

- [ ] **Step 1: Move existing code without behavior edits**

Copy each editor view body exactly, changing `private struct` to `struct` so `TemplatesView.swift` can use the types from another file.

- [ ] **Step 2: Add needed imports per file**

Use `import SwiftUI` for all editor files, `import SwiftData` for files that use `@Environment(\.modelContext)`, and `import AppKit` plus `import UniformTypeIdentifiers` for the image style preset file.

### Task 3: Verify Refactor

**Files:**
- Verify all changed Swift files.

- [ ] **Step 1: Build**

Run:

```bash
xcodebuild -project SEOContentCreator/SEOContentCreator.xcodeproj -scheme SEOContentCreator -destination 'platform=macOS' build
```

Expected: exit code `0`.

- [ ] **Step 2: Check diff**

Run:

```bash
git diff --name-only
```

Expected: only task memory, plan, and intended Swift file split are present, plus any pre-existing user-local Xcode state.
