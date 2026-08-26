import SwiftUI
import Foundation

/// specs/004-ios-client.md I2 (001 §5.3) — composes ONLY design-system components. Date-range
/// selection uses the system `DatePicker` (tinted via `theme.colors.primary`, never a literal
/// color) as a documented system-primitive exception, exactly like the live map screen's
/// first-party MapKit; pagination is a plain "Load more" `FindlyButton` driven by the view model's
/// cursor state.
public struct HistoryScreen: View {
    @Environment(\.theme) private var theme
    // `@StateObject`, NOT `@ObservedObject` — see `HomeScreen`'s doc for the full failure mode
    // (I16). `RootView` constructs this screen's view model inline and re-evaluates on every
    // in-app navigation; `@StateObject` + `@autoclosure` keeps the first instance for this view's
    // lifetime instead of silently discarding the one `.task` observes.
    @StateObject private var viewModel: HistoryViewModel
    /// specs/010-app-shell-and-screen-ux.md §2.1 (I34) — fires once `viewModel.state` reaches
    /// `.routeToOnboarding`.
    private let onProfileDeadEnd: (OnboardingVariant) -> Void

    public init(
        viewModel: @autoclosure @escaping () -> HistoryViewModel,
        onProfileDeadEnd: @escaping (OnboardingVariant) -> Void = { _ in }
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.onProfileDeadEnd = onProfileDeadEnd
    }

    public var body: some View {
        VStack(spacing: 0) {
            FindlyNavBar("History")
            dateRangeControls
            content
        }
        .background(theme.colors.surfaceVariant)
        .task { await viewModel.load() }
        .onChange(of: routingVariant) { variant in
            if let variant { onProfileDeadEnd(variant) }
        }
    }

    private var routingVariant: OnboardingVariant? {
        if case .routeToOnboarding(let variant) = viewModel.state { return variant }
        return nil
    }

    /// specs/001 §5.3 — `from`/`to` date-range selection. Changing either date reloads (resetting
    /// pagination, `HistoryViewModel.load()`'s job) and re-validates the 31-day max span.
    private var dateRangeControls: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            DatePicker("From", selection: fromDateBinding, displayedComponents: .date)
                .tint(theme.colors.primary)
            DatePicker("To", selection: toDateBinding, displayedComponents: .date)
                .tint(theme.colors.primary)
        }
        .padding(theme.spacing.md)
        .background(theme.colors.surface)
    }

    private var fromDateBinding: Binding<Date> {
        Binding(
            get: { Self.parse(viewModel.fromDate) },
            set: { newValue in
                viewModel.fromDate = Self.format(newValue)
                Task { await viewModel.load() }
            }
        )
    }

    private var toDateBinding: Binding<Date> {
        Binding(
            get: { Self.parse(viewModel.toDate) },
            set: { newValue in
                viewModel.toDate = Self.format(newValue)
                Task { await viewModel.load() }
            }
        )
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.calendar = Calendar(identifier: .gregorian)
        return formatter
    }()

    private static func parse(_ value: String) -> Date {
        dateFormatter.date(from: value) ?? Date()
    }

    private static func format(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading, .routeToOnboarding:
            LoadingStateView(message: "Loading history…")
        case .error(let message):
            ErrorStateView(message: message) {
                Task { await viewModel.load() }
            }
        case .loaded(let points, let hasMore):
            list(points: points, hasMore: hasMore)
        }
    }

    private func list(points: [HistoryPoint], hasMore: Bool) -> some View {
        ScrollView {
            VStack(spacing: theme.spacing.sm) {
                if points.isEmpty {
                    EmptyStateView(title: "No history", message: "No locations recorded in this date range.")
                } else {
                    ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                        FindlyListRow(title: "\(point.lat), \(point.lon)", subtitle: point.recordedAt) {
                            StatusChip(point.source.rawValue.capitalized, kind: .online)
                        }
                    }
                    if hasMore {
                        FindlyButton(viewModel.isLoadingMore ? "Loading…" : "Load more", style: .secondary) {
                            Task { await viewModel.loadMore() }
                        }
                        .disabled(viewModel.isLoadingMore)
                    }
                }
            }
            .padding(theme.spacing.md)
        }
    }
}
