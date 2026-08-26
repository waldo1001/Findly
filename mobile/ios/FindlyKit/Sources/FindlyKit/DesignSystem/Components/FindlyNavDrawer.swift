import SwiftUI

/// specs/010-app-shell-and-screen-ux.md §1.2, specs/004-ios-client.md §2.3 — the navigation drawer
/// reached from the Family Map's ☰ button. Stateless/presentational like every other design-system
/// component: it renders a header (family name + caller display name) and the item list
/// `FindlyNavDrawerBuilder` computed, and reports selection/dismissal via closures — it has zero
/// knowledge of `AppCoordinator`, routing, or any view model. iOS has no drawer primitive to wrap
/// (unlike Android's `ModalNavigationDrawer`), so this is a coordinator-driven overlay: the caller
/// (`LiveMapScreen`) shows it conditionally in a `ZStack`/`.overlay`, exactly the pattern documented
/// in 010 §1.2's last bullet.
///
/// Left-edge placement, opened only by the ☰ button (010 §1.2: iOS gets no leading-edge swipe-to-
/// open, per the I19 swipe-back deliberation this spec does not reopen) — that policy lives in
/// `LiveMapScreen` (there is no gesture here to omit; this component simply has no drag handling).
public struct FindlyNavDrawer: View {
    @Environment(\.theme) private var theme
    private let familyName: String
    private let myDisplayName: String
    private let items: [FindlyNavDrawerItem]
    private let selectedId: String?
    private let onSelect: (String) -> Void
    private let onDismiss: () -> Void

    public init(
        familyName: String,
        myDisplayName: String,
        items: [FindlyNavDrawerItem],
        selectedId: String? = nil,
        onSelect: @escaping (String) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.familyName = familyName
        self.myDisplayName = myDisplayName
        self.items = items
        self.selectedId = selectedId
        self.onSelect = onSelect
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
                .accessibilityLabel("Dismiss menu")

            VStack(alignment: .leading, spacing: 0) {
                header
                FindlyCardDivider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(items) { item in
                            row(for: item)
                        }
                    }
                }
            }
            .frame(maxWidth: 300, maxHeight: .infinity, alignment: .leading)
            .background(theme.colors.surface)
            .ignoresSafeArea(edges: .vertical)
        }
        .transition(.move(edge: .leading))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            Text(familyName)
                .font(theme.typography.titleMedium.font)
                .foregroundColor(theme.colors.onSurface)
            Text(myDisplayName)
                .font(theme.typography.bodyMedium.font)
                .foregroundColor(theme.onSurfaceMuted)
        }
        .padding(theme.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(for item: FindlyNavDrawerItem) -> some View {
        let isSelected = item.id == selectedId
        return Button {
            onSelect(item.id)
        } label: {
            Text(item.title)
                .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? theme.colors.primary : theme.colors.onSurface)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, theme.spacing.md)
                .frame(minHeight: 48)
                .background(isSelected ? theme.colors.surfaceVariant : Color.clear)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
