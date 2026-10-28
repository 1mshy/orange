import SwiftUI

/// Radial "fan" of petals around a center label, like Tangerine's wheel.
struct WheelView: View {
    @ObservedObject var model: WheelModel
    @ObservedObject var settings = AppSettings.shared
    let outerRadius: CGFloat
    let innerRadius: CGFloat

    private var gapRadians: CGFloat { 0.035 }

    var body: some View {
        ZStack {
            // Backdrop disk
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: outerRadius * 2 + 12, height: outerRadius * 2 + 12)
                .shadow(color: .black.opacity(0.25), radius: 18, y: 6)

            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                petal(index: index, item: item)
            }

            centerLabel
        }
        .frame(width: outerRadius * 2 + 40, height: outerRadius * 2 + 40)
        .overlay(alignment: .bottom) { modeChips.offset(y: 12) }
        .animation(.easeOut(duration: 0.12), value: model.selectedIndex)
        .animation(.easeOut(duration: 0.18), value: model.mode)
    }

    private func petal(index: Int, item: WheelItem) -> some View {
        let count = max(model.items.count, 1)
        let slice = 2 * CGFloat.pi / CGFloat(count)
        let start = CGFloat(index) * slice - slice / 2 + gapRadians
        let end = start + slice - 2 * gapRadians
        let mid = (start + end) / 2
        let selected = model.selectedIndex == index
        let labelRadius = (innerRadius + outerRadius) / 2 + 2
        return ZStack {
            PetalShape(startAngle: start, endAngle: end, innerRadius: innerRadius, outerRadius: outerRadius)
                .fill(selected ? Color.accentColor : Color(nsColor: .controlBackgroundColor).opacity(0.92))
                .overlay(PetalShape(startAngle: start, endAngle: end, innerRadius: innerRadius, outerRadius: outerRadius)
                    .stroke(Color.primary.opacity(selected ? 0 : 0.08), lineWidth: 1))
                .scaleEffect(selected ? 1.04 : 1)
            VStack(spacing: 2) {
                Image(systemName: item.symbol).font(.system(size: count > 9 ? 11 : 14, weight: .semibold))
                Text(item.title)
                    .font(.system(size: count > 9 ? 9 : 11, weight: .bold, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .foregroundStyle(selected ? Color.white : Color.primary)
            .frame(width: max(44, (outerRadius - innerRadius) * 0.95))
            .offset(x: sin(mid) * labelRadius, y: -cos(mid) * labelRadius)
        }
    }

    private var centerLabel: some View {
        VStack(spacing: 3) {
            if let selected = model.selectedItem {
                Text(selected.caption).font(.system(size: 12, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
            } else if let message = model.emptyMessage {
                Text(message).font(.system(size: 10, weight: .semibold)).multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            } else {
                Text(model.mode.title).font(.system(size: 11, weight: .bold, design: .rounded))
                Text(model.categoryTitle).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(width: innerRadius * 2 - 10, height: innerRadius * 2 - 10)
        .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(Circle().stroke(Color.primary.opacity(0.1)))
    }

    private var modeChips: some View {
        HStack(spacing: 6) {
            ForEach(WheelMode.allCases, id: \.self) { mode in
                let active = mode == model.mode
                HStack(spacing: 3) {
                    Text(settings.modifier(for: mode).symbol).font(.system(size: 10, weight: .bold))
                    Text(mode.title.components(separatedBy: " ").last ?? "").font(.system(size: 9, weight: .semibold))
                }
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(active ? Color.accentColor : Color(nsColor: .controlBackgroundColor).opacity(0.9)))
                .foregroundStyle(active ? Color.white : Color.secondary)
            }
        }
    }
}

struct PetalShape: Shape {
    let startAngle: CGFloat   // radians, clockwise from top
    let endAngle: CGFloat
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        func point(_ angle: CGFloat, _ radius: CGFloat) -> CGPoint {
            CGPoint(x: center.x + sin(angle) * radius, y: center.y - cos(angle) * radius)
        }
        // Convert to SwiftUI angles (0 = right, clockwise in flipped coords).
        let s = Angle(radians: Double(startAngle) - .pi / 2)
        let e = Angle(radians: Double(endAngle) - .pi / 2)
        var path = Path()
        path.move(to: point(startAngle, innerRadius))
        path.addLine(to: point(startAngle, outerRadius))
        path.addArc(center: center, radius: outerRadius, startAngle: s, endAngle: e, clockwise: false)
        path.addLine(to: point(endAngle, innerRadius))
        path.addArc(center: center, radius: innerRadius, startAngle: e, endAngle: s, clockwise: true)
        path.closeSubpath()
        return path
    }
}
