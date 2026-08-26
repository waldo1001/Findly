import SwiftUI

/// specs/004-ios-client.md §3.4/§3.5 (001 §12.3–12.9; 005 §2.3; specs/007-public-join-links.md) —
/// composes ONLY design-system components (bar `ShareLink`/`DatePicker`/`.confirmationDialog`, the
/// same documented system-primitive-exception pattern used by the invite/history screens; Android's
/// equivalent exception is Material3 `AlertDialog`, specs/003 §4.3/§12.2). Rendering follows the
/// 005 §2.3 lazy-enforcement matrix: `active` shows the map entry point; roster is hidden for
/// non-owner members during `ended` (grace); rename/extend/rotate are owner-and-active/ended-only
/// (archived groups reject PATCH, 001 §12.4); kick/leave/delete stay available in every
/// non-expired state, matching the matrix exactly. `GROUP_EXPIRED` renders as a persistent notice
/// (`.expired`, same pattern as `GroupMapScreen`) requiring an explicit "Back to groups" tap, not a
/// silent exit. Since 007/I6, the share card's `ShareLink` and on-device QR carry the canonical
/// `https://{joinLinkHost}/g#CODE` link rather than plain text.
public struct GroupDetailScreen: View {
    @Environment(\.theme) private var theme
    // `@StateObject`, NOT `@ObservedObject` — see `HomeScreen`'s doc for the full failure mode
    // (I16). `RootView` constructs this screen's view model inline and re-evaluates on every
    // in-app navigation; `@StateObject` + `@autoclosure` keeps the first instance for this view's
    // lifetime instead of silently discarding the one `.task` observes.
    @StateObject private var viewModel: GroupDetailViewModel
    @State private var editedName: String = ""
    @State private var extendedEndsAt: Date = Date().addingTimeInterval(24 * 3600)
    /// Every owner mutation the spec (003 §12.2/004 §3.4) requires a confirm step for
    /// (rename/extend/end-now/rotate/kick/delete) funnels through this single pending-action +
    /// `.confirmationDialog`, rather than one boolean flag per action.
    @State private var pendingConfirmation: PendingConfirmation?
    /// specs/007-public-join-links.md §1, specs/004-ios-client.md §3.5 — the deployment constant
    /// the share link/QR are built against (`AppConfig.joinLinkHost`).
    private let joinLinkHost: String
    private let onSelectMap: () -> Void
    private let onExit: () -> Void

    public init(
        viewModel: @autoclosure @escaping () -> GroupDetailViewModel,
        joinLinkHost: String = AppConfig.defaultJoinLinkHost,
        onSelectMap: @escaping () -> Void,
        onExit: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.joinLinkHost = joinLinkHost
        self.onSelectMap = onSelectMap
        self.onExit = onExit
    }

    public var body: some View {
        VStack(spacing: 0) {
            FindlyNavBar("Group")
            content
        }
        .background(theme.colors.surfaceVariant)
        .task { await viewModel.load() }
        .onChange(of: viewModel.exitReason) { reason in
            if reason != nil { onExit() }
        }
        .confirmationDialog(
            "Are you sure?", isPresented: isConfirmationPresented,
            titleVisibility: .visible, presenting: pendingConfirmation
        ) { pending in
            Button(pending.actionTitle, role: .destructive) {
                Task { await perform(pending) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(pending.message)
        }
    }

    private var isConfirmationPresented: Binding<Bool> {
        Binding(get: { pendingConfirmation != nil }, set: { if !$0 { pendingConfirmation = nil } })
    }

    private func perform(_ pending: PendingConfirmation) async {
        switch pending {
        case .rename: await viewModel.rename(name: editedName)
        case .extend: await viewModel.extend(endsAt: extendedEndsAt)
        case .endNow: await viewModel.endNow()
        case .rotateCode: await viewModel.rotateCode()
        case .kick(let userId, _): await viewModel.kick(userId: userId)
        case .delete: await viewModel.deleteGroup()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            LoadingStateView(message: "Loading group…")
        case .error(let message):
            ErrorStateView(message: message) {
                Task { await viewModel.load() }
            }
        case .expired:
            // 005 §2.3 / specs/004 §3.4 — the group ended while this screen was open; a
            // persistent notice the caller must acknowledge, exactly like GroupMapScreen.
            ErrorStateView(message: "This group has ended.", retryTitle: "Back to groups", onRetry: onExit)
        case .loaded(let detail):
            detailView(detail)
        }
    }

    private func detailView(_ detail: GroupDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.md) {
                header(detail)
                if let lastActionError = viewModel.lastActionError {
                    ErrorStateView(message: lastActionError)
                }
                if detail.state == "active" {
                    FindlyButton("Group map") { onSelectMap() }
                }
                if let code = detail.code {
                    shareCodeCard(code: code, name: detail.name)
                }
                rosterOrGraceNotice(detail)
                controls(detail)
            }
            .padding(theme.spacing.md)
        }
        .onAppear { editedName = detail.name }
    }

