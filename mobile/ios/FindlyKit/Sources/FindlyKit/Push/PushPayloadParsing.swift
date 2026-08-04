import Foundation

/// I15 round-2 code review — the raw `[AnyHashable: Any]` a push notification arrives as (both
/// `UIApplicationDelegate.application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`'s
/// `userInfo` and `UNNotificationRequest.content.userInfo` in the `FindlyNotificationService`
/// extension target) needs converting into the `[String: String]` shape every push type in this
/// file already parses (specs/001-api-contract.md §8: "all `data` values are strings"). Both call
/// sites needed the identical few lines; sharing one implementation here — rather than each
/// keeping its own copy — is what makes `NotificationService` (the extension's own thin subclass)
/// and `AppDelegate` (app target) both genuinely logic-free rather than nominally so.
public enum PushPayloadParsing {
    public static func stringData(from userInfo: [AnyHashable: Any]) -> [String: String] {
        var data: [String: String] = [:]
        for (key, value) in userInfo {
            guard let key = key as? String else { continue }
            data[key] = "\(value)"
        }
        return data
    }
}
