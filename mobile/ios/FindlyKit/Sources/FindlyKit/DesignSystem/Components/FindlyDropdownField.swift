import SwiftUI

/// specs/010-app-shell-and-screen-ux.md §1.2/§4.2, specs/004-ios-client.md §2.3 (010-shell
/// addition) — one selectable value in a `FindlyDropdownField`. Generic over `Value` so the same
/// component serves any single-select field (today: device sync interval, 001 §1.4's seven-value
/// set); it carries no knowledge of what those values mean. `disabledReason` is shown alongside a
/// disabled option instead of silently omitting it — §4.2: "render disabled with the limit as the
/// reason", so the option stays visible (never hidden) but not selectable.
public struct FindlyDropdownOption<Value: Hashable>: Identifiable, Equatable {
    public let value: Value
    public let title: String
    public let isEnabled: Bool
    public let disabledReason: String?

    public var id: Value { value }

    public init(value: Value, title: String, isEnabled: Bool = true, disabledReason: String? = nil) {
        self.value = value
        self.title = title
        self.isEnabled = isEnabled
        self.disabledReason = disabledReason
    }
}

/// specs/010-app-shell-and-screen-ux.md §1.2/§4.2, specs/004-ios-client.md §2.3 — a labeled
/// single-select field presented via the platform-native menu (010 §4.2: "exposed dropdown menu
/// on Android, `Menu`/`Picker` presentation on iOS"). Stateless/presentational like every other
/// design-system component: it renders whatever `options` the caller supplies and reports the
/// selection via `onSelect` — zero knowledge of view models, networking, `features`, or which
/// value is "the sync interval". The caller (a pure plan type, e.g. `SyncIntervalDropdownPlan`)
/// owns which options are enabled/disabled and why.
///
/// Reads `@Environment(\.theme)` only — no literal `Color(...)`, `.font(.system(size:))`, or
/// hardcoded point size (004 §2.3's contract, which this 010-shell addition joins).
public struct FindlyDropdownField<Value: Hashable>: View {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    private let label: String
    private let options: [FindlyDropdownOption<Value>]
    private let selection: Value
    private let onSelect: (Value) -> Void

    public init(
        label: String,
        options: [FindlyDropdownOption<Value>],
        selection: Value,
        onSelect: @escaping (Value) -> Void
    ) {
        self.label = label
        self.options = options
        self.selection = selection
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            Text(label)
                .font(theme.typography.labelSmall.font)
                .tracking(theme.typography.labelSmall.tracking)
                .foregroundColor(theme.onSurfaceMuted)
            Menu {
                ForEach(options) { option in
                    Button {
                        onSelect(option.value)
                    } label: {
                        Text(menuItemTitle(for: option))
                    }
                    .disabled(!option.isEnabled)
                }
            } label: {
                fieldBox
            }
            .disabled(!isEnabled)
            .accessibilityLabel(label)
            .accessibilityValue(currentTitle)
        }
    }

    private func menuItemTitle(for option: FindlyDropdownOption<Value>) -> String {
        guard !option.isEnabled, let reason = option.disabledReason else { return option.title }
        return "\(option.title) — \(reason)"
    }

    private var fieldBox: some View {
        HStack(spacing: theme.spacing.sm) {
            Text(currentTitle)
                .font(theme.typography.bodyLarge.font)
                .foregroundColor(isEnabled ? theme.colors.onSurface : .findlyTextFieldDisabledText)
            Spacer(minLength: theme.spacing.sm)
            // A plain glyph, not an SF Symbol — same convention `StatusChip` already uses for its
            // status glyphs, so no new asset/import is needed for one static chevron.
            Text("▾")
                .font(theme.typography.bodyLarge.font)
                .foregroundColor(theme.outlineStrong)
        }
        .padding(.horizontal, theme.spacing.sm)
        .frame(height: 52)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isEnabled ? theme.colors.surfaceVariant : .findlyTextFieldDisabledFill)
        .clipShape(RoundedRectangle(cornerRadius: theme.corner.md))
        .overlay(
            RoundedRectangle(cornerRadius: theme.corner.md)
                .strokeBorder(isEnabled ? theme.outlineStrong : .findlyTextFieldDisabledBorder, lineWidth: 1.5)
        )
    }

    private var currentTitle: String {
        options.first(where: { $0.value == selection })?.title ?? ""
    }
}

#Preview("FindlyDropdownField — light") {
    VStack(spacing: 16) {
        FindlyDropdownField(
            label: "Sync interval",
            options: SyncIntervalDropdownPlan.options(minSyncIntervalMinutes: 5),
            selection: 15,
            onSelect: { _ in }
        )
        FindlyDropdownField(
            label: "Sync interval",
            options: SyncIntervalDropdownPlan.options(minSyncIntervalMinutes: 15),
            selection: 30,
            onSelect: { _ in }
        )
    }
    .padding()
    .background(Theme.light.colors.surface)
    .environment(\.theme, .light)
}

#Preview("FindlyDropdownField — dark") {
    VStack(spacing: 16) {
        FindlyDropdownField(
            label: "Sync interval",
            options: SyncIntervalDropdownPlan.options(minSyncIntervalMinutes: 5),
            selection: 15,
            onSelect: { _ in }
        )
    }
    .padding()
    .background(Theme.dark.colors.surface)
    .environment(\.theme, .dark)
    .preferredColorScheme(.dark)
}
