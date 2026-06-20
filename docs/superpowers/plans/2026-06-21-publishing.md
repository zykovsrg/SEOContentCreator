# «Публикация в Google Docs» — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Опубликовать принятую версию статьи в Google Docs одним действием, односторонне, через собственный OAuth и Docs/Drive REST API.

**Architecture:** Чистые тестируемые юниты: парсер markdown → блоки (`MarkdownDocParser`), построитель запросов Docs (`DocsRequestBuilder`), REST-клиент (`GoogleDocsClient`), OAuth-сервис (`GoogleAuthService`) и оркестратор (`ArticlePublisher`). Новая SwiftData-модель `ExternalDocument` хранит историю публикаций. UI: раздел Google в Настройках + кнопка «Опубликовать» с листом в рабочем пространстве темы.

**Tech Stack:** Swift, SwiftUI, SwiftData, URLSession, Network (NWListener для loopback), CryptoKit (PKCE/SHA256), Security (Keychain), Swift Testing.

**Спека:** `docs/superpowers/specs/2026-06-21-publishing-design.md`

**Ключевые принципы проекта:**
- Тесты — Swift Testing (`import Testing`, `@Test`, `#expect`). CLI-компиляция: `xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS'`. Запуск тестов — Cmd+U в Xcode (CLI `xcodebuild test` зависает — см. память проекта).
- Сетевые тесты — через `MockURLProtocol` (есть в `OpenAIClientTests.swift`; новый общий мок в задаче 4).
- Внедрение зависимостей как в `StageExecutor`/`OpenAIClient` (инициализатор принимает `URLSession`, провайдеры).
- Все строки UI и ошибок — на русском.
- Коммитим часто, после каждой задачи.

**Деталь по UI (осознанное решение):** публикация реализуется как кнопка «Опубликовать» в тулбаре `TopicWorkspaceView` + sheet, **а не** как новый case в `PipelineStage` — `PipelineStage` моделирует ИИ-этапы (agent/role/kind), действие-публикация туда не вписывается. Это совпадает с тем, как сделана кнопка «Изображения».

---

## File Structure

**Создаём:**
- `SEOContentCreator/Models/ExternalDocument.swift` — модель публикации.
- `SEOContentCreator/Logic/GoogleCredentialStore.swift` — Keychain для ключей и токенов Google.
- `SEOContentCreator/Logic/GoogleTokens.swift` — Codable-структура токенов.
- `SEOContentCreator/Logic/MarkdownDocParser.swift` — markdown → `[DocBlock]`.
- `SEOContentCreator/Logic/DocsRequestBuilder.swift` — `[DocBlock]` → `[[String: Any]]` (запросы batchUpdate).
- `SEOContentCreator/Logic/GoogleDocsClient.swift` — REST Docs/Drive.
- `SEOContentCreator/Logic/GoogleAuthService.swift` — OAuth desktop + PKCE + токены.
- `SEOContentCreator/Logic/ArticlePublisher.swift` — оркестратор.
- `SEOContentCreator/Views/PublishSheet.swift` — лист публикации + история.
- Тесты: `ExternalDocumentTests`, `GoogleCredentialStoreTests`, `MarkdownDocParserTests`, `DocsRequestBuilderTests`, `GoogleDocsClientTests`, `GoogleAuthServiceTests`, `ArticlePublisherTests`.

**Меняем:**
- `SEOContentCreator/SEOContentCreatorApp.swift` — регистрация `ExternalDocument` в схеме.
- `SEOContentCreator/Models/Topic.swift` — связь `publications: [ExternalDocument]`.
- `SEOContentCreator/Views/SettingsView.swift` — раздел Google.
- `SEOContentCreator/Views/TopicWorkspaceView.swift` — кнопка «Опубликовать» + sheet.

---

## Task 1: Модель `ExternalDocument` + связь у `Topic` + схема

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Models/ExternalDocument.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Models/Topic.swift`
- Modify: `SEOContentCreator/SEOContentCreator/SEOContentCreatorApp.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/ExternalDocumentTests.swift`

- [ ] **Step 1: Написать падающий тест**

```swift
import Testing
import Foundation
import SwiftData
@testable import SEOContentCreator

@MainActor
struct ExternalDocumentTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(
            for: Topic.self, ExternalDocument.self, ArticleVersion.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    @Test func storesPublicationAndLinksToTopic() throws {
        let ctx = try container().mainContext
        let topic = Topic(title: "Тема", articleType: .article)
        ctx.insert(topic)
        let doc = ExternalDocument(docID: "doc123", docURL: "https://docs.google.com/document/d/doc123/edit", mode: .newDocument)
        doc.topic = topic
        ctx.insert(doc)
        try ctx.save()

        #expect(topic.publications.count == 1)
        #expect(topic.publications.first?.docID == "doc123")
        #expect(topic.publications.first?.mode == .newDocument)
    }
}
```

- [ ] **Step 2: Запустить — убедиться, что не компилируется/падает**

Cmd+U (или CLI `build-for-testing`). Ожидаемо: ошибка «cannot find 'ExternalDocument'».

- [ ] **Step 3: Создать модель**

`ExternalDocument.swift`:

```swift
import Foundation
import SwiftData

enum PublishMode: String, Codable, Equatable {
    case newDocument
    case overwrite
}

@Model
final class ExternalDocument {
    var uuid: UUID
    var docID: String
    var docURL: String
    var modeRaw: String
    var publishedAt: Date

    @Relationship var topic: Topic?

    init(docID: String, docURL: String, mode: PublishMode, publishedAt: Date = .now) {
        self.uuid = UUID()
        self.docID = docID
        self.docURL = docURL
        self.modeRaw = mode.rawValue
        self.publishedAt = publishedAt
    }

    var mode: PublishMode {
        get { PublishMode(rawValue: modeRaw) ?? .newDocument }
        set { modeRaw = newValue.rawValue }
    }
}
```

- [ ] **Step 4: Добавить связь у `Topic`**

В `Topic.swift` после блока `@Relationship(... inverse: \GeneratedImage.topic) var images:` добавить:

```swift
    @Relationship(deleteRule: .cascade, inverse: \ExternalDocument.topic)
    var publications: [ExternalDocument] = []
```

- [ ] **Step 5: Зарегистрировать в схеме**

В `SEOContentCreatorApp.swift` в список `.modelContainer(for: [...])` добавить `ExternalDocument.self`:

```swift
        .modelContainer(for: [
            Topic.self, KnowledgeNode.self,
            ArticleVersion.self, GenerationJob.self, StageTemplate.self,
            ContextBlock.self, AIRole.self,
            GeneratedImage.self, ImageStylePreset.self, ImagePromptTemplate.self,
            ExternalDocument.self
        ])
```

- [ ] **Step 6: Запустить тест — зелёный**

Cmd+U → `ExternalDocumentTests` проходит.

- [ ] **Step 7: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Models/ExternalDocument.swift \
        SEOContentCreator/SEOContentCreator/Models/Topic.swift \
        SEOContentCreator/SEOContentCreator/SEOContentCreatorApp.swift \
        SEOContentCreator/SEOContentCreatorTests/ExternalDocumentTests.swift
git commit -m "feat(publish): ExternalDocument model + Topic.publications"
```

