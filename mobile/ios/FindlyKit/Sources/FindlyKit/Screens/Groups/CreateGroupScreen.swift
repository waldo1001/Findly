import SwiftUI

/// specs/004-ios-client.md §3.4 (001 §12.1; 005 §2.1) — composes ONLY design-system components,
/// bar the system `DatePicker` for `endsAt` (documented exception, same as `HistoryScreen`'s
/// date-range pickers and the live map's first-party MapKit).
public struct CreateGroupScreen: View {
    @Environment(\.theme) private var theme
    // `@StateObject`, NOT `@ObservedObject` — see `HomeScreen`'s doc for the full failure mode
    // (I16). `RootView` constructs this screen's view model inline and re-evaluates on every
    // in-app navigation; `@StateObject` + `@autoclosure` keeps the first instance for this view's
    // lifetime instead of silently discarding the one this screen's state (e.g. `.created`, which
    // `onChange(of: created)` below fires `onCreated` from) lives on.
    @StateObject private var viewModel: CreateGroupViewModel
    @State private var name: String = ""
    @State private var endsAt: Date = GroupEndsAtBounds.defaultEndsAt()
    /// 005 §2.5 item 1 — never preselected; the default stays a dated group (now + 24 h).
    @State private var noEndDate = false
    @State private var expiryPolicy: GroupExpiryPolicy = .delete
    @State private var displayName: String
    private let onCreated: (GroupSummary) -> Void
    /// `limits.maxGroupDurationDays` from the groups-list envelope (001 §9): `nil` = no cap (or the
    /// limits aren't known yet — the server stays authoritative either way, 001 §12.1).
    private let maxGroupDurationDays: Int?

    /// [prefillDisplayName] seeds the display-name field when this screen is reached from the
    /// profile-less first-run flow (`HomeScreen`'s `.profileless` branch, I17) — same "enter it
    /// once" intent as `GroupJoinScreen`/`AcceptInviteScreen`'s own `prefillDisplayName`.
    public init(
        viewModel: @autoclosure @escaping () -> CreateGroupViewModel,
        prefillDisplayName: String = "",
        maxGroupDurationDays: Int? = nil,
        onCreated: @escaping (GroupSummary) -> Void
    ) {
        self.maxGroupDurationDays = maxGroupDurationDays
        _viewModel = StateObject(wrappedValue: viewModel())
        self._displayName = State(initialValue: prefillDisplayName)
        self.onCreated = onCreated
    }

    public var body: some View {
        VStack(spacing: theme.spacing.lg) {
            FindlyNavBar("Create a group")
            content
            Spacer()
        }
        .background(theme.colors.surfaceVariant)
        .onChange(of: created) { group in
            if let group { onCreated(group) }
        }
    }

    private var created: GroupSummary? {
        if case .created(let group) = viewModel.state { return group }
        return nil
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .error, .created:
            form
        case .creating:
            LoadingStateView(message: "Creating group…")
        }
    }

    private var form: some View {
        ScrollView {
            VStack(spacing: theme.spacing.md) {
                if case .error(let message) = viewModel.state {
                    ErrorStateView(message: message)
                }
                FindlyTextField("Group name", text: $name, placeholder: "Festival crew")
                FindlyToggleRow(title: "No end date", isOn: $noEndDate)
                if noEndDate {
                    noEndDateWarning
                } else {
                    endsAtPicker
                }
                policyPicker
                Text(expiryPolicy.policyCopy)
                    .font(theme.typography.bodyMedium.font)
                    .foregroundColor(theme.colors.onSurface.opacity(0.7))
                if noEndDate {
                    Text(GroupNoEndDateCopy.policyNote)
                        .font(theme.typography.labelSmall.font)
                        .foregroundColor(theme.onSurfaceMuted)
                }
                FindlyTextField("Your name for this group", text: $displayName, placeholder: "Eric")
                FindlyButton("Create group") {
                    Task {
                        await viewModel.createGroup(
                            name: name, endsAt: noEndDate ? nil : endsAt, expiryPolicy: expiryPolicy, displayName: displayName
                        )
                    }
                }
            }
            .padding(.horizontal, theme.spacing.xl)
        }
    }

    /// 005 §2.5 item 6 / 004 amendment — bounded below by now + 1 h, and above by
    /// `maxGroupDurationDays` only when the plan has a cap (`nil` = open-ended partial range).
    @ViewBuilder
    private var endsAtPicker: some View {
        let lower = GroupEndsAtBounds.lowerBound()
        if let upper = GroupEndsAtBounds.upperBound(maxGroupDurationDays: maxGroupDurationDays) {
            DatePicker("Ends", selection: $endsAt, in: lower...upper, displayedComponents: [.date, .hourAndMinute])
                .tint(theme.colors.primary)
        } else {
            DatePicker("Ends", selection: $endsAt, in: lower..., displayedComponents: [.date, .hourAndMinute])
                .tint(theme.colors.primary)
        }
    }

    /// 005 §2.5 item 2 — the design system's warning style (`colors.warning`, as `ErrorStateView`/
    /// `PermissionBannerView` use it), directly under the choice and before the Create button.
    private var noEndDateWarning: some View {
        (Text(GroupNoEndDateCopy.warningTitle).bold() + Text(" " + GroupNoEndDateCopy.warningBody))
            .font(theme.typography.bodyMedium.font)
            .foregroundColor(theme.colors.onSurface)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(theme.spacing.md)
            .background(theme.colors.warning.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: theme.corner.sm))
            .accessibilityElement(children: .combine)
    }

    private var policyPicker: some View {
        HStack(spacing: theme.spacing.sm) {
            ForEach(GroupExpiryPolicy.allCases) { policy in
                FindlyButton(policy.title, style: expiryPolicy == policy ? .primary : .secondary) {
                    expiryPolicy = policy
                }
            }
        }
    }
}