    private func header(_ detail: GroupDetail) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                Text(detail.name)
                    .font(theme.typography.titleLarge.font)
                    .foregroundColor(theme.colors.onSurface)
                Text("\(detail.memberCount) member\(detail.memberCount == 1 ? "" : "s")")
                    .font(theme.typography.bodyMedium.font)
                    .foregroundColor(theme.colors.onSurface.opacity(0.7))
                Text(GroupCountdown.text(from: detail.endsAt))
                    .font(theme.typography.labelSmall.font)
                    .foregroundColor(theme.colors.onSurface.opacity(0.7))
            }
            Spacer()
            StatusChip(GroupStateChip.label(for: detail.state), kind: GroupStateChip.kind(for: detail.state))
        }
    }

    /// specs/007-public-join-links.md §1/§4, specs/004-ios-client.md §3.5 — the https link is now
    /// the canonical thing shared and encoded as a QR ("the https form is the canonical one for
    /// sharing and QR"); the `findly://` deep link stays supported for INCOMING opens (§4) but is no
    /// longer what this screen hands out. The QR renders entirely on-device (`GroupJoinQRCodeView`
    /// — CoreImage, never a networked service).
    private func shareCodeCard(code: String, name: String) -> some View {
        let joinLink = GroupDetailViewModel.joinLink(for: code, joinLinkHost: joinLinkHost)
        return FindlyCard {
            VStack(spacing: theme.spacing.sm) {
                Text(GroupDetailViewModel.shareText(for: code, groupName: name))
                    .font(theme.typography.titleMedium.font)
                    .foregroundColor(theme.colors.onSurface)
                    .multilineTextAlignment(.center)
                GroupJoinQRCodeView(text: joinLink.absoluteString)
                ShareLink(
                    "Share code",
                    item: GroupDetailViewModel.shareText(for: code, groupName: name, joinLinkHost: joinLinkHost)
                )
            }
        }
    }

    /// 005 §2.3: during `ended` (grace), non-owner members get no roster — only the owner sees it,
    /// to decide on reactivation. `archived` and `active` always carry the full roster.
    @ViewBuilder
    private func rosterOrGraceNotice(_ detail: GroupDetail) -> some View {
        if let members = detail.members {
            VStack(alignment: .leading, spacing: theme.spacing.sm) {
                ForEach(members, id: \.userId) { member in
                    FindlyListRow(title: member.displayName, subtitle: member.role.capitalized) {
                        if viewModel.isOwner && member.role != "owner" {
                            FindlyButton("Kick", style: .secondary) {
                                pendingConfirmation = .kick(userId: member.userId, displayName: member.displayName)
                            }
                        }
                    }
                }
            }
        } else {
            EmptyStateView(title: "This group has ended", message: "The owner can still reactivate it before it's deleted.")
        }
    }

    @ViewBuilder
    private func controls(_ detail: GroupDetail) -> some View {
        if viewModel.isOwner {
            ownerControls(detail)
        } else {
            FindlyButton("Leave group", style: .secondary) {
                Task { await viewModel.leave() }
            }
        }
    }

    /// PATCH-shaped controls (rename/extend/end-now) are hidden once `archived` — the server
    /// rejects PATCH there (`410 GROUP_EXPIRED`, 001 §12.4). Rotate only makes sense while `active`
    /// (the code row is gone otherwise, 005 §2.3). Kick/delete stay available in every state.
    /// Every action here goes through `pendingConfirmation` — none fire on tap alone (003 §12.2,
    /// mirrored by 004 §3.4: "owner controls behind confirm dialogs").
    @ViewBuilder
    private func ownerControls(_ detail: GroupDetail) -> some View {
        VStack(spacing: theme.spacing.sm) {
            if detail.state != "archived" {
                FindlyTextField("Group name", text: $editedName)
                FindlyButton("Rename", style: .secondary) {
                    pendingConfirmation = .rename(newName: editedName)
                }
                DatePicker("New end date", selection: $extendedEndsAt, displayedComponents: [.date, .hourAndMinute])
                    .tint(theme.colors.primary)
                FindlyButton(detail.state == "ended" ? "Reactivate" : "Extend", style: .secondary) {
                    pendingConfirmation = .extend
                }
                FindlyButton("End group now", style: .secondary) {
                    pendingConfirmation = .endNow
                }
            }
            if detail.state == "active" {
                FindlyButton("Rotate code", style: .secondary) {
                    pendingConfirmation = .rotateCode
                }
            }
            FindlyButton("Delete group", style: .secondary) {
                pendingConfirmation = .delete
            }
        }
    }
}

/// specs/003 §12.2 (mirrored by 004 §3.4) — "owner controls behind confirm dialogs: rename,
/// extend/end…, rotate code, kick member, delete group." One case per confirmable owner action;
/// `Identifiable` so `.confirmationDialog(presenting:)` can drive off it directly.
private enum PendingConfirmation: Identifiable, Equatable {
    case rename(newName: String)
    case extend
    case endNow
    case rotateCode
    case kick(userId: String, displayName: String)
    case delete

    var id: String {
        switch self {
        case .rename: return "rename"
        case .extend: return "extend"
        case .endNow: return "endNow"
        case .rotateCode: return "rotateCode"
        case .kick(let userId, _): return "kick-\(userId)"
        case .delete: return "delete"
        }
    }

    var actionTitle: String {
        switch self {
        case .rename: return "Rename"
        case .extend: return "Confirm"
        case .endNow: return "End group"
        case .rotateCode: return "Rotate"
        case .kick: return "Remove"
        case .delete: return "Delete"
        }
    }

    var message: String {
        switch self {
        case .rename(let newName): return "Rename this group to \"\(newName)\"?"
        case .extend: return "Change this group's end date?"
        case .endNow: return "End this group now? Members will lose access immediately."
        case .rotateCode: return "Rotate the join code? The current code will stop working immediately."
        case .kick(_, let displayName): return "Remove \(displayName) from this group?"
        case .delete: return "Delete this group? This can't be undone — everything about it disappears immediately."
        }
    }
}
