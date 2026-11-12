import SwiftUI

/// Where each tour target is on screen, gathered from the views marked with `tourTarget(_:)`.
struct TourTargetsKey: PreferenceKey {
    static var defaultValue: [Tour.Target: Anchor<CGRect>] { [:] }

    static func reduce(value: inout [Tour.Target: Anchor<CGRect>], nextValue: () -> [Tour.Target: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Marks this view as what a tour step can point at, keeping the targets inside it (a whole
    /// section holds the Dashboard's totals and the invoice list).
    func tourTarget(_ target: Tour.Target) -> some View {
        transformAnchorPreference(key: TourTargetsKey.self, value: .bounds) { $0[target] = $1 }
    }
}

/// Over the whole window while the tour is on: each step's dotted outline round its target and the
/// Pilot with its balloon beside it. Only the balloon takes clicks, so the section tree under a
/// "Click Quotes" prompt still works.
struct TourOverlay: View {
    let model: AppModel
    let targets: [Tour.Target: Anchor<CGRect>]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let tour = model.tour, !model.isBusy {
            GeometryReader { proxy in
                let shown = tour.shown(in: model.section)
                let rect = targets[shown.target].map { proxy[$0] }
                let pair = Tour.pairCenter(around: rect, placement: shown.placement, in: proxy.size)
                ZStack(alignment: .topLeading) {
                    if let rect, shown.target != .content {
                        TourHighlight()
                            .frame(width: rect.width + 6, height: rect.height + 6)
                            .position(x: rect.midX, y: rect.midY)
                            .allowsHitTesting(false)
                    }
                    // The balloon moves at once, whole; only the Pilot flies to the next target.
                    TourBalloon(tour: tour, text: shown.text, next: tour.nextTitle(in: model.section),
                                tail: pair.pilotLeads ? .leading : .trailing,
                                onNext: { model.tourNext() })
                        .position(x: pair.center.x + (pair.pilotLeads ? 1 : -1) * (Tour.pairWidth - Tour.balloonWidth) / 2,
                                  y: pair.center.y)
                    let pilot = CGPoint(x: pair.center.x + (pair.pilotLeads ? -1 : 1) * (Tour.pairWidth - Tour.pilotSize) / 2,
                                        y: pair.center.y)
                    PilotSprite(size: Tour.pilotSize, mirrored: true)
                        .allowsHitTesting(false)
                        .position(pilot)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: pilot)
                }
            }
        }
    }
}

/// A tour step's words in a pale yellow balloon with a pointer at the Pilot, the step count and Next
/// (Finish on the last step). Clicks only: the screen under it stays live, and Return and Escape
/// belong to whatever is being typed in there.
struct TourBalloon: View {
    let tour: Tour
    let text: String
    let next: String
    let tail: HorizontalEdge
    let onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(Win95.body)
                .foregroundStyle(Win95.text)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text(tour.count)
                    .font(Win95.small)
                    .foregroundStyle(Win95.text)
                Spacer(minLength: 0)
                Button(next, action: onNext)
                    .buttonStyle(Win95ButtonStyle(isDefault: true))
            }
        }
        .padding(12)
        .frame(width: Tour.balloonWidth)
        .background(RoundedRectangle(cornerRadius: 10).fill(Win95.tooltip))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.black, lineWidth: 1))
        .overlay(alignment: tail == .leading ? .leading : .trailing) {
            BalloonTail(pointsLeft: tail == .leading)
                .frame(width: 16, height: 20)
                .offset(x: tail == .leading ? -15 : 15)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tour, step \(tour.count)")
    }
}

/// The balloon's pointer: yellow with a black edge, open on the balloon's side.
private struct BalloonTail: View {
    let pointsLeft: Bool

    var body: some View {
        let shape = TailShape(pointsLeft: pointsLeft)
        shape.fill(Win95.tooltip).overlay(shape.stroke(Color.black, lineWidth: 1))
    }

    struct TailShape: Shape {
        let pointsLeft: Bool

        func path(in r: CGRect) -> Path {
            let tip = CGPoint(x: pointsLeft ? r.minX : r.maxX, y: r.midY)
            let open = pointsLeft ? r.maxX : r.minX
            var path = Path()
            path.move(to: CGPoint(x: open, y: r.minY))
            path.addLine(to: tip)
            path.addLine(to: CGPoint(x: open, y: r.maxY))
            return path
        }
    }
}

/// What a step points at: a Windows 95 dotted outline, thick and doubled with white so it shows on
/// grey, navy and white alike.
struct TourHighlight: View {
    var body: some View {
        ZStack {
            Rectangle().strokeBorder(Color.white, lineWidth: 3)
            Rectangle().strokeBorder(Win95.text, style: StrokeStyle(lineWidth: 3, dash: [5, 3]))
        }
    }
}
