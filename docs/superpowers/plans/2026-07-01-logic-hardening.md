# Logic Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make SEOContentCreator safer around Google Docs overwrite, draft prerequisites, pending generated versions, destructive deletes, and publication target choice.

**Architecture:** Keep the existing SwiftUI + SwiftData structure. Add small focused helpers where they make behavior testable (`ArticleVersionStatus`, draft-run guard, version filtering, Google Docs replacement request builder). Avoid broad UI redesign and keep all data-model changes additive.

**Tech Stack:** SwiftUI, SwiftData, Swift Testing, Xcode `xcodebuild test`.

---

## Files

- Modify: `SEOContentCreator/SEOContentCreator/Models/ArticleVersion.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Models/Topic.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Logic/DocsRequestBuilder.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Logic/GoogleDocsClient.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Logic/ArticlePublisher.swift`
- Create: `SEOContentCreator/SEOContentCreator/Logic/StageRunGuard.swift`
- Create: `SEOContentCreator/SEOContentCreator/Logic/KnowledgeNodeUsage.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Views/TopicWorkspaceView.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Views/VersionLaneView.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Views/PublishSheet.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Views/ContentPlanView.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Views/KnowledgeBaseView.swift`
- Modify: `SEOContentCreator/SEOContentCreatorTests/ArticleVersionTests.swift`
- Modify: `SEOContentCreator/SEOContentCreatorTests/ArticlePublisherTests.swift`
- Modify: `SEOContentCreator/SEOContentCreatorTests/DocsRequestBuilderTests.swift`
- Create: `SEOContentCreator/SEOContentCreatorTests/StageRunGuardTests.swift`
- Create: `SEOContentCreator/SEOContentCreatorTests/KnowledgeNodeUsageTests.swift`

---

### Task 1: Add Explicit Article Version Status

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Models/ArticleVersion.swift`
- Modify: `SEOContentCreator/SEOContentCreatorTests/ArticleVersionTests.swift`

- [ ] **Step 1: Write failing status tests**

Add to `ArticleVersionTests`:

```swift
@Test func versionStatusDefaultsToAcceptedForExistingBehavior() {
    let v = ArticleVersion(stage: .draft, source: .generated, text: "Текст")
    #expect(v.status == .accepted)
    #expect(v.isVisibleInVersionLane == true)
}

@Test func pendingRejectedAndArchivedStatusesAffectVisibility() {
    let pending = ArticleVersion(stage: .draft, source: .generated, text: "Черновик")
    pending.status = .pending
    #expect(pending.statusRaw == "pending")
    #expect(pending.isVisibleInVersionLane == false)

    pending.status = .rejected
    #expect(pending.statusRaw == "rejected")
    #expect(pending.isVisibleInVersionLane == false)

    pending.status = .archived
    #expect(pending.statusRaw == "archived")
    #expect(pending.isArchived == true)
    #expect(pending.isVisibleInVersionLane == false)
}

@Test func legacyArchivedFlagStillHidesVersion() {
    let v = ArticleVersion(stage: .draft, source: .generated, text: "Текст")
    v.isArchived = true
    #expect(v.status == .archived)
    #expect(v.isVisibleInVersionLane == false)
}
```

- [ ] **Step 2: Run test to verify RED**

Run:

```bash
xcodebuild test -project SEOContentCreator/SEOContentCreator.xcodeproj -scheme SEOContentCreator -destination 'platform=macOS' -derivedDataPath /tmp/SEOContentCreatorLogicHardeningDD -only-testing:SEOContentCreatorTests/ArticleVersionTests
```

Expected: FAIL because `status`, `statusRaw`, and `isVisibleInVersionLane` do not exist.

- [ ] **Step 3: Implement minimal status model**

In `ArticleVersion.swift`, add:

```swift
enum ArticleVersionStatus: String, Codable, CaseIterable {
    case pending
    case accepted
    case rejected
    case archived
}
```

Add property to `ArticleVersion`:

```swift
var statusRaw: String?
```

Set in initializer:

```swift
self.statusRaw = ArticleVersionStatus.accepted.rawValue
```

Add computed properties:

```swift
var status: ArticleVersionStatus {
    get {
        if isArchived { return .archived }
        guard let statusRaw, let value = ArticleVersionStatus(rawValue: statusRaw) else {
            return .accepted
        }
        return value
    }
    set {
        statusRaw = newValue.rawValue
        isArchived = newValue == .archived
    }
}

