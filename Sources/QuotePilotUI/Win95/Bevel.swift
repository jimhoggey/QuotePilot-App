import SwiftUI

public enum BevelKind {
    case raised, sunken, pressed, etched
}

/// The two-line Windows 95 bevel: an outer and an inner frame, each lit from the top left.
public struct Bevel: View {
    public var kind: BevelKind

    public init(_ kind: BevelKind) {
        self.kind = kind
    }

    public var body: some View {
        Canvas { context, size in
            let colors: (outerTL: Color, outerBR: Color, innerTL: Color, innerBR: Color)
            switch kind {
            case .raised: colors = (Win95.highlight, Win95.dark, Win95.light, Win95.shadow)
            case .sunken: colors = (Win95.shadow, Win95.highlight, Win95.dark, Win95.light)
            case .pressed: colors = (Win95.dark, Win95.highlight, Win95.shadow, Win95.light)
            case .etched: colors = (Win95.shadow, Win95.highlight, Win95.highlight, Win95.shadow)
            }
            func frame(inset: CGFloat, topLeft: Color, bottomRight: Color) {
                let w = size.width - inset * 2, h = size.height - inset * 2
                guard w > 2, h > 2 else { return }
                context.fill(Path(CGRect(x: inset, y: inset, width: w - 1, height: 1)), with: .color(topLeft))
                context.fill(Path(CGRect(x: inset, y: inset, width: 1, height: h - 1)), with: .color(topLeft))
                context.fill(Path(CGRect(x: inset, y: inset + h - 1, width: w, height: 1)), with: .color(bottomRight))
                context.fill(Path(CGRect(x: inset + w - 1, y: inset, width: 1, height: h)), with: .color(bottomRight))
            }
            frame(inset: 0, topLeft: colors.outerTL, bottomRight: colors.outerBR)
            frame(inset: 1, topLeft: colors.innerTL, bottomRight: colors.innerBR)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

public extension View {
    /// A raised grey panel: bars, buttons, the window body.
    func win95Raised(padding: CGFloat = 2) -> some View {
        self.padding(padding).background(Win95.face).overlay(Bevel(.raised))
    }

    /// A sunken well: fields, lists, readouts.
    func win95Sunken(fill: Color = Win95.field, padding: CGFloat = 2) -> some View {
        self.padding(padding).background(fill).overlay(Bevel(.sunken))
    }
}

/// The dotted rectangle Windows 95 draws around the focused control.
public struct FocusRect: View {
    public init() {}

    public var body: some View {
        // Dots are whole 1 pt squares on every other point. A dashed stroke straddles pixels on a
        // 1x display and blurs into a solid grey line.
        Canvas { context, size in
            var dots = Path()
            var x: CGFloat = 0
            while x < size.width {
                dots.addRect(CGRect(x: x, y: 0, width: 1, height: 1))
                dots.addRect(CGRect(x: x, y: size.height - 1, width: 1, height: 1))
                x += 2
            }
            var y: CGFloat = 2
            while y < size.height - 1 {
                dots.addRect(CGRect(x: 0, y: y, width: 1, height: 1))
                dots.addRect(CGRect(x: size.width - 1, y: y, width: 1, height: 1))
                y += 2
            }
            context.fill(dots, with: .color(Win95.dark))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
