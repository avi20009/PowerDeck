import AppKit
import QuartzCore
import SwiftUI

// Continuous animations live here, in Core Animation layers. Once added, CA animations run in the
// system's render server, so the app does no per-frame work. The same effects built from SwiftUI
// repeating animations, TimelineView or repeating symbol effects redraw the whole window every
// frame and cost 20–30% CPU.

/// A ring that keeps expanding and fading out from behind a dot or badge: a "live" ping.
struct PulseRing: NSViewRepresentable {
    let color: Color
    let size: CGFloat
    var scale: CGFloat = 2.8
    var duration: CFTimeInterval = 1.8

    func makeNSView(context: Context) -> PassThroughLayerView {
        let view = PassThroughLayerView()
        let ring = CALayer()
        ring.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        ring.position = CGPoint(x: size / 2, y: size / 2)
        ring.cornerRadius = size / 2
        ring.backgroundColor = NSColor(color).cgColor

        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 1
        grow.toValue = scale
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.6
        fade.toValue = 0
        let pulse = CAAnimationGroup()
        pulse.animations = [grow, fade]
        pulse.duration = duration
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeOut)
        pulse.isRemovedOnCompletion = false
        ring.add(pulse, forKey: "pulse")
        ring.opacity = 0

        view.layer?.addSublayer(ring)
        return view
    }

    func updateNSView(_ view: PassThroughLayerView, context: Context) {}

    // A fixed size keeps SwiftUI from asking AppKit's Auto Layout for a fitting size on every pass.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PassThroughLayerView, context: Context) -> CGSize? {
        CGSize(width: size, height: size)
    }
}

/// Particles that travel along each power-flow link. Rebuilt only when a link's shape, particle
/// count or speed bucket changes, so small wattage wobbles don't restart the animation.
struct FlowParticles: NSViewRepresentable {
    let links: [FlowLink]

    func makeNSView(context: Context) -> ParticleHostView { ParticleHostView() }

    func updateNSView(_ view: ParticleHostView, context: Context) {
        view.update(links: links)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ParticleHostView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }
}

/// A layer-hosting view that never takes clicks or hovers.
class PassThroughLayerView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class ParticleHostView: PassThroughLayerView {
    private var signature: [String] = []

    func update(links: [FlowLink]) {
        let active = links.filter(\.isActive)
        let signature = active.map(\.signature)
        guard signature != self.signature, let layer else { return }
        self.signature = signature
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        for link in active {
            addParticles(for: link, to: layer)
        }
    }

    private func addParticles(for link: FlowLink, to layer: CALayer) {
        let (control1, control2) = link.controls
        let path = CGMutablePath()
        path.move(to: link.from)
        path.addCurve(to: link.to, control1: control1, control2: control2)

        let from = NSColor(link.fromColor).cgColor
        let to = NSColor(link.toColor).cgColor
        let glow = NSColor(link.fromColor.mix(with: link.toColor, by: 0.5)).cgColor
        let radius = link.radius
        let duration = 1 / link.speed
        let count = link.particleCount

        for index in 0..<count {
            let dot = CALayer()
            dot.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
            dot.cornerRadius = radius
            dot.backgroundColor = from
            dot.shadowColor = glow
            dot.shadowOpacity = 0.9
            dot.shadowRadius = radius * 1.6
            dot.shadowOffset = .zero
            dot.shadowPath = CGPath(ellipseIn: dot.bounds, transform: nil)
            dot.opacity = 0

            let move = CAKeyframeAnimation(keyPath: "position")
            move.path = path
            move.calculationMode = .paced
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]
            fade.keyTimes = [0, 0.18, 0.82, 1]
            let tint = CABasicAnimation(keyPath: "backgroundColor")
            tint.fromValue = from
            tint.toValue = to

            let travel = CAAnimationGroup()
            travel.animations = [move, fade, tint]
            travel.duration = duration
            travel.repeatCount = .infinity
            travel.timeOffset = duration * Double(index) / Double(count)
            travel.isRemovedOnCompletion = false
            dot.add(travel, forKey: "travel")
            layer.addSublayer(dot)
        }
    }
}
