import SwiftUI

/// Section navigation shown in the window toolbar, replacing the old sidebar.
/// The toolbar itself supplies the translucent background, so this view only
/// draws the items and the accent capsule behind the active one.
struct SectionSwitcher: View {
    @Binding var selection: AppSection
    @Namespace private var capsule

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppSection.allCases) { section in
                if section.startsNewGroup {
                    Divider().frame(height: 16).padding(.horizontal, 6)
                }
                item(section)
            }
        }
        .animation(.snappy(duration: 0.22), value: selection)
    }

    private func item(_ section: AppSection) -> some View {
        let isSelected = section == selection

        return Button {
            selection = section
        } label: {
            Label(section.title, systemImage: section.systemImage)
                .labelStyle(.titleAndIcon)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.brandAccent)
                            .matchedGeometryEffect(id: "selection", in: capsule)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("\(section.title) (⌘\(String(section.shortcutKey)))")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