var isVisibleInVersionLane: Bool {
    status == .accepted
}
```

- [ ] **Step 4: Run test to verify GREEN**

Run the same `ArticleVersionTests` command.

Expected: TEST SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Models/ArticleVersion.swift SEOContentCreator/SEOContentCreatorTests/ArticleVersionTests.swift
git commit -m "Add article version status"
```

---

### Task 2: Persist Pending/Accepted/Rejected Generation Flow

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Logic/StageExecutor.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Views/TopicWorkspaceView.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Views/VersionLaneView.swift`
- Modify: `SEOContentCreator/SEOContentCreatorTests/StageExecutorTests.swift`

- [ ] **Step 1: Write failing StageExecutor pending test**

Update `successCreatesPendingVersionNotAutoCurrent` in `StageExecutorTests`:

```swift
#expect(created?.status == .pending)
#expect(created?.isVisibleInVersionLane == false)
```

- [ ] **Step 2: Run test to verify RED**

Run:

```bash
xcodebuild test -project SEOContentCreator/SEOContentCreator.xcodeproj -scheme SEOContentCreator -destination 'platform=macOS' -derivedDataPath /tmp/SEOContentCreatorLogicHardeningDD -only-testing:SEOContentCreatorTests/StageExecutorTests/successCreatesPendingVersionNotAutoCurrent
```

Expected: FAIL because generated versions still default to accepted.

- [ ] **Step 3: Mark generated versions pending**

In `StageExecutor.execute`, after creating `version` for normal generated stages:

```swift
version.status = .pending
```

- [ ] **Step 4: Update UI accept/reject transitions**

In `TopicWorkspaceView.acceptAll()`:

```swift
pending.status = .accepted
topic.currentVersionID = pending.uuid
topic.updatedAt = .now
pendingVersionID = nil
comparisonText = nil
```

In `TopicWorkspaceView.reject()`:

```swift
pending.status = .rejected
pendingVersionID = nil
comparisonText = nil
```

In `TopicWorkspaceView.applyPartial(...)`, keep the generated version hidden:

```swift
generated.status = .rejected
let version = ArticleVersion(stage: PipelineStage(rawValue: generated.stageRaw) ?? .draft,
                             source: .acceptedPartial, text: hybrid)
version.status = .accepted
```

In `TopicWorkspaceView.finishReview()`, set created check-applied versions accepted:

```swift
version.status = .accepted
```

- [ ] **Step 5: Use status for lane filtering**

In `VersionLaneView`:

```swift
private var versions: [ArticleVersion] {
    topic.versions.filter(\.isVisibleInVersionLane).sorted { $0.createdAt > $1.createdAt }
}
```

- [ ] **Step 6: Run focused tests**

Run:

```bash
xcodebuild test -project SEOContentCreator/SEOContentCreator.xcodeproj -scheme SEOContentCreator -destination 'platform=macOS' -derivedDataPath /tmp/SEOContentCreatorLogicHardeningDD -only-testing:SEOContentCreatorTests/StageExecutorTests -only-testing:SEOContentCreatorTests/ArticleVersionTests
```

Expected: TEST SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/StageExecutor.swift SEOContentCreator/SEOContentCreator/Views/TopicWorkspaceView.swift SEOContentCreator/SEOContentCreator/Views/VersionLaneView.swift SEOContentCreator/SEOContentCreatorTests/StageExecutorTests.swift
git commit -m "Track pending generated versions"
```

---

### Task 3: Block Draft Generation Without Required Brief

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Logic/StageRunGuard.swift`
- Create: `SEOContentCreator/SEOContentCreatorTests/StageRunGuardTests.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Views/TopicWorkspaceView.swift`

- [ ] **Step 1: Write failing guard tests**

Create `StageRunGuardTests.swift`:

```swift
import Testing
@testable import SEOContentCreator

struct StageRunGuardTests {
    @Test func draftWithoutDirectionReturnsMessage() {
        let topic = Topic(title: "Тема", articleType: .disease)
        #expect(StageRunGuard.messagePreventingRun(stage: .draft, topic: topic) == "Перед черновиком выберите направление в брифе.")
    }

    @Test func draftWithDirectionCanRun() {
        let direction = KnowledgeNode(title: "Онкология", type: .direction)
        let topic = Topic(title: "Тема", articleType: .disease, direction: direction)
        #expect(StageRunGuard.messagePreventingRun(stage: .draft, topic: topic) == nil)
    }

