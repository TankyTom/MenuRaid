import SwiftUI
import AppKit

extension AppearanceMode {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// Sets the appearance of the window hosting a view. `preferredColorScheme` alone doesn't restyle the
/// menu bar panel's translucent background, so the window itself is switched too.
struct WindowAppearance: NSViewRepresentable {
    let appearance: NSAppearance?

    final class HookView: NSView {
        var appearance_: NSAppearance?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.appearance = appearance_
        }
    }

    func makeNSView(context: Context) -> HookView {
        let view = HookView()
        view.appearance_ = appearance
        return view
    }

    func updateNSView(_ view: HookView, context: Context) {
        view.appearance_ = appearance
        view.window?.appearance = appearance
    }
}