---

## Task 2: `GoogleTokens` + `GoogleCredentialStore` (Keychain)

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Logic/GoogleTokens.swift`
- Create: `SEOContentCreator/SEOContentCreator/Logic/GoogleCredentialStore.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/GoogleCredentialStoreTests.swift`

- [ ] **Step 1: Написать падающий тест**

```swift
import Testing
import Foundation
@testable import SEOContentCreator

struct GoogleCredentialStoreTests {
    @Test func savesAndLoadsClientCredentials() throws {
        try? GoogleCredentialStore.deleteAll()
        try GoogleCredentialStore.saveClient(id: "cid.apps.googleusercontent.com", secret: "secret-x")
        #expect(GoogleCredentialStore.loadClientID() == "cid.apps.googleusercontent.com")
        #expect(GoogleCredentialStore.loadClientSecret() == "secret-x")
        #expect(GoogleCredentialStore.hasClient)
    }

    @Test func savesAndLoadsTokens() throws {
        try? GoogleCredentialStore.deleteAll()
        let tokens = GoogleTokens(accessToken: "at", refreshToken: "rt", expiry: Date(timeIntervalSince1970: 1000))
        try GoogleCredentialStore.saveTokens(tokens)
        let loaded = try #require(GoogleCredentialStore.loadTokens())
        #expect(loaded.accessToken == "at")
        #expect(loaded.refreshToken == "rt")
        #expect(loaded.expiry == Date(timeIntervalSince1970: 1000))
    }

    @Test func deleteAllClears() throws {
        try GoogleCredentialStore.saveClient(id: "c", secret: "s")
        try GoogleCredentialStore.deleteAll()
        #expect(!GoogleCredentialStore.hasClient)
        #expect(GoogleCredentialStore.loadTokens() == nil)
    }
}
```

- [ ] **Step 2: Запустить — падает («cannot find 'GoogleCredentialStore'»)**

- [ ] **Step 3: Создать `GoogleTokens.swift`**

```swift
import Foundation

struct GoogleTokens: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiry: Date

    var isExpired: Bool { Date() >= expiry.addingTimeInterval(-60) }
}
```

- [ ] **Step 4: Создать `GoogleCredentialStore.swift`**

Образец — `KeychainService` (тот же `Security` API, отдельный `serviceName`).

```swift
import Foundation
import Security

enum GoogleCredentialStore {
    static let serviceName = "SEOContentCreator.Google"

    private static func save(_ value: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainService.KeychainError.unexpectedStatus(status) }
    }

    private static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func saveClient(id: String, secret: String) throws {
        try save(id, account: "clientID")
        try save(secret, account: "clientSecret")
    }
    static func loadClientID() -> String? { load(account: "clientID") }
    static func loadClientSecret() -> String? { load(account: "clientSecret") }
    static var hasClient: Bool { loadClientID() != nil && loadClientSecret() != nil }

    static func saveTokens(_ tokens: GoogleTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        try save(String(decoding: data, as: UTF8.self), account: "tokens")
    }
    static func loadTokens() -> GoogleTokens? {
        guard let raw = load(account: "tokens"), let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(GoogleTokens.self, from: data)
    }
    static var isSignedIn: Bool { loadTokens() != nil }

    static func deleteAll() throws {
        delete(account: "clientID")
        delete(account: "clientSecret")
        delete(account: "tokens")
    }
}
```

- [ ] **Step 5: Запустить тесты — зелёные**

- [ ] **Step 6: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/GoogleTokens.swift \
        SEOContentCreator/SEOContentCreator/Logic/GoogleCredentialStore.swift \
        SEOContentCreator/SEOContentCreatorTests/GoogleCredentialStoreTests.swift
git commit -m "feat(publish): Google credential/token Keychain store"
```

---

## Task 3: `MarkdownDocParser` (markdown → блоки)

Чистый разбор. `DocBlock` — один абзац: стиль, плоский текст, диапазоны жирного, тип списка.

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Logic/MarkdownDocParser.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/MarkdownDocParserTests.swift`

- [ ] **Step 1: Написать падающие тесты**

```swift
import Testing
@testable import SEOContentCreator

struct MarkdownDocParserTests {
    @Test func parsesHeadings() {
        let blocks = MarkdownDocParser.parse("# Заголовок\n## Подзаголовок\n### Мелкий")
        #expect(blocks.count == 3)
        #expect(blocks[0].style == .heading1 && blocks[0].text == "Заголовок")
        #expect(blocks[1].style == .heading2 && blocks[1].text == "Подзаголовок")
        #expect(blocks[2].style == .heading3 && blocks[2].text == "Мелкий")
    }

    @Test func parsesParagraph() {
        let blocks = MarkdownDocParser.parse("Просто абзац текста.")
        #expect(blocks.count == 1)
        #expect(blocks[0].style == .normal)
        #expect(blocks[0].listType == nil)
        #expect(blocks[0].text == "Просто абзац текста.")
    }

    @Test func parsesBulletAndNumberedLists() {
        let blocks = MarkdownDocParser.parse("- один\n- два\n1. первый\n2. второй")
        #expect(blocks[0].listType == .bullet && blocks[0].text == "один")
        #expect(blocks[1].listType == .bullet && blocks[1].text == "два")
        #expect(blocks[2].listType == .numbered && blocks[2].text == "первый")
        #expect(blocks[3].listType == .numbered && blocks[3].text == "второй")
    }

    @Test func extractsBoldRangesAndStripsMarkers() {
        let blocks = MarkdownDocParser.parse("Это **жирное** слово")
        #expect(blocks[0].text == "Это жирное слово")
        #expect(blocks[0].boldRanges == [4..<10]) // "жирное"
    }

    @Test func skipsBlankLines() {
        let blocks = MarkdownDocParser.parse("Первый\n\nВторой")
        #expect(blocks.count == 2)
        #expect(blocks[0].text == "Первый")
        #expect(blocks[1].text == "Второй")
    }
}
```

- [ ] **Step 2: Запустить — падает**

- [ ] **Step 3: Реализация**

```swift
import Foundation

enum DocParagraphStyle: Equatable {
    case normal, heading1, heading2, heading3
}

enum DocListType: Equatable {
    case bullet, numbered
}

struct DocBlock: Equatable {
    var style: DocParagraphStyle
    var listType: DocListType?
    var text: String
    /// Диапазоны жирного в `text`, в индексах символов (Character offsets).
    var boldRanges: [Range<Int>]
}