    @Test func nonDraftStagesRemainFlexible() {
        let topic = Topic(title: "Тема", articleType: .disease)
        #expect(StageRunGuard.messagePreventingRun(stage: .seoCheck, topic: topic) == nil)
    }
}
```

- [ ] **Step 2: Run test to verify RED**

Run:

```bash
xcodebuild test -project SEOContentCreator/SEOContentCreator.xcodeproj -scheme SEOContentCreator -destination 'platform=macOS' -derivedDataPath /tmp/SEOContentCreatorLogicHardeningDD -only-testing:SEOContentCreatorTests/StageRunGuardTests
```

Expected: FAIL because `StageRunGuard` does not exist.

- [ ] **Step 3: Implement guard**

Create `StageRunGuard.swift`:

```swift
enum StageRunGuard {
    static func messagePreventingRun(stage: PipelineStage, topic: Topic) -> String? {
        guard stage == .draft else { return nil }
        if BriefValidation.canStartDraft(title: topic.title, hasDirection: topic.direction != nil) {
            return nil
        }
        if topic.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Перед черновиком заполните название темы в брифе."
        }
        return "Перед черновиком выберите направление в брифе."
    }
}
```

- [ ] **Step 4: Use guard in workspace**

In `TopicWorkspaceView.runStage`, before fetching template:

```swift
if let message = StageRunGuard.messagePreventingRun(stage: stage, topic: topic) {
    executor.lastErrorMessage = message
    return
}
```

- [ ] **Step 5: Run focused tests**

Run:

```bash
xcodebuild test -project SEOContentCreator/SEOContentCreator.xcodeproj -scheme SEOContentCreator -destination 'platform=macOS' -derivedDataPath /tmp/SEOContentCreatorLogicHardeningDD -only-testing:SEOContentCreatorTests/StageRunGuardTests -only-testing:SEOContentCreatorTests/BriefValidationTests
```

Expected: TEST SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/StageRunGuard.swift SEOContentCreator/SEOContentCreator/Views/TopicWorkspaceView.swift SEOContentCreator/SEOContentCreatorTests/StageRunGuardTests.swift
git commit -m "Block draft without required brief"
```

---

