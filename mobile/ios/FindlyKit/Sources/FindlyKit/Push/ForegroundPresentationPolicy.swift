import Foundation

/// specs/011 §4.4, specs/009 §5.6 — whether a notification that arrives while the app is in the
/// FOREGROUND is shown. `STALE_NUDGE` is suppressed (the app being open means it is not stale);
/// every other type keeps the §5.1 behaviour of `[.banner, .sound]`. The `AppDelegate`'s
/// `willPresent` maps this onto `UNNotificationPresentationOptions`; the decision lives here so it
/// is testable without UserNotifications.
public enum ForegroundPresentationPolicy {
    public enum Decision: Equatable {
        case bannerAndSound
        case suppress
    }

    public static func decision(for data: [String: String]) -> Decision {
        switch PushMessageType.from(data) {
        case .staleNudge: return .suppress
        case .locateRequest, .settingsChanged, .geofenceEvent, .geofenceConfigChanged, .unrecognized:
            return .bannerAndSound
        }
    }
}
