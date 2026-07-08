import SwiftUI

struct QuickCheckView: View {
    var body: some View {
        QuickCheckSheet(showsCloseButton: false)
            .panelCard()
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.pageBackground)
            .navigationTitle("Быстрая проверка")
    }
}
