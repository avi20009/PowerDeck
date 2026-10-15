import SwiftUI

/// Animated diagram of where power comes from and where it goes. Sources sit on the left, the Mac
/// in the middle, and everything it feeds on the right. Particles run along each link, moving
/// faster and thicker the more watts flow through it.
struct FlowDiagram: View {
    let snapshot: Snapshot

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.staticRender) private var staticRender

    struct Node: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let watts: Double
        let symbol: String
        let color: Color
        var pulse = false
    }

    private var sources: [Node] {
        var nodes: [Node] = []
        if let charger = snapshot.charger {
            nodes.append(Node(id: "charger", title: charger.brand ?? "Charger",
                              subtitle: "\(Int(charger.ratedWatts)) W charger",
                              watts: snapshot.telemetry?.inputWatts ?? 0,
                              symbol: "powerplug.fill", color: Theme.powerIn))
        }
        if let battery = snapshot.battery, battery.isDischarging || snapshot.charger == nil {
            nodes.append(Node(id: "battery-out", title: "Battery", subtitle: "\(battery.percent)% left",
                              watts: snapshot.batteryDrawWatts, symbol: Fmt.batterySymbol(battery.percent), color: Theme.battery))
        }
        if nodes.isEmpty {
            nodes.append(Node(id: "wall", title: "Wall power", subtitle: "", watts: snapshot.macWatts,
                              symbol: "powerplug.fill", color: Theme.powerIn))
        }
        return nodes
    }

    private var sinks: [Node] {
        var nodes: [Node] = []
        if let battery = snapshot.battery, battery.watts > 0.05 {
            nodes.append(Node(id: "battery-in", title: "Battery", subtitle: "\(battery.percent)% · charging",
                              watts: battery.watts, symbol: "battery.100percent.bolt", color: Theme.battery, pulse: true))
        }
        let devices = snapshot.devices
        if !devices.isEmpty || snapshot.accessoryWatts > 0.01 {
            let title = devices.count == 1 ? devices[0].name : devices.isEmpty ? "Device" : "\(devices.count) devices"
            nodes.append(Node(id: "devices", title: title, subtitle: "over USB-C", watts: snapshot.accessoryWatts,
                              symbol: devices.count == 1 ? devices[0].kind.symbol : "cable.connector", color: Theme.accessory))
        }
        if snapshot.charger != nil, let loss = snapshot.telemetry?.conversionLossWatts, loss > 0.05 {
            nodes.append(Node(id: "heat", title: "Heat", subtitle: "conversion loss", watts: loss,
                              symbol: "flame.fill", color: Theme.loss))
        }
        return nodes
    }

    var body: some View {
        let sources = self.sources
        let sinks = self.sinks
        let mac = Node(id: "mac", title: "Your Mac", subtitle: snapshot.mac.modelName,
                       watts: snapshot.macWatts, symbol: "laptopcomputer", color: Theme.mac)
        let animated = !(reduceMotion || staticRender)
        GeometryReader { geo in
            let layout = FlowLayout(size: geo.size, sourceCount: sources.count, sinkCount: sinks.count)
            let links = sources.indices.map { index in
                FlowLink(from: layout.source(index).shifted(x: FlowLayout.nodeRadius),
                         to: layout.mac.shifted(x: -FlowLayout.macRadius),
                         watts: sources[index].watts, fromColor: sources[index].color, toColor: Theme.mac)
            } + sinks.indices.map { index in
                FlowLink(from: layout.mac.shifted(x: FlowLayout.macRadius),
                         to: layout.sink(index).shifted(x: -FlowLayout.nodeRadius),
                         watts: sinks[index].watts, fromColor: Theme.mac, toColor: sinks[index].color)
            }
            ZStack {
                Canvas { context, _ in
                    for link in links {
                        link.drawStroke(in: &context)
                        // Snapshots and Reduce Motion get a still frame of the particles instead.
                        if !animated { link.drawStillParticles(in: &context) }
                    }
                }
                if animated {
                    FlowParticles(links: links)
                        .allowsHitTesting(false)
                }
                ForEach(Array(sources.enumerated()), id: \.element.id) { item in
                    FlowNodeView(node: item.element, labelSide: .leading, size: FlowLayout.nodeRadius * 2)
                        .position(layout.source(item.offset))
                }
                ForEach(Array(sinks.enumerated()), id: \.element.id) { item in
                    FlowNodeView(node: item.element, labelSide: .trailing, size: FlowLayout.nodeRadius * 2)
                        .position(layout.sink(item.offset))
                }
                FlowNodeView(node: mac, labelSide: .bottom, size: FlowLayout.macRadius * 2)
                    .position(layout.mac)
            }
        }
    }
}

private struct FlowLayout {
    static let nodeRadius: CGFloat = 27
    static let macRadius: CGFloat = 42
    static let sideInset: CGFloat = 150

    let size: CGSize
    let sourceCount: Int
    let sinkCount: Int

    var mac: CGPoint { CGPoint(x: size.width / 2, y: size.height / 2 - 16) }

    func source(_ index: Int) -> CGPoint {
        CGPoint(x: Self.sideInset, y: y(index, of: sourceCount))
    }

    func sink(_ index: Int) -> CGPoint {
        CGPoint(x: size.width - Self.sideInset, y: y(index, of: sinkCount))
    }