enum MarkdownDocParser {
    static func parse(_ markdown: String) -> [DocBlock] {
        var blocks: [DocBlock] = []
        for rawLine in markdown.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            var style: DocParagraphStyle = .normal
            var listType: DocListType? = nil
            var content = line

            if line.hasPrefix("### ") { style = .heading3; content = String(line.dropFirst(4)) }
            else if line.hasPrefix("## ") { style = .heading2; content = String(line.dropFirst(3)) }
            else if line.hasPrefix("# ") { style = .heading1; content = String(line.dropFirst(2)) }
            else if line.hasPrefix("- ") || line.hasPrefix("* ") { listType = .bullet; content = String(line.dropFirst(2)) }
            else if let m = numberedPrefixLength(line) { listType = .numbered; content = String(line.dropFirst(m)) }

            let (plain, bold) = extractBold(content)
            blocks.append(DocBlock(style: style, listType: listType, text: plain, boldRanges: bold))
        }
        return blocks
    }

    /// Длина префикса вида "12. " если строка нумерованный пункт, иначе nil.
    private static func numberedPrefixLength(_ line: String) -> Int? {
        var idx = line.startIndex
        var digits = 0
        while idx < line.endIndex, line[idx].isNumber { idx = line.index(after: idx); digits += 1 }
        guard digits > 0, idx < line.endIndex, line[idx] == "." else { return nil }
        idx = line.index(after: idx)
        guard idx < line.endIndex, line[idx] == " " else { return nil }
        return digits + 2 // цифры + "." + " "
    }

    /// Убирает **…** и *…*, возвращает плоский текст и диапазоны жирного (в Character-индексах).
    private static func extractBold(_ input: String) -> (String, [Range<Int>]) {
        var result = ""
        var ranges: [Range<Int>] = []
        var chars = Array(input)
        var i = 0
        var bold = false
        var boldStart = 0
        while i < chars.count {
            if chars[i] == "*" && i + 1 < chars.count && chars[i + 1] == "*" {
                if !bold { bold = true; boldStart = result.count }
                else { bold = false; ranges.append(boldStart..<result.count) }
                i += 2
                continue
            }
            // одиночную * (курсив) просто снимаем как маркер, текст оставляем
            if chars[i] == "*" {
                i += 1
                continue
            }
            result.append(chars[i])
            i += 1
        }
        if bold { ranges.append(boldStart..<result.count) } // незакрытый — до конца
        return (result, ranges)
    }
}
```

- [ ] **Step 4: Запустить тесты — зелёные**

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/MarkdownDocParser.swift \
        SEOContentCreator/SEOContentCreatorTests/MarkdownDocParserTests.swift
git commit -m "feat(publish): markdown→DocBlock parser"
```

---

## Task 4: `DocsRequestBuilder` (блоки → запросы batchUpdate)

Строит массив запросов Google Docs: один `insertText` со всем текстом в индекс 1, затем `updateParagraphStyle`/`createParagraphBullets`/`updateTextStyle` по вычисленным диапазонам. В Google Docs индексация в UTF-16; абзац заканчивается `\n`, который тоже занимает позицию.

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Logic/DocsRequestBuilder.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/DocsRequestBuilderTests.swift`

- [ ] **Step 1: Написать падающие тесты**

```swift
import Testing
@testable import SEOContentCreator

struct DocsRequestBuilderTests {
    @Test func insertsAllTextFirst() {
        let blocks = [DocBlock(style: .heading1, listType: nil, text: "Заголовок", boldRanges: [])]
        let reqs = DocsRequestBuilder.build(blocks: blocks)
        let insert = reqs.first?["insertText"] as? [String: Any]
        #expect((insert?["text"] as? String) == "Заголовок\n")
        let loc = insert?["location"] as? [String: Any]
        #expect((loc?["index"] as? Int) == 1)
    }

    @Test func setsHeadingParagraphStyle() {
        let blocks = [DocBlock(style: .heading2, listType: nil, text: "Подзаголовок", boldRanges: [])]
        let reqs = DocsRequestBuilder.build(blocks: blocks)
        let styled = reqs.compactMap { $0["updateParagraphStyle"] as? [String: Any] }
        let named = (styled.first?["paragraphStyle"] as? [String: Any])?["namedStyleType"] as? String
        #expect(named == "HEADING_2")
    }

    @Test func computesBoldRangeInDocumentIndices() {
        // "Текст" (5) + " " ... строим "AB **C**" → плоско "AB C", bold "C" в 3..<4 от начала абзаца.
        let blocks = [DocBlock(style: .normal, listType: nil, text: "AB C", boldRanges: [3..<4])]
        let reqs = DocsRequestBuilder.build(blocks: blocks)
        let textStyle = reqs.compactMap { $0["updateTextStyle"] as? [String: Any] }.first
        let range = textStyle?["range"] as? [String: Any]
        // текст вставлен с индекса 1 → "C" на позиции 1+3=4..<1+4=5
        #expect((range?["startIndex"] as? Int) == 4)
        #expect((range?["endIndex"] as? Int) == 5)
        #expect(((textStyle?["textStyle"] as? [String: Any])?["bold"] as? Bool) == true)
    }

    @Test func emitsBulletRequestForList() {
        let blocks = [
            DocBlock(style: .normal, listType: .bullet, text: "пункт", boldRanges: [])
        ]
        let reqs = DocsRequestBuilder.build(blocks: blocks)
        let bullets = reqs.compactMap { $0["createParagraphBullets"] as? [String: Any] }
        #expect(bullets.count == 1)
    }
}
```

- [ ] **Step 2: Запустить — падает**

- [ ] **Step 3: Реализация**

```swift
import Foundation

enum DocsRequestBuilder {
    /// Длина строки в UTF-16 (индексация Google Docs).
    private static func len(_ s: String) -> Int { s.utf16.count }

    static func build(blocks: [DocBlock]) -> [[String: Any]] {
        // 1) Полный текст: каждый блок + "\n".
        var fullText = ""
        for b in blocks { fullText += b.text + "\n" }

        var requests: [[String: Any]] = []
        if !fullText.isEmpty {
            requests.append([
                "insertText": [
                    "location": ["index": 1],
                    "text": fullText
                ]
            ])
        }

        // 2) Идём по блокам, считая абсолютные индексы (старт документа = 1).
        var cursor = 1
        for b in blocks {
            let blockLen = len(b.text)
            let paraStart = cursor
            let paraEnd = cursor + blockLen + 1 // включая завершающий "\n"

            // Стиль абзаца (заголовок / обычный).
            let named: String
            switch b.style {
            case .normal:   named = "NORMAL_TEXT"
            case .heading1: named = "HEADING_1"
            case .heading2: named = "HEADING_2"
            case .heading3: named = "HEADING_3"
            }
            requests.append([
                "updateParagraphStyle": [
                    "range": ["startIndex": paraStart, "endIndex": paraEnd],
                    "paragraphStyle": ["namedStyleType": named],
                    "fields": "namedStyleType"
                ]
            ])

            // Списки.
            if let listType = b.listType {
                let preset = listType == .bullet ? "BULLET_DISC_CIRCLE_SQUARE" : "NUMBERED_DECIMAL_ALPHA_ROMAN"
                requests.append([
                    "createParagraphBullets": [
                        "range": ["startIndex": paraStart, "endIndex": paraEnd],
                        "bulletPreset": preset
                    ]
                ])
            }

            // Жирный — диапазоны заданы в Character-офсетах; пересчёт в UTF-16 от начала блока.
            for r in b.boldRanges {
                let prefix = String(Array(b.text)[0..<r.lowerBound])
                let middle = String(Array(b.text)[r.lowerBound..<r.upperBound])
                let start = paraStart + len(prefix)
                let end = start + len(middle)
                requests.append([
                    "updateTextStyle": [
                        "range": ["startIndex": start, "endIndex": end],
                        "textStyle": ["bold": true],
                        "fields": "bold"
                    ]
                ])
            }

            cursor = paraEnd
        }
        return requests
    }
}
```

- [ ] **Step 4: Запустить — зелёные**

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/DocsRequestBuilder.swift \
        SEOContentCreator/SEOContentCreatorTests/DocsRequestBuilderTests.swift
git commit -m "feat(publish): Docs batchUpdate request builder"
```