### Task 4: Make Google Docs Overwrite One Replacement Operation

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Logic/DocsRequestBuilder.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Logic/GoogleDocsClient.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Logic/ArticlePublisher.swift`
- Modify: `SEOContentCreator/SEOContentCreatorTests/DocsRequestBuilderTests.swift`
- Modify: `SEOContentCreator/SEOContentCreatorTests/ArticlePublisherTests.swift`

- [ ] **Step 1: Write failing replacement-request test**

Add to `DocsRequestBuilderTests`:

```swift
@Test func replacementRequestsDeleteExistingBodyBeforeInsert() {
    let blocks = [DocBlock(style: .normal, listType: nil, text: "Новый текст", boldRanges: [])]
    let reqs = DocsRequestBuilder.buildReplacingBody(blocks: blocks, existingBodyEndIndex: 20)
    let delete = reqs.first?["deleteContentRange"] as? [String: Any]
    let range = delete?["range"] as? [String: Any]
    #expect(range?["startIndex"] as? Int == 1)
    #expect(range?["endIndex"] as? Int == 19)

    let insert = reqs.dropFirst().first?["insertText"] as? [String: Any]
    #expect((insert?["text"] as? String) == "Новый текст\n")
}
```

- [ ] **Step 2: Write failing publisher failure test**

Extend `FakeDocsClient` in `ArticlePublisherTests` with:

```swift
nonisolated(unsafe) var bodyEndIndex = 20
nonisolated(unsafe) var failBatchUpdate = false
func documentBodyEndIndex(docID: String) async throws -> Int { bodyEndIndex }
```

Change `batchUpdate`:

```swift
func batchUpdate(docID: String, requests: [[String: Any]]) async throws {
    if failBatchUpdate { throw GoogleDocsClient.DocsError.http(500) }
    batched.append((docID, requests))
}
```

Add test:

```swift
@Test func overwriteDoesNotRecordPublicationWhenReplacementFails() async throws {
    let context = try ctx()
    let topic = topicWithText(context, "Текст")
    let prev = ExternalDocument(docID: "doc-old", docURL: GoogleDocsClient.documentURL(id: "doc-old"), mode: .newDocument)
    prev.topic = topic
    context.insert(prev)
    let fake = FakeDocsClient()
    fake.failBatchUpdate = true
    let publisher = ArticlePublisher(docs: fake, tokenProvider: { "t" }, folderName: "SEO-статьи клиники")

    await publisher.publish(topic: topic, mode: .overwrite, targetDocID: "doc-old", in: context)

    #expect(publisher.lastErrorMessage != nil)
    #expect(topic.publications.count == 1)
    #expect(fake.cleared.isEmpty)
}
```

- [ ] **Step 3: Run tests to verify RED**

Run:

```bash
xcodebuild test -project SEOContentCreator/SEOContentCreator.xcodeproj -scheme SEOContentCreator -destination 'platform=macOS' -derivedDataPath /tmp/SEOContentCreatorLogicHardeningDD -only-testing:SEOContentCreatorTests/DocsRequestBuilderTests/replacementRequestsDeleteExistingBodyBeforeInsert -only-testing:SEOContentCreatorTests/ArticlePublisherTests/overwriteDoesNotRecordPublicationWhenReplacementFails
```

Expected: FAIL because `buildReplacingBody`, `documentBodyEndIndex`, and `targetDocID` publish overload do not exist.

- [ ] **Step 4: Add replacement builder**

In `DocsRequestBuilder`:

```swift
static func buildReplacingBody(blocks: [DocBlock], existingBodyEndIndex: Int) -> [[String: Any]] {
    var requests: [[String: Any]] = []
    if existingBodyEndIndex > 2 {
        requests.append([
            "deleteContentRange": [
                "range": ["startIndex": 1, "endIndex": existingBodyEndIndex - 1]
            ]
        ])
    }
    requests.append(contentsOf: build(blocks: blocks))
    return requests
}
```

- [ ] **Step 5: Add document end-index API**

In `DocsPublishing`, replace `clearBody` with:

```swift
func documentBodyEndIndex(docID: String) async throws -> Int
```

In `GoogleDocsClient`:

```swift
func documentBodyEndIndex(docID: String) async throws -> Int {
    let getURL = URL(string: "https://docs.googleapis.com/v1/documents/\(docID)")!
    let data = try await send(url: getURL, method: "GET", json: nil)
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let body = obj["body"] as? [String: Any],
          let content = body["content"] as? [[String: Any]] else { throw DocsError.badResponse }
    return content.compactMap { $0["endIndex"] as? Int }.max() ?? 1
}
```

Keep `clearBody` only if tests or other code still need it; do not use it from `ArticlePublisher`.

- [ ] **Step 6: Update publisher overwrite**

Change publish signature:

```swift
func publish(topic: Topic, mode: PublishMode, targetDocID: String? = nil, in context: ModelContext) async
```

Overwrite doc selection:

```swift
let existing = targetDocID
    ?? topic.publications.sorted(by: { $0.publishedAt > $1.publishedAt }).first?.docID
    ?? topic.externalDocURL.flatMap(Self.docID(fromURL:))
```

Overwrite replacement:

```swift
let endIndex = try await docs.documentBodyEndIndex(docID: docID)
let replacementRequests = DocsRequestBuilder.buildReplacingBody(blocks: blocks, existingBodyEndIndex: endIndex)
try await fill(docID: docID, requests: replacementRequests)
record(topic: topic, docID: docID, mode: mode, in: context)
```

New document path keeps using `DocsRequestBuilder.build(blocks:)`.

- [ ] **Step 7: Run focused tests**

Run:

```bash
xcodebuild test -project SEOContentCreator/SEOContentCreator.xcodeproj -scheme SEOContentCreator -destination 'platform=macOS' -derivedDataPath /tmp/SEOContentCreatorLogicHardeningDD -only-testing:SEOContentCreatorTests/DocsRequestBuilderTests -only-testing:SEOContentCreatorTests/ArticlePublisherTests
```

Expected: TEST SUCCEEDED.

- [ ] **Step 8: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/DocsRequestBuilder.swift SEOContentCreator/SEOContentCreator/Logic/GoogleDocsClient.swift SEOContentCreator/SEOContentCreator/Logic/ArticlePublisher.swift SEOContentCreator/SEOContentCreatorTests/DocsRequestBuilderTests.swift SEOContentCreator/SEOContentCreatorTests/ArticlePublisherTests.swift
git commit -m "Make Google Docs overwrite safer"
```