    private func y(_ index: Int, of count: Int) -> CGFloat {
        size.height * CGFloat(index + 1) / CGFloat(count + 1)
    }
}

/// One curved connection in the flow diagram, plus how its particles should look and move.
struct FlowLink {
    let from: CGPoint
    let to: CGPoint
    let watts: Double
    let fromColor: Color
    let toColor: Color

    var isActive: Bool { watts > 0.02 }
    var strength: Double { min(max(watts, 0), 60) / 60 }
    var particleCount: Int { Int(min(14, 3 + watts / 3)) }
    /// Trips along the link per second.
    var speed: Double { 0.16 + 0.7 * strength }
    var radius: CGFloat { CGFloat(2.2 + 2 * strength) }

    var controls: (CGPoint, CGPoint) {
        let pull = (to.x - from.x) * 0.5
        return (CGPoint(x: from.x + pull, y: from.y), CGPoint(x: to.x - pull, y: to.y))
    }

    /// Changes only when the particles would visibly change, so live wobble doesn't restart them.
    var signature: String {
        "\(Int(from.x)),\(Int(from.y))>\(Int(to.x)),\(Int(to.y)) n\(particleCount) s\(Int(speed * 20))"
    }

    func drawStroke(in context: inout GraphicsContext) {
        let (control1, control2) = controls
        var path = Path()
        path.move(to: from)
        path.addCurve(to: to, control1: control1, control2: control2)
        let opacity = isActive ? 0.32 : 0.12
        let gradient = Gradient(colors: [fromColor.opacity(opacity), toColor.opacity(opacity)])
        context.stroke(path, with: .linearGradient(gradient, startPoint: from, endPoint: to),
                       style: StrokeStyle(lineWidth: isActive ? CGFloat(2 + 8 * strength) : 1.5,
                                          lineCap: .round, dash: isActive ? [] : [4, 5]))
    }

    func drawStillParticles(in context: inout GraphicsContext) {
        guard isActive else { return }
        let (control1, control2) = controls
        let glow = radius * 2.6
        for index in 0..<particleCount {
            let t = (0.35 * speed + Double(index) / Double(particleCount)).truncatingRemainder(dividingBy: 1)
            let point = bezierPoint(CGFloat(t), from, control1, control2, to)
            let fade = sin(t * .pi)
            let color = fromColor.mix(with: toColor, by: t)
            context.fill(Path(ellipseIn: CGRect(x: point.x - glow, y: point.y - glow, width: glow * 2, height: glow * 2)),
                         with: .color(color.opacity(0.2 * fade)))
            context.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                         with: .color(color.opacity(fade)))
        }
    }

    private func bezierPoint(_ t: CGFloat, _ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) -> CGPoint {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return CGPoint(x: a * p0.x + b * p1.x + c * p2.x + d * p3.x,
                       y: a * p0.y + b * p1.y + c * p2.y + d * p3.y)
    }
}

private struct FlowNodeView: View {
    enum LabelSide { case leading, trailing, bottom }

    let node: FlowDiagram.Node
    let labelSide: LabelSide
    let size: CGFloat

    @Environment(\.staticRender) private var staticRender
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch labelSide {
        case .leading:
            circle.overlay(alignment: .leading) {
                label(alignment: .trailing).alignmentGuide(.leading) { $0[.trailing] + 14 }
            }
        case .trailing:
            circle.overlay(alignment: .trailing) {
                label(alignment: .leading).alignmentGuide(.trailing) { $0[.leading] - 14 }
            }
        case .bottom:
            circle.overlay(alignment: .bottom) {
                label(alignment: .center).alignmentGuide(.bottom) { $0[.top] - 10 }
            }
        }
    }

    private var circle: some View {
        ZStack {
            if node.pulse && !staticRender && !reduceMotion {
                PulseRing(color: node.color.opacity(0.5), size: size, scale: 1.7, duration: 2)
            }
            Circle().fill(Theme.card)
            Circle().fill(node.color.opacity(0.14))
            Circle().strokeBorder(node.color.opacity(0.6), lineWidth: 1.5)
            Image(systemName: node.symbol)
                .font(.system(size: size * 0.38, weight: .medium))
                .foregroundStyle(node.color)
        }
        .frame(width: size, height: size)
        // The glow sits in the background so its larger frame can't stretch the circle.
        .background {
            Circle()
                .fill(RadialGradient(colors: [node.color.opacity(0.28), .clear],
                                     center: .center, startRadius: size * 0.35, endRadius: size * 0.8))
                .frame(width: size * 1.6, height: size * 1.6)
        }
    }

    private func label(alignment: HorizontalAlignment) -> some View {
        let textAlignment: TextAlignment = alignment == .trailing ? .trailing : alignment == .leading ? .leading : .center
        let frameAlignment: Alignment = alignment == .trailing ? .trailing : alignment == .leading ? .leading : .center
        return VStack(alignment: alignment, spacing: 2) {
            Text(node.title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Text(Fmt.watts(node.watts))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(node.color)
                .valueFade(node.watts)
            if !node.subtitle.isEmpty {
                Text(node.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
        }
        .multilineTextAlignment(textAlignment)
        .frame(width: labelSide == .bottom ? 220 : 118, alignment: frameAlignment)
    }
}

private extension CGPoint {
    func shifted(x dx: CGFloat) -> CGPoint { CGPoint(x: x + dx, y: y) }
}
