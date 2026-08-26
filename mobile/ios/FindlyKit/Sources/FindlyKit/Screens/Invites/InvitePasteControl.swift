import SwiftUI
#if os(iOS)
import UIKit
import UniformTypeIdentifiers
#endif

#if os(iOS)
/// specs/010-app-shell-and-screen-ux.md §5.2 — the accept-invite screen's explicit-tap-only paste
/// affordance ("iOS: `UIPasteControl`-class"). Wraps the REAL system `UIPasteControl` rather than a
/// plain button that peeks at the pasteboard: `UIPasteControl` is Apple's own answer to "offer
/// paste without an ambient clipboard-content check" — it shows/hides itself based on whether the
/// pasteboard currently holds a compatible item WITHOUT that check itself counting as an
/// app-initiated read (no user-facing "Findly pasted from…" notification, unlike a direct
/// `UIPasteboard.general.string` read). The pasteboard is genuinely read ONLY inside
/// `Coordinator.paste(itemProviders:)`, which fires ONLY on the user's explicit tap — never on
/// screen appearance, never ambiently (010 §5.2: "the clipboard is read only on the user's tap on
/// that control").
///
/// A `UIKit`-bridging system-primitive exception to the "compose only design-system components"
/// rule, the same documented pattern `GroupDetailScreen` already uses for `ShareLink`/`DatePicker`/
/// `.confirmationDialog` — `UIPasteControl` renders its own system chrome, not app-themed.
///
/// `UIPasteControl` doesn't exist on macOS (the platform this package ALSO builds/tests for, per
/// `Package.swift`) — guarded with `#if os(iOS)` so `swift build`/`swift test` still compile clean
/// on a plain macOS/CLT host; `AcceptInviteScreen` only renders this control under the same guard.
public struct InvitePasteControl: UIViewRepresentable {
    private let onPaste: (String) -> Void

    public init(onPaste: @escaping (String) -> Void) {
        self.onPaste = onPaste
    }

    public func makeUIView(context: Context) -> UIPasteControl {
        var configuration = UIPasteControl.Configuration()
        configuration.displayMode = .labelOnly
        configuration.cornerStyle = .capsule
        let control = UIPasteControl(configuration: configuration)
        control.target = context.coordinator
        control.pasteConfiguration = UIPasteConfiguration(acceptableTypeIdentifiers: [UTType.text.identifier])
        return control
    }

    public func updateUIView(_ uiView: UIPasteControl, context: Context) {}

    public func makeCoordinator() -> Coordinator {
        Coordinator(onPaste: onPaste)
    }

    /// `UIPasteControl.target` must be a `UIResponder` implementing
    /// `UIResponderStandardEditActions.paste(itemProviders:)` — that override is the ONLY place in
    /// this type that ever touches pasteboard contents, and it runs only when the system control
    /// itself is tapped. `UIResponder` already conforms to `UIPasteConfigurationSupporting` (its
    /// `pasteConfiguration` is already a stored property there) — redeclaring the conformance/
    /// property here is a compile error ("cannot override with a stored property"), so this type
    /// only ever ASSIGNS the inherited property, never redeclares it.
    public final class Coordinator: UIResponder {
        private let onPaste: (String) -> Void

        init(onPaste: @escaping (String) -> Void) {
            self.onPaste = onPaste
            super.init()
            self.pasteConfiguration = UIPasteConfiguration(acceptableTypeIdentifiers: [UTType.text.identifier])
        }

        public override var canBecomeFirstResponder: Bool { true }

        public override func paste(itemProviders: [NSItemProvider]) {
            for provider in itemProviders where provider.canLoadObject(ofClass: NSString.self) {
                provider.loadObject(ofClass: NSString.self) { [onPaste] reading, _ in
                    guard let pasted = reading as? String else { return }
                    DispatchQueue.main.async { onPaste(pasted) }
                }
            }
        }
    }
}
#endif
