import Foundation

struct ContentPlanFilter {
    var searchText: String = ""
    var type: ArticleType? = nil

    func apply(to topics: [Topic]) -> [Topic] {
        topics.filter { topic in
            let matchesSearch = searchText.isEmpty
                || topic.title.localizedCaseInsensitiveContains(searchText)
            let matchesType = type == nil || topic.articleType == type
            return matchesSearch && matchesType
        }
    }
}
