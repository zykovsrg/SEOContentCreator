# Drive Image Upload + Tech-Info Section Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upload selected article images to a per-article Google Drive subfolder at publish time, and append an H2 «Техническая информация» section to the article text when the «Финальная вычитка» stage completes.

**Architecture:** Pure-logic builders (`TechInfoSectionBuilder`, `ImageDriveUploader` naming/orchestration) tested offline with mocks; `GoogleDocsClient` gains parent-aware folder lookup and multipart upload; `ArticlePublisher` orchestrates upload → link substitution → doc publish; UI wiring in `TopicWorkspaceView`, `BriefView`, `PublishSheet`. Spec: `docs/superpowers/specs/2026-07-20-drive-images-tech-info-design.md`.

**Tech Stack:** Swift / SwiftUI / SwiftData, Swift Testing (`@Test`/`#expect`), Google Drive REST v3.

**Verification constraint (project-wide):** CLI `xcodebuild test` hangs (known issue — see memory `xcodebuild-test-runner-hang`). Compile checks use:

```bash
cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | tail -5
```

Expected: `TEST BUILD SUCCEEDED`. Actual test *execution* happens once, at the final checkpoint, via Cmd+U in Xcode (user-run). So "write failing test" steps verify by compile + code review of the assertion, not by observing a red run.

**Deviation from spec (intentional):** images upload **before** the doc is created/updated, not after — so the real folder link lands in the published document on the very first publish. If upload fails, the doc still publishes with the placeholder and a warning is shown. This matches the spec's intent (link substituted at publish).

---

### Task 1: TechInfoSectionBuilder (pure logic)

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Logic/TechInfoSectionBuilder.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/TechInfoSectionBuilderTests.swift`

- [ ] **Step 1: Write the tests**

```swift
import Testing
import Foundation
import SwiftData
@testable import SEOContentCreator

struct TechInfoSectionBuilderTests {

    @Test func sectionPathMapsArticleTypes() {
        #expect(TechInfoSectionBuilder.sectionPath(for: .disease) == "/deseases/")
        #expect(TechInfoSectionBuilder.sectionPath(for: .service) == "/services/")
        #expect(TechInfoSectionBuilder.sectionPath(for: .info) == "/article/")
    }

    @Test func buildFillsAllKnownFields() {
        let section = TechInfoSectionBuilder.build(
            seoTitle: "Лечение цистита", seoDescription: "Описание страницы",
            expert: "Иванова А. А.", directions: ["Урология", "Андрология"],
            articleType: .service)
        #expect(section.hasPrefix("## Техническая информация"))
        #expect(section.contains("Тайтл: Лечение цистита"))
        #expect(section.contains("Дескрипшн: Описание страницы"))
        #expect(section.contains("Эксперт: Иванова А. А."))
        #expect(section.contains("Врачи отделения: [вписать вручную]"))
        #expect(section.contains("Направления: Урология, Андрология"))
        #expect(section.contains("Раздел: /services/"))
        #expect(section.contains("URL: [вписать вручную]"))
        #expect(section.contains("Иллюстрации: [появится при публикации]"))
    }

    @Test func buildFallsBackToManualPlaceholders() {
        let section = TechInfoSectionBuilder.build(
            seoTitle: nil, seoDescription: "  ", expert: nil,
            directions: [], articleType: .disease)
        #expect(section.contains("Тайтл: [вписать вручную]"))
        #expect(section.contains("Дескрипшн: [вписать вручную]"))
        #expect(section.contains("Эксперт: [вписать вручную]"))
        #expect(section.contains("Направления: [вписать вручную]"))
    }

    @Test func appendAddsSectionOnce() {
        let section = TechInfoSectionBuilder.build(
            seoTitle: "T", seoDescription: "D", expert: nil,
            directions: [], articleType: .info)
        let once = TechInfoSectionBuilder.append(to: "# Статья\n\nТекст.", section: section)
        #expect(once.hasSuffix(section))
        #expect(once.contains("# Статья"))
        let twice = TechInfoSectionBuilder.append(to: once, section: section)
        #expect(twice == once)  // idempotent
    }

    @Test func substituteReplacesIllustrationsPlaceholder() {
        let text = "Текст\n\n## Техническая информация\n\nИллюстрации: [появится при публикации]"
        let out = TechInfoSectionBuilder.substituteIllustrationsLink(
            in: text, url: "https://drive.google.com/drive/folders/abc")
        #expect(out.contains("Иллюстрации: https://drive.google.com/drive/folders/abc"))
        #expect(!out.contains("[появится при публикации]"))
        // No placeholder → text unchanged.
        #expect(TechInfoSectionBuilder.substituteIllustrationsLink(in: "чистый текст", url: "u") == "чистый текст")
    }