---

## Task 5: `GoogleDocsClient` (REST Docs/Drive)

REST через `URLSession`; access-токен берётся через внедрённый `tokenProvider: () async throws -> String` (развязка с auth для тестов). Ошибки — `LocalizedError`.

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Logic/GoogleDocsClient.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/GoogleDocsClientTests.swift`

- [ ] **Step 1: Написать падающие тесты**

Использует общий мок. Если `MockURLProtocol` уже объявлен в `OpenAIClientTests.swift`, переиспользуем его (он `@testable`-видим), но он отдаёт один статичный ответ. Для нескольких ответов подряд добавим отдельный мок с очередью.

```swift
import Testing
import Foundation
@testable import SEOContentCreator

final class GoogleMockURLProtocol: URLProtocol {
    struct Stub { let status: Int; let body: String }
    nonisolated(unsafe) static var queue: [Stub] = []
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let stub = Self.queue.isEmpty ? Stub(status: 200, body: "{}") : Self.queue.removeFirst()
        let resp = HTTPURLResponse(url: request.url!, statusCode: stub.status, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(stub.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct GoogleDocsClientTests {
    private func session() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [GoogleMockURLProtocol.self]
        return URLSession(configuration: cfg)
    }
    private func client() -> GoogleDocsClient {
        GoogleDocsClient(session: session(), tokenProvider: { "test-token" })
    }

    @Test func createDocumentReturnsID() async throws {
        GoogleMockURLProtocol.queue = [.init(status: 200, body: #"{"documentId":"doc-42"}"#)]
        GoogleMockURLProtocol.requests = []
        let id = try await client().createDocument(title: "Моя статья")
        #expect(id == "doc-42")
        let req = try #require(GoogleMockURLProtocol.requests.first)
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        #expect(req.url?.absoluteString == "https://docs.googleapis.com/v1/documents")
    }

    @Test func unauthorizedMapsToError() async {
        GoogleMockURLProtocol.queue = [.init(status: 401, body: "{}")]
        let c = client()
        await #expect(throws: GoogleDocsClient.DocsError.unauthorized) {
            _ = try await c.createDocument(title: "x")
        }
    }

    @Test func findOrCreateFolderReturnsExisting() async throws {
        GoogleMockURLProtocol.queue = [
            .init(status: 200, body: #"{"files":[{"id":"folder-7","name":"SEO-статьи клиники"}]}"#)
        ]
        let id = try await client().findOrCreateFolder(name: "SEO-статьи клиники")
        #expect(id == "folder-7")
    }

    @Test func findOrCreateFolderCreatesWhenMissing() async throws {
        GoogleMockURLProtocol.queue = [
            .init(status: 200, body: #"{"files":[]}"#),
            .init(status: 200, body: #"{"id":"folder-new"}"#)
        ]
        let id = try await client().findOrCreateFolder(name: "SEO-статьи клиники")
        #expect(id == "folder-new")
    }
}
```

- [ ] **Step 2: Запустить — падает**

- [ ] **Step 3: Реализация**

```swift
import Foundation

struct GoogleDocsClient {
    enum DocsError: Error, Equatable, LocalizedError {
        case unauthorized
        case http(Int)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .unauthorized: return "Google отклонил запрос (401). Войдите в Google заново в Настройках."
            case .http(let c): return "Ошибка Google API (HTTP \(c)). Попробуйте позже."
            case .badResponse: return "Не удалось разобрать ответ Google."
            }
        }
    }

    let session: URLSession
    let tokenProvider: () async throws -> String
    let maxAttempts: Int

    init(session: URLSession = .shared,
         tokenProvider: @escaping () async throws -> String,
         maxAttempts: Int = 4) {
        self.session = session
        self.tokenProvider = tokenProvider
        self.maxAttempts = maxAttempts
    }

    // MARK: Public API

    func createDocument(title: String) async throws -> String {
        let url = URL(string: "https://docs.googleapis.com/v1/documents")!
        let data = try await send(url: url, method: "POST", json: ["title": title])
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = obj["documentId"] as? String else { throw DocsError.badResponse }
        return id
    }

    func batchUpdate(docID: String, requests: [[String: Any]]) async throws {
        let url = URL(string: "https://docs.googleapis.com/v1/documents/\(docID):batchUpdate")!
        _ = try await send(url: url, method: "POST", json: ["requests": requests])
    }

    /// Удаляет всё тело документа (для перезаписи). Диапазон 1..<endIndex берётся из documents.get.
    func clearBody(docID: String) async throws {
        let getURL = URL(string: "https://docs.googleapis.com/v1/documents/\(docID)")!
        let data = try await send(url: getURL, method: "GET", json: nil)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = obj["body"] as? [String: Any],
              let content = body["content"] as? [[String: Any]],
              let endIndex = content.compactMap({ $0["endIndex"] as? Int }).max(),
              endIndex > 2 else { return }
        // Последний "\n" удалять нельзя → endIndex-1.
        try await batchUpdate(docID: docID, requests: [[
            "deleteContentRange": [
                "range": ["startIndex": 1, "endIndex": endIndex - 1]
            ]
        ]])
    }

    func findOrCreateFolder(name: String) async throws -> String {
        var comps = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        let q = "mimeType='application/vnd.google-apps.folder' and name='\(name)' and trashed=false"
        comps.queryItems = [URLQueryItem(name: "q", value: q), URLQueryItem(name: "fields", value: "files(id,name)")]
        let data = try await send(url: comps.url!, method: "GET", json: nil)
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let files = obj["files"] as? [[String: Any]],
           let id = files.first?["id"] as? String {
            return id
        }
        // Создать
        let createURL = URL(string: "https://www.googleapis.com/drive/v3/files")!
        let created = try await send(url: createURL, method: "POST",
            json: ["name": name, "mimeType": "application/vnd.google-apps.folder"])
        guard let obj = try? JSONSerialization.jsonObject(with: created) as? [String: Any],
              let id = obj["id"] as? String else { throw DocsError.badResponse }
        return id
    }

    func moveToFolder(fileID: String, folderID: String) async throws {
        var comps = URLComponents(string: "https://www.googleapis.com/drive/v3/files/\(fileID)")!
        comps.queryItems = [URLQueryItem(name: "addParents", value: folderID),
                            URLQueryItem(name: "removeParents", value: "root")]
        _ = try await send(url: comps.url!, method: "PATCH", json: [:])
    }

    static func documentURL(id: String) -> String {
        "https://docs.google.com/document/d/\(id)/edit"
    }

    // MARK: Transport (retry + backoff)

    private func send(url: URL, method: String, json: [String: Any]?) async throws -> Data {
        var lastError: Error = DocsError.badResponse
        for attempt in 0..<maxAttempts {
            do {
                let token = try await tokenProvider()
                var req = URLRequest(url: url)
                req.httpMethod = method
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                if let json {
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = try JSONSerialization.data(withJSONObject: json)
                }
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
}
```

- [ ] **Step 4: Запустить — зелёные**

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/GoogleDocsClient.swift \
        SEOContentCreator/SEOContentCreatorTests/GoogleDocsClientTests.swift
git commit -m "feat(publish): Google Docs/Drive REST client"
```

---

## Task 6: `GoogleAuthService` (OAuth desktop + PKCE)

Юнит-тестируем чистую логику: построение auth-URL, обмен кода, обновление токена. Интерактивная часть (браузер + NWListener) изолирована в методе `signIn()` и проверяется вручную.

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Logic/GoogleAuthService.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/GoogleAuthServiceTests.swift`

- [ ] **Step 1: Написать падающие тесты**

```swift
import Testing
import Foundation
@testable import SEOContentCreator

@Suite(.serialized)
struct GoogleAuthServiceTests {
    private func session() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [GoogleMockURLProtocol.self]
        return URLSession(configuration: cfg)
    }

    @Test func authURLContainsScopesAndPKCE() {
        let url = GoogleAuthService.buildAuthURL(
            clientID: "cid", redirectURI: "http://127.0.0.1:5555", codeChallenge: "chal"
        )
        let s = url.absoluteString
        #expect(s.contains("client_id=cid"))
        #expect(s.contains("code_challenge=chal"))
        #expect(s.contains("code_challenge_method=S256"))
        #expect(s.contains("access_type=offline"))
        #expect(s.contains("documents"))
        #expect(s.contains("drive.file"))
    }

    @Test func exchangeCodeStoresTokens() async throws {
        try? GoogleCredentialStore.deleteAll()
        try GoogleCredentialStore.saveClient(id: "cid", secret: "sec")
        GoogleMockURLProtocol.queue = [.init(status: 200,
            body: #"{"access_token":"at1","refresh_token":"rt1","expires_in":3600}"#)]
        let auth = GoogleAuthService(session: session())
        try await auth.exchangeCode("the-code", verifier: "ver", redirectURI: "http://127.0.0.1:5555")
        let tokens = try #require(GoogleCredentialStore.loadTokens())
        #expect(tokens.accessToken == "at1")
        #expect(tokens.refreshToken == "rt1")
    }

    @Test func validAccessTokenRefreshesWhenExpired() async throws {
        try? GoogleCredentialStore.deleteAll()
        try GoogleCredentialStore.saveClient(id: "cid", secret: "sec")
        try GoogleCredentialStore.saveTokens(GoogleTokens(
            accessToken: "old", refreshToken: "rt", expiry: Date(timeIntervalSince1970: 0)))
        GoogleMockURLProtocol.queue = [.init(status: 200,
            body: #"{"access_token":"fresh","expires_in":3600}"#)]
        let auth = GoogleAuthService(session: session())
        let token = try await auth.validAccessToken()
        #expect(token == "fresh")
    }

    @Test func validAccessTokenThrowsWhenNotSignedIn() async {
        try? GoogleCredentialStore.deleteAll()
        let auth = GoogleAuthService(session: session())
        await #expect(throws: GoogleAuthService.AuthError.notSignedIn) {
            _ = try await auth.validAccessToken()
        }
    }
}
```

- [ ] **Step 2: Запустить — падает**

- [ ] **Step 3: Реализация**

```swift
import Foundation
import CryptoKit
import AppKit
import Network

@MainActor
@Observable
final class GoogleAuthService {
    enum AuthError: Error, Equatable, LocalizedError {
        case noClientCredentials
        case notSignedIn
        case cancelled
        case tokenExchangeFailed
        var errorDescription: String? {
            switch self {
            case .noClientCredentials: return "Укажите Client ID и Client Secret Google в Настройках."
            case .notSignedIn: return "Войдите в Google в Настройках."
            case .cancelled: return "Вход в Google отменён."
            case .tokenExchangeFailed: return "Не удалось получить токен Google."
            }
        }
    }

    static let scopes = ["https://www.googleapis.com/auth/documents",
                         "https://www.googleapis.com/auth/drive.file"]

    var lastErrorMessage: String?
    var isSignedIn: Bool { GoogleCredentialStore.isSignedIn }

    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    // MARK: Pure helpers (tested)

    static func buildAuthURL(clientID: String, redirectURI: String, codeChallenge: String) -> URL {
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: codeChallenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent")
        ]
        return c.url!
    }

    static func codeChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncodedString()
    }

    static func makeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    // MARK: Token endpoints (tested via exchangeCode / validAccessToken)

    func exchangeCode(_ code: String, verifier: String, redirectURI: String) async throws {
        guard let id = GoogleCredentialStore.loadClientID(),
              let secret = GoogleCredentialStore.loadClientSecret() else { throw AuthError.noClientCredentials }
        let form = [
            "code": code, "client_id": id, "client_secret": secret,
            "code_verifier": verifier, "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ]
        let json = try await postForm(form)
        guard let access = json["access_token"] as? String,
              let refresh = json["refresh_token"] as? String,
              let expiresIn = json["expires_in"] as? Int else { throw AuthError.tokenExchangeFailed }
        try GoogleCredentialStore.saveTokens(GoogleTokens(
            accessToken: access, refreshToken: refresh,
            expiry: Date().addingTimeInterval(TimeInterval(expiresIn))))
    }

    func validAccessToken() async throws -> String {
        guard let tokens = GoogleCredentialStore.loadTokens() else { throw AuthError.notSignedIn }
        if !tokens.isExpired { return tokens.accessToken }
        guard let id = GoogleCredentialStore.loadClientID(),
              let secret = GoogleCredentialStore.loadClientSecret() else { throw AuthError.noClientCredentials }
        let form = [
            "client_id": id, "client_secret": secret,
            "refresh_token": tokens.refreshToken, "grant_type": "refresh_token"
        ]
        let json = try await postForm(form)
        guard let access = json["access_token"] as? String,
              let expiresIn = json["expires_in"] as? Int else { throw AuthError.tokenExchangeFailed }
        let updated = GoogleTokens(accessToken: access, refreshToken: tokens.refreshToken,
                                   expiry: Date().addingTimeInterval(TimeInterval(expiresIn)))
        try GoogleCredentialStore.saveTokens(updated)
        return access
    }

    func signOut() { try? GoogleCredentialStore.deleteAll() }

    private func postForm(_ fields: [String: String]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = fields.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? $0.value)" }
            .joined(separator: "&").data(using: .utf8)
        let (data, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthError.tokenExchangeFailed
        }
        return json
    }

    // MARK: Interactive sign-in (manual-tested; browser + loopback)

    func signIn() async throws {
        guard let id = GoogleCredentialStore.loadClientID() else { throw AuthError.noClientCredentials }
        let verifier = Self.makeVerifier()
        let challenge = Self.codeChallenge(for: verifier)
        let listener = try LoopbackListener()
        let redirect = "http://127.0.0.1:\(listener.port)"
        let authURL = Self.buildAuthURL(clientID: id, redirectURI: redirect, codeChallenge: challenge)
        NSWorkspace.shared.open(authURL)
        let code = try await listener.waitForCode()
        try await exchangeCode(code, verifier: verifier, redirectURI: redirect)
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "+&=")
        return set
    }()
}
```

- [ ] **Step 4: Создать `LoopbackListener` (часть того же файла или отдельный `LoopbackListener.swift`)**

Минимальный TCP-слушатель на `127.0.0.1`, отдаёт страницу «можно закрыть окно» и извлекает `code`.

```swift
import Network
import Foundation

final class LoopbackListener {
    let port: UInt16
    private let listener: NWListener
    private var continuation: CheckedContinuation<String, Error>?

    init() throws {
        let l = try NWListener(using: .tcp, on: .any)
        self.listener = l
        // Запускаем и узнаём порт.
        let sem = DispatchSemaphore(value: 0)
        var boundPort: UInt16 = 0
        l.stateUpdateHandler = { state in
            if case .ready = state, let p = l.port?.rawValue { boundPort = p; sem.signal() }
        }
        l.start(queue: .global())
        sem.wait()
        self.port = boundPort
    }

    func waitForCode() async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            listener.newConnectionHandler = { [weak self] conn in
                conn.start(queue: .global())
                conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                    guard let data, let request = String(data: data, encoding: .utf8) else { return }
                    // Первая строка: "GET /?code=XXX&... HTTP/1.1"
                    let code = Self.extractCode(from: request)
                    let html = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n\r\n<html><body><h3>Готово. Можно закрыть это окно и вернуться в приложение.</h3></body></html>"
                    conn.send(content: Data(html.utf8), completion: .contentProcessed { _ in conn.cancel() })
                    self?.listener.cancel()
                    if let code { self?.continuation?.resume(returning: code) }
                    else { self?.continuation?.resume(throwing: GoogleAuthService.AuthError.cancelled) }
                    self?.continuation = nil
                }
            }
        }
    }

    static func extractCode(from httpRequest: String) -> String? {
        guard let firstLine = httpRequest.components(separatedBy: "\r\n").first,
              let pathPart = firstLine.components(separatedBy: " ").dropFirst().first,
              let comps = URLComponents(string: "http://127.0.0.1\(pathPart)") else { return nil }
        return comps.queryItems?.first(where: { $0.name == "code" })?.value
    }
}
```

Доп. тест (чистый разбор):

```swift
    @Test func extractsCodeFromHTTPRequest() {
        let req = "GET /?code=ABC123&scope=x HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
        #expect(LoopbackListener.extractCode(from: req) == "ABC123")
    }
```

- [ ] **Step 5: Запустить юнит-тесты — зелёные** (интерактивный `signIn()` не тестируется автоматически)

- [ ] **Step 6: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/GoogleAuthService.swift \
        SEOContentCreator/SEOContentCreatorTests/GoogleAuthServiceTests.swift
git commit -m "feat(publish): Google OAuth desktop service (PKCE + loopback)"
```

---

## Task 7: `ArticlePublisher` (оркестратор)

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Logic/ArticlePublisher.swift`
- Test: `SEOContentCreator/SEOContentCreatorTests/ArticlePublisherTests.swift`

Развязка для тестов: `ArticlePublisher` зависит от протокола `DocsPublishing` (его реализует `GoogleDocsClient`), чтобы подставить фейк.

- [ ] **Step 1: Написать падающие тесты**

```swift
import Testing
import Foundation
import SwiftData
@testable import SEOContentCreator

final class FakeDocsClient: DocsPublishing {
    nonisolated(unsafe) var created: [String] = []
    nonisolated(unsafe) var batched: [(String, [[String: Any]])] = []
    nonisolated(unsafe) var cleared: [String] = []
    nonisolated(unsafe) var moved: [(String, String)] = []
    nonisolated(unsafe) var nextDocID = "doc-new"

    func createDocument(title: String) async throws -> String { created.append(title); return nextDocID }
    func batchUpdate(docID: String, requests: [[String: Any]]) async throws { batched.append((docID, requests)) }
    func clearBody(docID: String) async throws { cleared.append(docID) }
    func findOrCreateFolder(name: String) async throws -> String { "folder-1" }
    func moveToFolder(fileID: String, folderID: String) async throws { moved.append((fileID, folderID)) }
}

@MainActor
struct ArticlePublisherTests {
    private func ctx() throws -> ModelContext {
        try ModelContainer(for: Topic.self, ExternalDocument.self, ArticleVersion.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true)).mainContext
    }
    private func topicWithText(_ ctx: ModelContext, _ text: String) -> Topic {
        let t = Topic(title: "Тема", articleType: .article)
        ctx.insert(t)
        let v = ArticleVersion(stage: .draft, source: .generated, text: text, agentName: "ИИ-автор", templateID: UUID(), modelName: "gpt-4.1")
        v.topic = t
        ctx.insert(v)
        t.currentVersionID = v.uuid
        return t
    }

    @Test func newDocumentCreatesAndRecords() async throws {
        let context = try ctx()
        let topic = topicWithText(context, "# Заголовок\nАбзац.")
        let fake = FakeDocsClient()
        let publisher = ArticlePublisher(docs: fake, tokenProvider: { "t" }, folderName: "SEO-статьи клиники")
        await publisher.publish(topic: topic, mode: .newDocument, in: context)

        #expect(publisher.lastErrorMessage == nil)
        #expect(fake.created == ["Тема"])
        #expect(fake.moved.first?.1 == "folder-1")
        #expect(topic.publications.count == 1)
        #expect(topic.externalDocURL?.contains("doc-new") == true)
        #expect(topic.publishedAt != nil)
    }

    @Test func overwriteReusesExistingDocAndClears() async throws {
        let context = try ctx()
        let topic = topicWithText(context, "Текст")
        let prev = ExternalDocument(docID: "doc-old", docURL: GoogleDocsClient.documentURL(id: "doc-old"), mode: .newDocument)
        prev.topic = topic; context.insert(prev)
        let fake = FakeDocsClient()
        let publisher = ArticlePublisher(docs: fake, tokenProvider: { "t" }, folderName: "SEO-статьи клиники")
        await publisher.publish(topic: topic, mode: .overwrite, in: context)

        #expect(fake.created.isEmpty)
        #expect(fake.cleared == ["doc-old"])
        #expect(fake.batched.first?.0 == "doc-old")
    }

    @Test func noCurrentVersionSetsError() async throws {
        let context = try ctx()
        let topic = Topic(title: "Пустая", articleType: .article)
        context.insert(topic)
        let publisher = ArticlePublisher(docs: FakeDocsClient(), tokenProvider: { "t" }, folderName: "f")
        await publisher.publish(topic: topic, mode: .newDocument, in: context)
        #expect(publisher.lastErrorMessage != nil)
        #expect(topic.publications.isEmpty)
    }
}
```

- [ ] **Step 2: Запустить — падает**

- [ ] **Step 3: Реализация**

```swift
import Foundation
import SwiftData

protocol DocsPublishing {
    func createDocument(title: String) async throws -> String
    func batchUpdate(docID: String, requests: [[String: Any]]) async throws
    func clearBody(docID: String) async throws
    func findOrCreateFolder(name: String) async throws -> String
    func moveToFolder(fileID: String, folderID: String) async throws
}

extension GoogleDocsClient: DocsPublishing {}

@MainActor
@Observable
final class ArticlePublisher {
    var isPublishing = false
    var lastErrorMessage: String?

    private let docs: DocsPublishing
    private let tokenProvider: () async throws -> String
    private let folderName: String

    init(docs: DocsPublishing, tokenProvider: @escaping () async throws -> String,
         folderName: String = "SEO-статьи клиники") {
        self.docs = docs
        self.tokenProvider = tokenProvider
        self.folderName = folderName
    }

    /// Production convenience.
    static func live(auth: GoogleAuthService) -> ArticlePublisher {
        let client = GoogleDocsClient(tokenProvider: { try await auth.validAccessToken() })
        return ArticlePublisher(docs: client, tokenProvider: { try await auth.validAccessToken() })
    }

    func publish(topic: Topic, mode: PublishMode, in context: ModelContext) async {
        isPublishing = true
        lastErrorMessage = nil
        defer { isPublishing = false }

        guard let version = topic.currentVersion, !version.text.isEmpty else {
            lastErrorMessage = "Нет принятой версии текста для публикации."
            return
        }
        do {
            _ = try await tokenProvider() // ранняя проверка авторизации
            let blocks = MarkdownDocParser.parse(version.text)
            let requests = DocsRequestBuilder.build(blocks: blocks)

            let docID: String
            switch mode {
            case .newDocument:
                docID = try await docs.createDocument(title: topic.title)
            case .overwrite:
                guard let existing = topic.publications.sorted(by: { $0.publishedAt > $1.publishedAt }).first?.docID
                        ?? topic.externalDocURL.flatMap(Self.docID(fromURL:)) else {
                    // нет предыдущего — поведём как новый
                    let id = try await docs.createDocument(title: topic.title)
                    try await fill(docID: id, requests: requests)
                    try await place(docID: id)
                    record(topic: topic, docID: id, mode: .newDocument, in: context)
                    return
                }
                docID = existing
                try await docs.clearBody(docID: docID)
            }

            try await fill(docID: docID, requests: requests)
            if mode == .newDocument { try await place(docID: docID) }
            record(topic: topic, docID: docID, mode: mode, in: context)
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func fill(docID: String, requests: [[String: Any]]) async throws {
        try await docs.batchUpdate(docID: docID, requests: requests)
    }

    private func place(docID: String) async throws {
        let folder = try await docs.findOrCreateFolder(name: folderName)
        try await docs.moveToFolder(fileID: docID, folderID: folder)
    }

    private func record(topic: Topic, docID: String, mode: PublishMode, in context: ModelContext) {
        let url = GoogleDocsClient.documentURL(id: docID)
        let doc = ExternalDocument(docID: docID, docURL: url, mode: mode)
        doc.topic = topic
        context.insert(doc)
        topic.externalDocURL = url
        topic.publishedAt = .now
    }

    static func docID(fromURL url: String) -> String? {
        // https://docs.google.com/document/d/<ID>/edit
        guard let range = url.range(of: "/document/d/") else { return nil }
        let tail = url[range.upperBound...]
        return tail.components(separatedBy: "/").first
    }
}
```

- [ ] **Step 4: Запустить — зелёные**

- [ ] **Step 5: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Logic/ArticlePublisher.swift \
        SEOContentCreator/SEOContentCreatorTests/ArticlePublisherTests.swift
git commit -m "feat(publish): ArticlePublisher orchestrator (new/overwrite)"
```

---

## Task 8: Настройки — раздел Google

**Files:**
- Modify: `SEOContentCreator/SEOContentCreator/Views/SettingsView.swift`

Чистой логики нет — UI поверх протестированных юнитов. Тестов не добавляем (визуальная проверка вручную).

- [ ] **Step 1: Добавить состояние и секцию**

В `SettingsView` добавить поля состояния и новую `Section` после «Изображения»:

```swift
    @State private var googleClientID = ""
    @State private var googleClientSecret = ""
    @State private var hasGoogleClient = GoogleCredentialStore.hasClient
    @State private var isGoogleSignedIn = GoogleCredentialStore.isSignedIn
    @State private var googleMessage: String?
    @State private var auth = GoogleAuthService()
```

```swift
            Section("Google Docs") {
                SecureField("Client ID", text: $googleClientID)
                SecureField("Client Secret", text: $googleClientSecret)
                HStack {
                    Button("Сохранить ключи") { saveGoogleClient() }
                        .disabled(googleClientID.isEmpty || googleClientSecret.isEmpty)
                    Spacer()
                    if hasGoogleClient {
                        Label("Ключи сохранены", systemImage: "checkmark.seal").foregroundStyle(.green)
                    }
                }
                HStack {
                    if isGoogleSignedIn {
                        Label("Подключено к Google", systemImage: "link").foregroundStyle(.green)
                        Button("Выйти", role: .destructive) { signOutGoogle() }
                    } else {
                        Button("Войти в Google") { Task { await signInGoogle() } }
                            .disabled(!hasGoogleClient)
                    }
                }
                if let googleMessage {
                    Text(googleMessage).font(.caption).foregroundStyle(.secondary)
                }
            }
```

- [ ] **Step 2: Добавить методы**

```swift
    private func saveGoogleClient() {
        do {
            try GoogleCredentialStore.saveClient(id: googleClientID, secret: googleClientSecret)
            googleClientID = ""; googleClientSecret = ""
            hasGoogleClient = true
            googleMessage = "Ключи Google сохранены в Keychain."
        } catch {
            googleMessage = "Не удалось сохранить: \(error.localizedDescription)"
        }
    }

    private func signInGoogle() async {
        do {
            try await auth.signIn()
            isGoogleSignedIn = true
            googleMessage = "Вход выполнен."
        } catch {
            googleMessage = (error as? LocalizedError)?.errorDescription ?? "Вход не удался."
        }
    }

    private func signOutGoogle() {
        auth.signOut()
        isGoogleSignedIn = false
        googleMessage = "Выход выполнен."
    }
```

Увеличить высоту окна: `.frame(width: 460, height: 480)`.

- [ ] **Step 3: Скомпилировать**

`xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS'` — успешно.

- [ ] **Step 4: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Views/SettingsView.swift
git commit -m "feat(publish): Google settings (client keys + sign-in)"
```

---

## Task 9: UI публикации — кнопка, лист, история

**Files:**
- Create: `SEOContentCreator/SEOContentCreator/Views/PublishSheet.swift`
- Modify: `SEOContentCreator/SEOContentCreator/Views/TopicWorkspaceView.swift`

- [ ] **Step 1: Создать `PublishSheet.swift`**

Лист с превью, выбором режима (если уже публиковалась), кнопкой публикации и историей.

```swift
import SwiftUI
import SwiftData

struct PublishSheet: View {
    let topic: Topic
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var publisher = ArticlePublisher.live(auth: GoogleAuthService())
    @State private var mode: PublishMode = .newDocument
    @State private var confirmOverwrite = false

    private var hasPrevious: Bool { !topic.publications.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Публикация в Google Docs").font(.title2).bold()

            GroupBox("Что публикуется") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Документ: \(topic.title)")
                    Text("Папка Google Drive: SEO-статьи клиники").foregroundStyle(.secondary)
                    if topic.currentVersion == nil {
                        Text("Нет принятой версии текста.").foregroundStyle(.red)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }

            if hasPrevious {
                Picker("Режим", selection: $mode) {
                    Text("Создать новый документ").tag(PublishMode.newDocument)
                    Text("Перезаписать существующий").tag(PublishMode.overwrite)
                }.pickerStyle(.radioGroup)
            }

            if let error = publisher.lastErrorMessage {
                Text(error).foregroundStyle(.red).font(.callout)
            }

            if !topic.publications.isEmpty {
                GroupBox("История публикаций") {
                    ForEach(topic.publications.sorted(by: { $0.publishedAt > $1.publishedAt }), id: \.uuid) { doc in
                        HStack {
                            Link(doc.docURL, destination: URL(string: doc.docURL)!).lineLimit(1)
                            Spacer()
                            Text(doc.publishedAt, style: .date).foregroundStyle(.secondary).font(.caption)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Закрыть") { dismiss() }
                Button(publisher.isPublishing ? "Публикую…" : "Опубликовать") {
                    if mode == .overwrite { confirmOverwrite = true } else { Task { await doPublish() } }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(publisher.isPublishing || topic.currentVersion == nil)
            }
        }
        .padding(20)
        .frame(width: 520, height: 460)
        .confirmationDialog("Перезаписать существующий документ?", isPresented: $confirmOverwrite) {
            Button("Перезаписать", role: .destructive) { Task { await doPublish() } }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Текущее содержимое документа будет заменено.")
        }
    }

    private func doPublish() async {
        await publisher.publish(topic: topic, mode: mode, in: context)
        if publisher.lastErrorMessage == nil { dismiss() }
    }
}
```

- [ ] **Step 2: Встроить кнопку в `TopicWorkspaceView`**

Найти `.toolbar { ... }` (где кнопка «Изображения») и добавить кнопку «Опубликовать», плюс состояние `@State private var showPublish = false` и `.sheet(isPresented: $showPublish) { PublishSheet(topic: topic) }`.

```swift
            ToolbarItem {
                Button {
                    showPublish = true
                } label: {
                    Label("Опубликовать", systemImage: "paperplane")
                }
            }
```

Если опубликовано — показать в шапке ссылку (там, где статус): если `topic.externalDocURL != nil`, добавить `Link("Открыть в Docs", destination: URL(string: topic.externalDocURL!)!)`.

- [ ] **Step 3: Скомпилировать**

`xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS'` — успешно.

- [ ] **Step 4: Commit**

```bash
git add SEOContentCreator/SEOContentCreator/Views/PublishSheet.swift \
        SEOContentCreator/SEOContentCreator/Views/TopicWorkspaceView.swift
git commit -m "feat(publish): publish sheet + toolbar button + history"
```

---

## Task 10: Интеграция и ручная проверка

- [ ] **Step 1: Полная сборка тестов**

`xcodebuild build-for-testing -scheme SEOContentCreator -destination 'platform=macOS'` — зелёная.

- [ ] **Step 2: Запустить все тесты (Cmd+U в Xcode)** — все зелёные.

- [ ] **Step 3: Ручные проверки (требуют реального Google Cloud OAuth-клиента типа Desktop):**
  - В Настройках ввести Client ID/Secret → «Сохранить ключи».
  - «Войти в Google» → браузер → согласие → «можно закрыть окно» → в Настройках «Подключено».
  - Открыть тему с принятой версией → «Опубликовать» → «Создать новый» → проверить, что документ создан в папке «SEO-статьи клиники», заголовки/списки/жирный на месте.
  - Повторно «Опубликовать» → «Перезаписать» → подтверждение → содержимое заменено в том же документе.
  - Повторно «Опубликовать» → «Создать новый» → создан второй документ; в истории две записи с датами.
  - Отключить интернет → «Опубликовать» → понятная ошибка, тема не помечена опубликованной.

- [ ] **Step 4: Обновить changelog**

Добавить запись в `ai/changelog.md` по образцу существующих (под-проект «Публикация», что реализовано, новые сущности/файлы, ключевые решения, отметить ручные проверки).

- [ ] **Step 5: Commit**

```bash
git add ai/changelog.md
git commit -m "docs: changelog — sub-project Публикация в Google Docs"
```

---

## Self-Review (выполнено при написании плана)

**Покрытие спеки:**
- OAuth (URLSession + PKCE) → Task 6. Скоупы documents+drive.file → Task 6 (`scopes`).
- Ключи Google в Keychain → Task 2 + UI Task 8.
- markdown→Docs (H1/H2/H3, абзацы, жирный/курсив, списки) → Task 3 (парсер) + Task 4 (запросы).
- Создание документа + папка Drive + перемещение → Task 5.
- Повторная публикация новый/перезапись (с подтверждением) → Task 7 (логика) + Task 9 (подтверждение).
- Модель «Внешний документ» + история → Task 1 + Task 9 (список).
- Обработка ошибок (нет ключей/не вошёл/сеть/перезапись docID) → Task 5 (retry/маппинг), Task 6 (AuthError), Task 7 (ветки).
- Тесты по разделу 6 спеки → Tasks 1–7.

**Курсив:** в v1 курсив снимается как маркер (текст сохраняется), отдельный стиль italic не выставляется — допустимое упрощение; при необходимости добавить `italicRanges` по образцу `boldRanges` (отмечено как возможное расширение, не блокер).

**Согласованность типов:** `PublishMode`, `DocBlock`/`DocParagraphStyle`/`DocListType`, `GoogleTokens`, `DocsError`, `AuthError`, `DocsPublishing`, `GoogleDocsClient.documentURL(id:)` — имена совпадают во всех задачах.

**Изображения** — вне объёма (спека, раздел 7), в плане отсутствуют намеренно.

---

## Execution Handoff

План сохранён в `docs/superpowers/plans/2026-06-21-publishing.md`.
