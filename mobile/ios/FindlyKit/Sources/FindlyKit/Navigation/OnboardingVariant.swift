/// specs/010-app-shell-and-screen-ux.md §2.2 — the Onboarding screen's two variants. A
/// `PROFILE_NOT_FOUND` (no `Users` profile row at all, 001 §1.5.3) is materially different from a
/// `FAMILY_NOT_FOUND` (a profile exists but `familyId` is null — a groups-only user, 001 §1.5.4):
/// the profile-less caller cannot even call `GET /groups`, so only the four bootstrap paths make
/// sense for them, while the family-less caller already has a working Groups feature. Carried as
/// the `AppRoute.onboarding` associated value so the router — not the screen — is the single source
/// of truth for which variant is showing.
public enum OnboardingVariant: Equatable, Sendable {
    case profileLess
    case familyLess
}