    @Test @MainActor func sectionForTopicGathersData() throws {
        let container = try ModelContainer(
            for: Topic.self, KnowledgeNode.self, ArticleVersion.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(container)
        let direction = KnowledgeNode(title: "Урология", type: .direction)
        let extra = KnowledgeNode(title: "Андрология", type: .direction)
        let doctor = KnowledgeNode(title: "Петров П. П.", type: .doctor)
        ctx.insert(direction); ctx.insert(extra); ctx.insert(doctor)
        let topic = Topic(title: "Тема", articleType: .service, direction: direction, doctor: doctor)
        topic.additionalDirections = [extra]
        ctx.insert(topic)
        let v = ArticleVersion(stage: .semanticsInText, source: .generated, text: "Текст")
        v.seoTitle = "SEO тайтл"; v.seoDescription = "SEO дескрипшн"
        v.topic = topic; ctx.insert(v)
        topic.currentVersionID = v.uuid

        let section = TechInfoSectionBuilder.section(for: topic)
        #expect(section.contains("Тайтл: SEO тайтл"))
        #expect(section.contains("Дескрипшн: SEO дескрипшн"))
        #expect(section.contains("Эксперт: Петров П. П."))
        #expect(section.contains("Направления: Урология, Андрология"))
        #expect(section.contains("Раздел: /services/"))
    }

    @Test @MainActor func sectionForTopicFallsBackToLatestSEOFields() throws {
        // checkApplied versions don't carry seoTitle; the builder must look back
        // through older versions for the newest non-empty values.
        let container = try ModelContainer(
            for: Topic.self, KnowledgeNode.self, ArticleVersion.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(container)
        let topic = Topic(title: "Тема", articleType: .info)
        ctx.insert(topic)
        let old = ArticleVersion(stage: .semanticsInText, source: .generated, text: "Старый")
        old.seoTitle = "Тайтл из семантики"; old.topic = topic; ctx.insert(old)
        let current = ArticleVersion(stage: .factCheck, source: .checkApplied, text: "Новый")
        current.topic = topic; ctx.insert(current)
        topic.currentVersionID = current.uuid

        let section = TechInfoSectionBuilder.section(for: topic)
        #expect(section.contains("Тайтл: Тайтл из семантики"))
    }
}
```

Note: `topic.additionalDirections` does not exist until Task 2 — that's expected; this test file will not compile until Task 2 lands. Tasks 1 and 2 are committed together at the end of Task 2 if you prefer green builds per commit; otherwise implement Task 1's builder with `additionalDirections` usage and commit both tasks in one go. **Recommended order: do Task 2 (model fields) first, then Task 1 — the plan keeps them as written for readability, but execution order is 2 → 1.**

- [ ] **Step 2: Write the implementation**

```swift
import Foundation

/// Builds the «Техническая информация» section that is appended to the end of
/// the article text when the «Финальная вычитка» stage completes, and later
/// updated at publish time (illustrations folder link).
enum TechInfoSectionBuilder {
    static let header = "## Техническая информация"
    static let manualPlaceholder = "[вписать вручную]"
    static let illustrationsPlaceholder = "[появится при публикации]"
    private static let illustrationsLinePrefix = "Иллюстрации: "

    /// Site section path by article type. Paths use the site's own spelling
    /// (including «deseases») — agreed with the user 2026-07-20.
    static func sectionPath(for type: ArticleType) -> String {
        switch type {
        case .disease: return "/deseases/"
        case .service: return "/services/"
        case .info:    return "/article/"
        }
    }

    static func build(seoTitle: String?, seoDescription: String?, expert: String?,
                      directions: [String], articleType: ArticleType) -> String {
        func filled(_ value: String?) -> String {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? manualPlaceholder : trimmed
        }
        let directionsLine = directions.isEmpty ? manualPlaceholder : directions.joined(separator: ", ")
        return """
        \(header)

        Тайтл: \(filled(seoTitle))
        Дескрипшн: \(filled(seoDescription))
        Эксперт: \(filled(expert))
        Врачи отделения: \(manualPlaceholder)
        Направления: \(directionsLine)
        Раздел: \(sectionPath(for: articleType))
        URL: \(manualPlaceholder)
        \(illustrationsLinePrefix)\(illustrationsPlaceholder)
        """
    }

    /// Appends the section unless the text already contains one (idempotent).
    static func append(to text: String, section: String) -> String {
        guard !text.contains(header) else { return text }
        return text + "\n\n" + section
    }

    /// Gathers section data from the topic. SEO title/description come from the
    /// current version, falling back to the newest older version that has them
    /// (checkApplied versions don't carry SEO fields).
    static func section(for topic: Topic) -> String {
        let byDate = topic.versions.sorted { $0.createdAt > $1.createdAt }
        func newest(_ keyPath: KeyPath<ArticleVersion, String?>) -> String? {
            if let value = topic.currentVersion?[keyPath: keyPath],
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return value }
            return byDate.compactMap { $0[keyPath: keyPath] }
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        let directions = ([topic.direction].compactMap { $0 } + topic.additionalDirections).map(\.title)
        return build(
            seoTitle: newest(\.seoTitle),
            seoDescription: newest(\.seoDescription),
            expert: topic.doctor?.title,
            directions: directions,
            articleType: topic.articleType)
    }

    /// Replaces the illustrations placeholder line value with the real folder URL.
    static func substituteIllustrationsLink(in text: String, url: String) -> String {
        text.replacingOccurrences(
            of: illustrationsLinePrefix + illustrationsPlaceholder,
            with: illustrationsLinePrefix + url)
    }
}
```

- [ ] **Step 3: Build to verify compile** (after Task 2 if executing in 2 → 1 order)

Run: `cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `TEST BUILD SUCCEEDED`

- [ ] **Step 4: Commit** (together with Task 2)

```bash
git add SEOContentCreator/SEOContentCreator/Logic/TechInfoSectionBuilder.swift \
        SEOContentCreator/SEOContentCreatorTests/TechInfoSectionBuilderTests.swift
git commit -m "feat: TechInfoSectionBuilder for «Техническая информация» section"
```

---

### Task 2: Model fields (Topic, GeneratedImage, KnowledgeNodeUsage)

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Models/Topic.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Models/GeneratedImage.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Logic/KnowledgeNodeUsage.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/KnowledgeNodeUsageTests.swift` (extend)

All three additions are lightweight-migratable (new optional / new empty to-many relationship); existing data is untouched.

- [ ] **Step 1: Add fields to `Topic`**

In the property block (after `var coverImageID: UUID?`):

```swift
    /// Ссылка на подпапку Google Drive с иллюстрациями этой статьи.
    /// Появляется после первой публикации с загрузкой картинок.
    var illustrationsFolderURL: String?
```

After the `doctor` relationship:

```swift
    /// Дополнительные направления для раздела «Техническая информация».
    /// Основное `direction` остаётся единственным источником для промтов.
    @Relationship var additionalDirections: [KnowledgeNode] = []
```

In `init`, alongside `self.attachedNodes = []`:

```swift
        self.additionalDirections = []
```

- [ ] **Step 2: Add `driveFileID` to `GeneratedImage`**

Property (after `var modelName: String?`):

```swift
    /// ID файла на Google Диске после загрузки при публикации; nil — не загружен.
    var driveFileID: String?
```

In `init` (before `self.isArchived = false`):

```swift
        self.driveFileID = nil
```

- [ ] **Step 3: Count additional directions in `KnowledgeNodeUsage`**

```swift
enum KnowledgeNodeUsage {
    static func count(for node: KnowledgeNode, in topics: [Topic]) -> Int {
        topics.filter { topic in
            topic.direction === node
                || topic.doctor === node
                || topic.attachedNodes.contains(where: { $0 === node })
                || topic.additionalDirections.contains(where: { $0 === node })
        }.count
    }
}
```

- [ ] **Step 4: Extend `KnowledgeNodeUsageTests`**

Add one test following the file's existing style (open the file first and mirror its container setup):

```swift
    @Test func countsAdditionalDirections() throws {
        // Mirror the existing test setup in this file for container/context creation.
        let node = KnowledgeNode(title: "Андрология", type: .direction)
        let topic = Topic(title: "Тема", articleType: .info)
        topic.additionalDirections = [node]
        #expect(KnowledgeNodeUsage.count(for: node, in: [topic]) == 1)
    }
```

- [ ] **Step 5: Build to verify compile**

Run: `cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `TEST BUILD SUCCEEDED`

- [ ] **Step 6: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Models/Topic.swift \
        SEOContentCreator/SEOContentCreator/Models/GeneratedImage.swift \
        SEOContentCreator/SEOContentCreator/Logic/KnowledgeNodeUsage.swift \
        SEOContentCreator/SEOContentCreatorTests/KnowledgeNodeUsageTests.swift
git commit -m "feat: additionalDirections + illustrationsFolderURL on Topic, driveFileID on GeneratedImage"
```

---

### Task 3: Append tech-info section when «Финальная вычитка» completes

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Views/TopicWorkspaceView.swift` (`finishReview()` ~line 533, zero-remarks branch in `runStage` ~line 482)

Two completion paths for a checking stage: remarks applied via `finishReview()`, or zero remarks (`checkedWithNoRemarks`). Both must append the section for `.finalReview`. Logic lives in `TechInfoSectionBuilder` (tested in Task 1); this task is thin wiring.

- [ ] **Step 1: Modify `finishReview()`**

Replace the existing method with:

```swift
    private func finishReview() {
        let base = reviewBaseText
        let accepted = (executor?.remarks ?? []).filter { acceptedRemarkIDs.contains($0.id) }
        var result = RemarkApplier.apply(base: base, accepted: accepted)
        if selectedStage == .finalReview {
            result = TechInfoSectionBuilder.append(to: result, section: TechInfoSectionBuilder.section(for: topic))
        }
        if result != base {
            let version = ArticleVersion(stage: selectedStage, source: .checkApplied, text: result)
            version.status = .accepted
            version.h1 = topic.currentVersion?.h1
            version.seoTitle = topic.currentVersion?.seoTitle
            version.seoDescription = topic.currentVersion?.seoDescription
            version.topic = topic
            context.insert(version)
            topic.currentVersionID = version.uuid
            topic.updatedAt = .now
        }
        endReview()
    }
```

(Carrying `h1`/`seoTitle`/`seoDescription` forward keeps the publish pipeline's H1 normalization working for the new version; previously checkApplied versions dropped them.)

- [ ] **Step 2: Handle the zero-remarks path**

In `runStage`, replace:

```swift
            if stage.kind == .checking && executor.remarks.isEmpty && executor.lastErrorMessage == nil {
                checkedWithNoRemarks = true
            }
```

with:

```swift
            if stage.kind == .checking && executor.remarks.isEmpty && executor.lastErrorMessage == nil {
                checkedWithNoRemarks = true
                if stage == .finalReview { appendTechInfoIfNeeded() }
            }
```

and add the helper next to `finishReview()`:

```swift
    /// «Финальная вычитка» прошла без замечаний: дописываем раздел
    /// «Техническая информация» отдельной принятой версией (если его ещё нет).
    private func appendTechInfoIfNeeded() {
        guard let current = topic.currentVersion else { return }
        let appended = TechInfoSectionBuilder.append(
            to: current.text, section: TechInfoSectionBuilder.section(for: topic))
        guard appended != current.text else { return }
        let version = ArticleVersion(stage: .finalReview, source: .checkApplied, text: appended)
        version.status = .accepted
        version.h1 = current.h1
        version.seoTitle = current.seoTitle
        version.seoDescription = current.seoDescription
        version.topic = topic
        context.insert(version)
        topic.currentVersionID = version.uuid
        topic.updatedAt = .now
    }
```

- [ ] **Step 3: Build to verify compile**

Run: `cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `TEST BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Views/TopicWorkspaceView.swift
git commit -m "feat: append «Техническая информация» section on finalReview completion"
```

---

### Task 4: Additional directions in BriefView

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Views/BriefView.swift`

- [ ] **Step 1: Add state**

After `@State private var notes = ""`:

```swift
    @State private var additionalDirections: [KnowledgeNode] = []
    @State private var newDirectionTitle = ""
```

- [ ] **Step 2: Add the section to the Form**

After the `Picker("Врач", ...)` block:

```swift
            Section("Дополнительные направления") {
                ForEach(directions) { node in
                    if node !== direction {
                        Toggle(node.title, isOn: Binding(
                            get: { additionalDirections.contains(where: { $0 === node }) },
                            set: { isOn in
                                if isOn { additionalDirections.append(node) }
                                else { additionalDirections.removeAll { $0 === node } }
                            }
                        ))
                    }
                }
                HStack {
                    TextField("Новое направление", text: $newDirectionTitle)
                    Button("Создать") { createDirection() }
                        .disabled(newDirectionTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
```

- [ ] **Step 3: Add creation helper, extend `load()`/`save()`**

New private method:

```swift
    private func createDirection() {
        let title = newDirectionTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let node = KnowledgeNode(title: title, type: .direction)
        context.insert(node)
        additionalDirections.append(node)
        newDirectionTitle = ""
    }
```

In `load()` add:

```swift
        additionalDirections = topic.additionalDirections
```

In `save()`, existing-topic branch add (primary direction is filtered out so it never appears twice in the tech-info section):

```swift
            topic.additionalDirections = additionalDirections.filter { $0 !== direction }
```

New-topic branch, after `context.insert(new)`:

```swift
            new.additionalDirections = additionalDirections.filter { $0 !== direction }
```

- [ ] **Step 4: Build to verify compile**

Run: `cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `TEST BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Views/BriefView.swift
git commit -m "feat: multi-select additional directions with inline creation in brief"
```

---

### Task 5: GoogleDocsClient — parent-aware folders + multipart upload

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Logic/GoogleDocsClient.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/GoogleDocsClientTests.swift` (extend)

- [ ] **Step 1: Write tests for the pure helpers**

Open `GoogleDocsClientTests.swift`, mirror its style, add:

```swift
    @Test func multipartBodyHasMetadataAndFileParts() {
        let body = GoogleDocsClient.multipartBody(
            metadataJSON: Data("{\"name\":\"x.png\"}".utf8),
            fileData: Data([0x89, 0x50]),
            mimeType: "image/png",
            boundary: "BOUND")
        let text = String(decoding: body, as: UTF8.self)
        #expect(text.contains("--BOUND\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n{\"name\":\"x.png\"}"))
        #expect(text.contains("--BOUND\r\nContent-Type: image/png\r\n\r\n"))
        #expect(text.hasSuffix("\r\n--BOUND--\r\n"))
    }

    @Test func escapeQueryValueEscapesQuotesAndBackslashes() {
        #expect(GoogleDocsClient.escapeQueryValue("O'Brien") == "O\\'Brien")
        #expect(GoogleDocsClient.escapeQueryValue("a\\b") == "a\\\\b")
        #expect(GoogleDocsClient.escapeQueryValue("обычное имя") == "обычное имя")
    }

    @Test func folderURLBuildsDriveLink() {
        #expect(GoogleDocsClient.folderURL(id: "abc123") == "https://drive.google.com/drive/folders/abc123")
    }
```

- [ ] **Step 2: Refactor `send` to support raw bodies**

Replace the existing private `send(url:method:json:)` with a thin wrapper plus a core method (retry/backoff/401 logic moves unchanged into the core):

```swift
    private func send(url: URL, method: String, json: [String: Any]?) async throws -> Data {
        var body: Data?
        if let json { body = try JSONSerialization.data(withJSONObject: json) }
        return try await send(url: url, method: method, body: body,
                              contentType: json == nil ? nil : "application/json")
    }

    private func send(url: URL, method: String, body: Data?, contentType: String?) async throws -> Data {
        var lastError: Error = DocsError.badResponse
        for attempt in 0..<maxAttempts {
            do {
                let token = try await tokenProvider()
                var req = URLRequest(url: url)
                req.httpMethod = method
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                if let contentType { req.setValue(contentType, forHTTPHeaderField: "Content-Type") }
                req.httpBody = body
                let (data, resp) = try await session.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                switch code {
                case 200...299: return data
                case 401: throw DocsError.unauthorized
                case 429, 500...599:
                    lastError = DocsError.http(code)
                    try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 0.5 * 1_000_000_000))
                    continue
                default: throw DocsError.http(code)
                }
            } catch let e as DocsError where e == .unauthorized {
                throw e
            } catch {
                lastError = error
                try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 0.5 * 1_000_000_000))
            }
        }
        throw lastError
    }
```

- [ ] **Step 3: Add the new public API**

```swift
    /// Escapes a value for use inside single quotes in a Drive `q` query.
    static func escapeQueryValue(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
             .replacingOccurrences(of: "'", with: "\\'")
    }

    static func folderURL(id: String) -> String {
        "https://drive.google.com/drive/folders/\(id)"
    }

    /// Finds or creates a folder INSIDE the given parent (unlike the root-level
    /// `findOrCreateFolder(name:)` above).
    func findOrCreateFolder(name: String, parentID: String) async throws -> String {
        var comps = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        let escaped = Self.escapeQueryValue(name)
        let q = "mimeType='application/vnd.google-apps.folder' and name='\(escaped)' and '\(parentID)' in parents and trashed=false"
        comps.queryItems = [URLQueryItem(name: "q", value: q), URLQueryItem(name: "fields", value: "files(id,name)")]
        let data = try await send(url: comps.url!, method: "GET", json: nil)
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let files = obj["files"] as? [[String: Any]],
           let id = files.first?["id"] as? String {
            return id
        }
        let createURL = URL(string: "https://www.googleapis.com/drive/v3/files")!
        let created = try await send(url: createURL, method: "POST",
            json: ["name": name, "mimeType": "application/vnd.google-apps.folder", "parents": [parentID]])
        guard let obj = try? JSONSerialization.jsonObject(with: created) as? [String: Any],
              let id = obj["id"] as? String else { throw DocsError.badResponse }
        return id
    }

    /// Multipart body for `uploadType=multipart` (metadata JSON + file bytes).
    static func multipartBody(metadataJSON: Data, fileData: Data, mimeType: String, boundary: String) -> Data {
        var body = Data()
        func add(_ s: String) { body.append(Data(s.utf8)) }
        add("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n")
        body.append(metadataJSON)
        add("\r\n--\(boundary)\r\nContent-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        add("\r\n--\(boundary)--\r\n")
        return body
    }

    /// Uploads a file into the given folder. Returns the created file's ID.
    func uploadFile(name: String, data: Data, mimeType: String, parentID: String) async throws -> String {
        let url = URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id")!
        let boundary = "seo-content-creator-\(UUID().uuidString)"
        let metadata = try JSONSerialization.data(withJSONObject: ["name": name, "parents": [parentID]])
        let body = Self.multipartBody(metadataJSON: metadata, fileData: data, mimeType: mimeType, boundary: boundary)
        let response = try await send(url: url, method: "POST", body: body,
                                      contentType: "multipart/related; boundary=\(boundary)")
        guard let obj = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
              let id = obj["id"] as? String else { throw DocsError.badResponse }
        return id
    }
```

- [ ] **Step 4: Build to verify compile**

Run: `cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `TEST BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/GoogleDocsClient.swift \
        SEOContentCreator/SEOContentCreatorTests/GoogleDocsClientTests.swift
git commit -m "feat: parent-aware Drive folders and multipart file upload in GoogleDocsClient"
```

---

### Task 6: ImageDriveUploader + DocsPublishing protocol extension

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Logic/ImageDriveUploader.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Logic/ArticlePublisher.swift` (protocol only, lines 4–13)
- Modify: `SEOContentCreator/SEOContentCreatorTests/ArticlePublisherTests.swift` (`FakeDocsClient`)
- Test: `SEOContentCreator/SEOContentCreatorTests/ImageDriveUploaderTests.swift`

- [ ] **Step 1: Extend the `DocsPublishing` protocol**

In `ArticlePublisher.swift`, add to the protocol:

```swift
protocol DocsPublishing {
    func createDocument(title: String) async throws -> String
    func batchUpdate(docID: String, requests: [[String: Any]]) async throws
    func clearBody(docID: String) async throws
    func documentBodyEndIndex(docID: String) async throws -> Int
    func findOrCreateFolder(name: String) async throws -> String
    func findOrCreateFolder(name: String, parentID: String) async throws -> String
    func uploadFile(name: String, data: Data, mimeType: String, parentID: String) async throws -> String
    func moveToFolder(fileID: String, folderID: String) async throws
}
```

(`extension GoogleDocsClient: DocsPublishing {}` keeps compiling — Task 5 added both methods.)

- [ ] **Step 2: Extend `FakeDocsClient` in `ArticlePublisherTests.swift`**

Add to the class:

```swift
    nonisolated(unsafe) var subfolders: [(name: String, parentID: String)] = []
    nonisolated(unsafe) var uploads: [(name: String, parentID: String, byteCount: Int)] = []
    nonisolated(unsafe) var failUpload = false
    nonisolated(unsafe) var nextFileIDNumber = 1

    func findOrCreateFolder(name: String, parentID: String) async throws -> String {
        subfolders.append((name, parentID))
        return "sub-\(name)"
    }
    func uploadFile(name: String, data: Data, mimeType: String, parentID: String) async throws -> String {
        if failUpload { throw GoogleDocsClient.DocsError.http(500) }
        uploads.append((name, parentID, data.count))
        defer { nextFileIDNumber += 1 }
        return "file-\(nextFileIDNumber)"
    }
```

- [ ] **Step 3: Write `ImageDriveUploaderTests.swift`**

```swift
import Testing
import Foundation
import SwiftData
@testable import SEOContentCreator

@MainActor
struct ImageDriveUploaderTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Topic.self, KnowledgeNode.self, ArticleVersion.self, GeneratedImage.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func image(role: ImageRole, topic: Topic, ctx: ModelContext) -> GeneratedImage {
        let img = GeneratedImage(role: role, data: Data([1, 2, 3]), promptUsed: "p")
        img.topic = topic
        ctx.insert(img)
        return img
    }

    @Test func topicFolderNameUsesExternalID() {
        #expect(ImageDriveUploader.topicFolderName(externalID: "12", topicTitle: "Тема") == "№12 Тема")
        #expect(ImageDriveUploader.topicFolderName(externalID: "  ", topicTitle: "Тема") == "Тема")
    }

    @Test func fileNamesByRoleAndIndex() {
        #expect(ImageDriveUploader.fileName(role: .cover, index: 1) == "обложка.png")
        #expect(ImageDriveUploader.fileName(role: .cover, index: 2) == "обложка-2.png")
        #expect(ImageDriveUploader.fileName(role: .illustration, index: 1) == "иллюстрация-1.png")
    }

    @Test func uploadsIntoNestedFolderAndMarksImages() async throws {
        let ctx = try makeContext()
        let topic = Topic(title: "Тема", articleType: .info, externalID: "7")
        ctx.insert(topic)
        let cover = image(role: .cover, topic: topic, ctx: ctx)
        let ill = image(role: .illustration, topic: topic, ctx: ctx)
        let fake = FakeDocsClient()

        let result = try await ImageDriveUploader.upload(
            images: [cover, ill], topic: topic, drive: fake, rootFolderName: "SEO-статьи клиники")

        // Folder chain: root (existing API) → «Иллюстрации» → topic subfolder.
        #expect(fake.subfolders.map(\.name) == ["Иллюстрации", "№7 Тема"])
        #expect(fake.subfolders[1].parentID == "sub-Иллюстрации")
        #expect(fake.uploads.map(\.name) == ["обложка.png", "иллюстрация-1.png"])
        #expect(cover.driveFileID == "file-1")
        #expect(ill.driveFileID == "file-2")
        #expect(result.uploadedCount == 2)
        #expect(result.skippedCount == 0)
        #expect(result.folderURL == GoogleDocsClient.folderURL(id: "sub-№7 Тема"))
    }

    @Test func skipsAlreadyUploadedImages() async throws {
        let ctx = try makeContext()
        let topic = Topic(title: "Тема", articleType: .info)
        ctx.insert(topic)
        let done = image(role: .illustration, topic: topic, ctx: ctx)
        done.driveFileID = "already-there"
        let fresh = image(role: .illustration, topic: topic, ctx: ctx)
        let fake = FakeDocsClient()

        let result = try await ImageDriveUploader.upload(
            images: [done, fresh], topic: topic, drive: fake, rootFolderName: "R")

        #expect(fake.uploads.count == 1)
        // Numbering stays stable: the skipped image keeps slot 1, the new one is 2.
        #expect(fake.uploads.first?.name == "иллюстрация-2.png")
        #expect(result.uploadedCount == 1)
        #expect(result.skippedCount == 1)
        #expect(done.driveFileID == "already-there")
    }
}
```

- [ ] **Step 4: Write `ImageDriveUploader.swift`**

```swift
import Foundation

/// Загружает выбранные картинки темы в подпапку статьи на Google Диске:
/// `<root>/Иллюстрации/№[ID] [Тема]/`. Уже загруженные (driveFileID != nil)
/// пропускаются; нумерация имён файлов при этом не сдвигается.
@MainActor
enum ImageDriveUploader {
    struct UploadResult: Equatable {
        var folderID: String
        var folderURL: String
        var uploadedCount: Int
        var skippedCount: Int
    }

    static let illustrationsFolderName = "Иллюстрации"

    static func topicFolderName(externalID: String, topicTitle: String) -> String {
        let id = externalID.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = topicTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? name : "№\(id) \(name)"
    }

    static func fileName(role: ImageRole, index: Int) -> String {
        switch role {
        case .cover:        return index == 1 ? "обложка.png" : "обложка-\(index).png"
        case .illustration: return "иллюстрация-\(index).png"
        }
    }

    static func upload(images: [GeneratedImage], topic: Topic, drive: DocsPublishing,
                       rootFolderName: String) async throws -> UploadResult {
        let root = try await drive.findOrCreateFolder(name: rootFolderName)
        let illustrations = try await drive.findOrCreateFolder(
            name: illustrationsFolderName, parentID: root)
        let topicFolder = try await drive.findOrCreateFolder(
            name: topicFolderName(externalID: topic.externalID, topicTitle: topic.title),
            parentID: illustrations)

        var uploaded = 0
        var skipped = 0
        var coverIndex = 0
        var illustrationIndex = 0
        for image in images.sorted(by: { $0.createdAt < $1.createdAt }) {
            let index: Int
            if image.role == .cover { coverIndex += 1; index = coverIndex }
            else { illustrationIndex += 1; index = illustrationIndex }
            if image.driveFileID != nil { skipped += 1; continue }
            let fileID = try await drive.uploadFile(
                name: fileName(role: image.role, index: index),
                data: image.data, mimeType: "image/png", parentID: topicFolder)
            image.driveFileID = fileID
            uploaded += 1
        }
        return UploadResult(
            folderID: topicFolder,
            folderURL: GoogleDocsClient.folderURL(id: topicFolder),
            uploadedCount: uploaded, skippedCount: skipped)
    }
}
```

- [ ] **Step 5: Build to verify compile**

Run: `cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `TEST BUILD SUCCEEDED`

- [ ] **Step 6: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/ImageDriveUploader.swift \
        SEOContentCreator/SEOContentCreator/Logic/ArticlePublisher.swift \
        SEOContentCreator/SEOContentCreatorTests/ArticlePublisherTests.swift \
        SEOContentCreator/SEOContentCreatorTests/ImageDriveUploaderTests.swift
git commit -m "feat: ImageDriveUploader with per-article Drive subfolders"
```

---

### Task 7: ArticlePublisher — upload images, substitute link, keep doc publish resilient

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Logic/ArticlePublisher.swift` (`publish` method)
- Test: `SEOContentCreator/SEOContentCreatorTests/ArticlePublisherTests.swift` (extend)

- [ ] **Step 1: Write the tests**

Add to `ArticlePublisherTests`:

```swift
    @Test func publishUploadsSelectedImagesAndSubstitutesLink() async throws {
        let context = try ctx()
        let topic = topicWithText(context,
            "# Заголовок\nТекст.\n\n## Техническая информация\n\nИллюстрации: [появится при публикации]")
        let img = GeneratedImage(role: .cover, data: Data([1]), promptUsed: "p")
        img.topic = topic; context.insert(img)
        let fake = FakeDocsClient()
        let publisher = ArticlePublisher(docs: fake, tokenProvider: { "t" }, folderName: "SEO-статьи клиники")

        await publisher.publish(topic: topic, mode: .newDocument, imagesToUpload: [img], in: context)

        #expect(publisher.lastErrorMessage == nil)
        #expect(fake.uploads.count == 1)
        #expect(img.driveFileID != nil)
        #expect(topic.illustrationsFolderURL?.contains("drive.google.com/drive/folders/") == true)
        // The published body must contain the real link, not the placeholder.
        let bodyJSON = String(describing: fake.batched.first?.1 ?? [])
        #expect(bodyJSON.contains("drive.google.com/drive/folders"))
        #expect(!bodyJSON.contains("[появится при публикации]"))
    }

    @Test func uploadFailureStillPublishesDocWithWarning() async throws {
        let context = try ctx()
        let topic = topicWithText(context, "# Заголовок\nТекст.")
        let img = GeneratedImage(role: .cover, data: Data([1]), promptUsed: "p")
        img.topic = topic; context.insert(img)
        let fake = FakeDocsClient()
        fake.failUpload = true
        let publisher = ArticlePublisher(docs: fake, tokenProvider: { "t" }, folderName: "SEO-статьи клиники")

        await publisher.publish(topic: topic, mode: .newDocument, imagesToUpload: [img], in: context)

        #expect(topic.publications.count == 1)                    // doc still published
        #expect(publisher.lastErrorMessage?.contains("картинки") == true)  // warning surfaced
        #expect(img.driveFileID == nil)
    }

    @Test func publishWithoutImagesLeavesPlaceholder() async throws {
        let context = try ctx()
        let topic = topicWithText(context,
            "Текст\n\n## Техническая информация\n\nИллюстрации: [появится при публикации]")
        let fake = FakeDocsClient()
        let publisher = ArticlePublisher(docs: fake, tokenProvider: { "t" }, folderName: "SEO-статьи клиники")

        await publisher.publish(topic: topic, mode: .newDocument, in: context)

        #expect(fake.uploads.isEmpty)
        #expect(topic.illustrationsFolderURL == nil)
    }
```

- [ ] **Step 2: Rewrite `publish` with upload + substitution**

Replace the whole `publish` method with:

```swift
    func publish(topic: Topic, mode: PublishMode, targetDocID: String? = nil,
                 imagesToUpload: [GeneratedImage] = [], in context: ModelContext) async {
        isPublishing = true
        lastErrorMessage = nil
        defer { isPublishing = false }

        guard let version = topic.currentVersion, !version.text.isEmpty else {
            lastErrorMessage = "Нет принятой версии текста для публикации."
            return
        }
        do {
            _ = try await tokenProvider()

            // Картинки грузим ДО документа, чтобы реальная ссылка на папку
            // попала в текст уже при первой публикации. Ошибка загрузки не
            // блокирует публикацию документа — только предупреждение в конце.
            var uploadWarning: String?
            if !imagesToUpload.isEmpty {
                do {
                    let result = try await ImageDriveUploader.upload(
                        images: imagesToUpload, topic: topic,
                        drive: docs, rootFolderName: folderName)
                    topic.illustrationsFolderURL = result.folderURL
                } catch {
                    let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    uploadWarning = "Документ опубликован, но картинки загрузить не удалось: \(reason)"
                }
            }

            var text = version.text
            if let link = topic.illustrationsFolderURL {
                text = TechInfoSectionBuilder.substituteIllustrationsLink(in: text, url: link)
            }

            let normalizedText = Self.normalizeHeading(text: text, h1: version.h1)
            let segments = CommercialBlockSplitter.split(normalizedText).map { segment in
                DocSegment(isCommercial: segment.isCommercial, blocks: MarkdownDocParser.parse(segment.text))
            }
            let requests = DocsRequestBuilder.build(segments: segments)

            let docTitle = PublishTitleBuilder.title(externalID: topic.externalID, topicTitle: topic.title)
            let docID: String
            switch mode {
            case .newDocument:
                docID = try await docs.createDocument(title: docTitle)
            case .overwrite:
                guard let existing = targetDocID
                        ?? topic.publications.sorted(by: { $0.publishedAt > $1.publishedAt }).first?.docID
                        ?? topic.externalDocURL.flatMap(Self.docID(fromURL:)) else {
                    let id = try await docs.createDocument(title: docTitle)
                    try await fill(docID: id, requests: requests)
                    try await place(docID: id)
                    record(topic: topic, docID: id, mode: .newDocument, in: context)
                    lastErrorMessage = uploadWarning
                    return
                }
                docID = existing
                let endIndex = try await docs.documentBodyEndIndex(docID: docID)
                let replacementRequests = DocsRequestBuilder.buildReplacingBody(segments: segments, existingBodyEndIndex: endIndex)
                try await fill(docID: docID, requests: replacementRequests)
                record(topic: topic, docID: docID, mode: mode, in: context)
                lastErrorMessage = uploadWarning
                return
            }

            try await fill(docID: docID, requests: requests)
            if mode == .newDocument { try await place(docID: docID) }
            record(topic: topic, docID: docID, mode: mode, in: context)
            lastErrorMessage = uploadWarning
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
```

- [ ] **Step 3: Build to verify compile**

Run: `cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `TEST BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/ArticlePublisher.swift \
        SEOContentCreator/SEOContentCreatorTests/ArticlePublisherTests.swift
git commit -m "feat: publish uploads selected images to Drive and substitutes folder link"
```

---

### Task 8: PublishSheet — image selection UI

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Views/PublishSheet.swift`

- [ ] **Step 1: Add state and helpers**

After `@State private var selectedDocID: String?`:

```swift
    @State private var selectedImageIDs: Set<UUID> = []
```

New computed property next to `sortedPublications`:

```swift
    private var selectableImages: [GeneratedImage] {
        topic.images.filter { !$0.isArchived }.sorted { $0.createdAt < $1.createdAt }
    }
```

- [ ] **Step 2: Add the picker section to `body`**

After the `GroupBox("Что публикуется") { ... }` block:

```swift
            if !selectableImages.isEmpty {
                GroupBox("Картинки на Google Диск") {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
                            ForEach(selectableImages, id: \.uuid) { image in
                                imageCell(image)
                            }
                        }
                    }
                    .frame(height: 120)
                }
            }
```

And the cell builder as a private method:

```swift
    @ViewBuilder
    private func imageCell(_ image: GeneratedImage) -> some View {
        let isSelected = selectedImageIDs.contains(image.uuid)
        Button {
            if isSelected { selectedImageIDs.remove(image.uuid) }
            else { selectedImageIDs.insert(image.uuid) }
        } label: {
            VStack(spacing: 2) {
                ZStack(alignment: .topTrailing) {
                    if let nsImage = NSImage(data: image.data) {
                        Image(nsImage: nsImage)
                            .resizable().scaledToFill()
                            .frame(width: 80, height: 60).clipped()
                            .cornerRadius(6)
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.quaternary).frame(width: 80, height: 60)
                    }
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        .padding(2)
                }
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2))
                Text(image.driveFileID != nil ? "на Диске" : image.role.title)
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
```

- [ ] **Step 3: Preselect the cover, pass selection to publish**

Add to `body` modifiers (after `.confirmationDialog { ... }`):

```swift
        .onAppear {
            if let coverID = topic.coverImageID,
               selectableImages.contains(where: { $0.uuid == coverID }) {
                selectedImageIDs = [coverID]
            }
        }
```

Update `doPublish`:

```swift
    private func doPublish() async {
        let images = selectableImages.filter { selectedImageIDs.contains($0.uuid) }
        await publisher.publish(
            topic: topic,
            mode: mode,
            targetDocID: mode == .overwrite ? overwriteTargetID : nil,
            imagesToUpload: images,
            in: context
        )
        if publisher.lastErrorMessage == nil { dismiss() }
    }
```

(The sheet already stays open when `lastErrorMessage` is non-nil — the upload warning from Task 7 is shown by the existing error `Text`.)

Also bump the sheet frame height to fit the new section: change `.frame(width: 520, height: 460)` to `.frame(width: 520, height: 600)`.

Per spec, the folder link must be visible in the app: inside the `GroupBox("Что публикуется")` `VStack`, after the `Text("Папка Google Drive: ...")` line, add:

```swift
                    if let link = topic.illustrationsFolderURL, let url = URL(string: link) {
                        Link("Папка иллюстраций на Диске", destination: url).font(.callout)
                    }
```

- [ ] **Step 4: Build to verify compile**

Run: `cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `TEST BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Views/PublishSheet.swift
git commit -m "feat: image selection for Drive upload in publish sheet"
```

---

### Task 9: Final verification checkpoint

- [ ] **Step 1: Full compile of app + tests**

Run: `cd SEOContentCreator && xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `TEST BUILD SUCCEEDED`

- [ ] **Step 2: User runs the test suite via Cmd+U in Xcode**

(CLI `xcodebuild test` hangs — known project constraint.) All tests green, including the new `TechInfoSectionBuilderTests`, `ImageDriveUploaderTests`, extended `ArticlePublisherTests`, `GoogleDocsClientTests`, `KnowledgeNodeUsageTests`.

- [ ] **Step 3: Manual smoke checklist (real Google account, spends one publish)**

1. Тема с текстом, «Финальная вычитка» без замечаний → в конце текста появился раздел «Техническая информация» со всеми полями (включая `URL: [вписать вручную]`); повторный прогон вычитки не добавляет второй раздел.
2. Бриф темы: мультивыбор дополнительных направлений + создание нового направления на месте; они появляются в строке «Направления».
3. Публикация: выбрать обложку и картинку → в Drive появились `SEO-статьи клиники/Иллюстрации/№ID Тема/обложка.png`, `иллюстрация-1.png`; в Google Doc строка «Иллюстрации:» содержит рабочую ссылку на подпапку.
4. Повторная публикация той же темы → дубликаты файлов не создаются («на Диске» бейджи в окне публикации).

Результат ручной проверки записать в `ai/changelog.md` при закрытии задачи (или завести future task на отложенную проверку, как принято в проекте).
