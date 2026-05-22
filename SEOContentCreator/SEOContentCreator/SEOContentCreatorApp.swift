import SwiftUI
import SwiftData

@main
struct SEOContentCreatorApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: Topic.self)
    }
}