---

### Task 5: Let User Choose Publication Target

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Views/PublishSheet.swift`

- [ ] **Step 1: Add target selection state**

In `PublishSheet`:

```swift
@State private var selectedDocID: String?
```

Add helper:

```swift
private var sortedPublications: [ExternalDocument] {
    topic.publications.sorted(by: { $0.publishedAt > $1.publishedAt })
}

private var overwriteTargetID: String? {
    selectedDocID ?? sortedPublications.first?.docID
}
```

- [ ] **Step 2: Add picker in overwrite mode**

Below mode picker:

```swift
if mode == .overwrite && !sortedPublications.isEmpty {
    Picker("Документ для перезаписи", selection: Binding(
        get: { overwriteTargetID },
        set: { selectedDocID = $0 }
    )) {
        ForEach(sortedPublications, id: \.docID) { doc in
            Text(doc.docURL).tag(Optional(doc.docID))
        }
    }
}
```

- [ ] **Step 3: Pass selected target**

In `doPublish()`:

```swift
await publisher.publish(topic: topic, mode: mode, targetDocID: mode == .overwrite ? overwriteTargetID : nil, in: context)
```

- [ ] **Step 4: Manual build check**

Run:

```bash
xcodebuild build -project SEOContentCreator/SEOContentCreator.xcodeproj -scheme SEOContentCreator -destination 'platform=macOS' -derivedDataPath /tmp/SEOContentCreatorLogicHardeningDD
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Views/PublishSheet.swift
git commit -m "Allow choosing publication overwrite target"
```

---

### Task 6: Add Deletion Confirmations and Knowledge Usage Warning

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Logic/KnowledgeNodeUsage.swift`
- Create: `SEOContentCreator/SEOContentCreatorTests/KnowledgeNodeUsageTests.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Views/ContentPlanView.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Views/KnowledgeBaseView.swift`

- [ ] **Step 1: Write failing usage tests**

Create `KnowledgeNodeUsageTests.swift`:

```swift
import Testing
@testable import SEOContentCreator

struct KnowledgeNodeUsageTests {
    @Test func countsDirectionDoctorAndAttachedNodeUsage() {
        let direction = KnowledgeNode(title: "Онкология", type: .direction)
        let doctor = KnowledgeNode(title: "Доктор", type: .doctor)
        let fact = KnowledgeNode(title: "Факт", type: .fact)
        let a = Topic(title: "A", articleType: .disease, direction: direction)
        let b = Topic(title: "B", articleType: .disease, doctor: doctor)
        let c = Topic(title: "C", articleType: .disease)
        c.attachedNodes.append(fact)

        #expect(KnowledgeNodeUsage.count(for: direction, in: [a, b, c]) == 1)
        #expect(KnowledgeNodeUsage.count(for: doctor, in: [a, b, c]) == 1)
        #expect(KnowledgeNodeUsage.count(for: fact, in: [a, b, c]) == 1)
    }
}
```

- [ ] **Step 2: Run test to verify RED**

Run:

```bash
xcodebuild test -project SEOContentCreator/SEOContentCreator.xcodeproj -scheme SEOContentCreator -destination 'platform=macOS' -derivedDataPath /tmp/SEOContentCreatorLogicHardeningDD -only-testing:SEOContentCreatorTests/KnowledgeNodeUsageTests
```

Expected: FAIL because `KnowledgeNodeUsage` does not exist.

- [ ] **Step 3: Implement usage helper**

Create `KnowledgeNodeUsage.swift`:

```swift
enum KnowledgeNodeUsage {
    static func count(for node: KnowledgeNode, in topics: [Topic]) -> Int {
        topics.filter { topic in
            topic.direction === node
                || topic.doctor === node
                || topic.attachedNodes.contains(where: { $0 === node })
        }.count
    }
}
```

- [ ] **Step 4: Add topic delete confirmation**

In `ContentPlanView`, add state:

```swift
@State private var topicPendingDeletion: Topic?
```

Change context menu delete:

```swift
Button("Удалить", role: .destructive) { topicPendingDeletion = t }
```

Add confirmation:

```swift
.confirmationDialog("Удалить тему?", isPresented: Binding(
    get: { topicPendingDeletion != nil },
    set: { if !$0 { topicPendingDeletion = nil } }
)) {
    Button("Удалить", role: .destructive) {
        if let topicPendingDeletion { context.delete(topicPendingDeletion) }
        topicPendingDeletion = nil
    }
    Button("Отмена", role: .cancel) { topicPendingDeletion = nil }
} message: {
    Text("Тема и связанные версии, логи и изображения будут удалены.")
}
```

- [ ] **Step 5: Add knowledge node delete confirmation**

In `KnowledgeBaseView`, pass `allNodes` and topics into detail. Add:

```swift
@Query(sort: \Topic.updatedAt, order: .reverse) private var topics: [Topic]
```

Use:

```swift
NodeDetailView(node: node, topics: topics)
```

In `NodeDetailView`, add:

```swift
let topics: [Topic]
@State private var confirmDelete = false
private var usageCount: Int { KnowledgeNodeUsage.count(for: node, in: topics) }
```

Change delete button:

```swift
Button("Удалить", role: .destructive) { confirmDelete = true }
```

Add confirmation dialog:

```swift
.confirmationDialog("Удалить узел базы знаний?", isPresented: $confirmDelete) {
    Button("Удалить", role: .destructive) { context.delete(node) }
    Button("Отмена", role: .cancel) {}
} message: {
    Text(usageCount > 0
         ? "Этот узел используется в \(usageCount) темах. После удаления брифы и промты могут потерять часть контекста."
         : "Узел будет удалён из базы знаний.")
}
```

- [ ] **Step 6: Run focused tests and build**

Run:

```bash
xcodebuild test -project SEOContentCreator/SEOContentCreator.xcodeproj -scheme SEOContentCreator -destination 'platform=macOS' -derivedDataPath /tmp/SEOContentCreatorLogicHardeningDD -only-testing:SEOContentCreatorTests/KnowledgeNodeUsageTests
xcodebuild build -project SEOContentCreator/SEOContentCreator.xcodeproj -scheme SEOContentCreator -destination 'platform=macOS' -derivedDataPath /tmp/SEOContentCreatorLogicHardeningDD
```

Expected: test succeeds and build succeeds.

- [ ] **Step 7: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/KnowledgeNodeUsage.swift SEOContentCreator/SEOContentCreator/Views/ContentPlanView.swift SEOContentCreator/SEOContentCreator/Views/KnowledgeBaseView.swift SEOContentCreator/SEOContentCreatorTests/KnowledgeNodeUsageTests.swift
git commit -m "Confirm destructive deletes"
```

---

### Task 7: Final Verification

**Files:**
- All files touched above.

- [ ] **Step 1: Run focused logic tests**

```bash
xcodebuild test -project SEOContentCreator/SEOContentCreator.xcodeproj -scheme SEOContentCreator -destination 'platform=macOS' -derivedDataPath /tmp/SEOContentCreatorLogicHardeningDD -only-testing:SEOContentCreatorTests/ArticleVersionTests -only-testing:SEOContentCreatorTests/StageExecutorTests -only-testing:SEOContentCreatorTests/StageRunGuardTests -only-testing:SEOContentCreatorTests/DocsRequestBuilderTests -only-testing:SEOContentCreatorTests/ArticlePublisherTests -only-testing:SEOContentCreatorTests/KnowledgeNodeUsageTests
```

Expected: TEST SUCCEEDED.

- [ ] **Step 2: Run app build**

```bash
xcodebuild build -project SEOContentCreator/SEOContentCreator.xcodeproj -scheme SEOContentCreator -destination 'platform=macOS' -derivedDataPath /tmp/SEOContentCreatorLogicHardeningDD
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Inspect diff**

```bash
git diff --name-only
git diff --check
```

Expected: only intended source/test/docs/memory files changed; no whitespace errors.

- [ ] **Step 4: Update current task handoff**

Set `ai/current-task.md` stage to `review` and record verification results in `Agent handoff`.

- [ ] **Step 5: Commit final task memory if appropriate**

```bash
git add ai/current-task.md
git commit -m "Update logic hardening task state"
```

Only do this if task-memory changes are intended to be saved separately.

---

## Self-Review

- Spec coverage: all five agreed findings are covered by tasks 1-6.
- Completeness scan: no unfinished markers remain.
- Type consistency: `ArticleVersionStatus`, `StageRunGuard`, `KnowledgeNodeUsage`, `documentBodyEndIndex`, and `targetDocID` are named consistently throughout the plan.
