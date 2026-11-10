import SwiftUI

/// The padlock beside the Quote Pilot fee's settings, so whoever sets Quote Pilot up decides the fee.
/// With no password it's open and pressing it chooses one; locked, pressing it asks for the password;
/// unlocked, pressing it locks again, and Remove Password shows beside it.
struct FeeLockButton: View {
    let model: AppModel

    var body: some View {
        let hasPassword = model.library.brand.appFee.lock != nil
        let locked = model.feeSettingsLocked
        HStack(spacing: 6) {
            if hasPassword, !locked {
                Button("Remove Password") { model.removeFeePassword() }
                    .buttonStyle(.win95Small)
                    .help("Take the password off, so anyone can change the fee. Press the lock to choose a new one.")
            }
            Button {
                if !hasPassword {
                    model.dialog = .feePassword(.choose)
                } else if locked {
                    model.dialog = .feePassword(.unlock)
                } else {
                    model.feeSettingsUnlocked = false
                }
            } label: {
                PixelIconView(locked ? .lock : .unlocked)
            }
            .buttonStyle(SquareButtonStyle())
            .help(Self.help(hasPassword: hasPassword, locked: locked))
            .accessibilityLabel(Self.help(hasPassword: hasPassword, locked: locked))
        }
    }

    static func help(hasPassword: Bool, locked: Bool) -> String {
        if !hasPassword { return "Lock the fee's settings with a password, so only you can change them" }
        return locked ? "Locked. Press and type the password to change the fee's settings"
                      : "Unlocked. Press to lock the fee's settings again"
    }
}
