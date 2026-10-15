import Charts
import SwiftUI

// MARK: - Motion

extension View {
    /// Cross-fades a headline number when it changes. A cross-fade costs about 1% CPU; the rolling
    /// `.numericText()` transition blurs every digit on the CPU and cost about 10% at a 2 s refresh.
    func valueFade<V: Equatable>(_ value: V) -> some View {
        contentTransition(.opacity).animation(.easeOut(duration: 0.25), value: value)
    }

    /// Fades and slides the view in when it first appears; `index` staggers siblings.
    func appear(_ index: Int) -> some View {
        modifier(AppearEffect(delay: Double(index) * 0.06))
    }

    @ViewBuilder func optionalHelp(_ text: String?) -> some View {
        if let text { help(text) } else { self }
    }
}

struct AppearEffect: ViewModifier {
    let delay: Double
    @State private var shown = false
    @Environment(\.staticRender) private var staticRender
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let visible = shown || staticRender
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 18)
            .onAppear {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.86).delay(delay)) { shown = true }
            }
    }
}

/// A status dot with a Core Animation ping around it (see CoreAnimationViews.swift for why).
struct LiveDot: View {
    var color: Color = Theme.powerIn
    @Environment(\.staticRender) private var staticRender
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if !staticRender && !reduceMotion {
                PulseRing(color: color, size: 7)
            }
            Circle().fill(color)
        }
        .frame(width: 7, height: 7)
    }
}

// MARK: - Cards

/// Card surface with a hover highlight. Deliberately no drop shadow: SwiftUI blurs shadows on the CPU,
/// and cards redraw every refresh, which made a shadow cost ~20% CPU.
struct CardStyle: ViewModifier {
    var padding: CGFloat = 18
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(hovering ? Theme.cardHover : Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(hovering ? Color.white.opacity(0.16) : Theme.border, lineWidth: 1)
            )
            .onHover { inside in
                withAnimation(.easeOut(duration: 0.18)) { hovering = inside }
            }
    }
}

extension View {
    func cardStyle(padding: CGFloat = 18) -> some View {
        modifier(CardStyle(padding: padding))
    }
}

struct Card<Trailing: View, Content: View>: View {
    let title: String
    let symbol: String
    let helpText: String?
    let trailing: Trailing
    let content: Content

    init(_ title: String, symbol: String, help: String? = nil,
         @ViewBuilder trailing: () -> Trailing,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.helpText = help
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.9)
                    .foregroundStyle(Theme.textSecondary)
                if let helpText {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .help(helpText)
                }
                Spacer(minLength: 8)
                trailing
            }
            content
        }
        .cardStyle()
    }
}

extension Card where Trailing == EmptyView {
    init(_ title: String, symbol: String, help: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title, symbol: symbol, help: help, trailing: { EmptyView() }, content: content)
    }
}

struct SectionHeader: View {
    let title: String
    let symbol: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(Theme.textSecondary)
            Text(title).font(.system(size: 16, weight: .semibold))
            Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            Spacer()
        }
        .padding(.top, 4)
    }
}

// MARK: - Small pieces

struct SmallLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.9)
            .foregroundStyle(Theme.textTertiary)
    }
}

struct Pill: View {
    let text: String
    let color: Color
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 10, weight: .bold))
            }
            Text(text).lineLimit(1)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(color.opacity(0.14), in: Capsule())
        .animation(.smooth, value: text)
    }
}

struct MeterBar: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.07))
                Capsule()
                    .fill(color.gradient)
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: height)
        .animation(.smooth(duration: 0.35), value: fraction)
    }
}

struct Sparkline: View {
    let values: [Double]
    let color: Color
    var ceiling: Double? = nil

    var body: some View {
        let clamped = values.map { max($0, 0) }
        let top = ceiling ?? max(clamped.max() ?? 0, 0.5) * 1.2
        Chart {
            ForEach(Array(clamped.enumerated()), id: \.offset) { item in
                AreaMark(x: .value("t", item.offset), y: .value("v", item.element))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.32), color.opacity(0)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("t", item.offset), y: .value("v", item.element))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartYScale(domain: 0...top)
        .chartXScale(domain: 0...max(clamped.count - 1, 1))
    }
}

struct StatTile: View {
    let title: String
    let symbol: String
    let value: String
    let unit: String
    let detail: String
    let color: Color
    var spark: [Double]? = nil
    var sparkCeiling: Double? = nil
    var progress: Double? = nil
    var help: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.9)
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .valueFade(value)
                Text(unit)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Group {
                if let spark {
                    Sparkline(values: spark, color: color, ceiling: sparkCeiling)
                } else if let progress {
                    MeterBar(fraction: progress, color: color, height: 8)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(height: 32)
        }
        .cardStyle(padding: 16)
        .optionalHelp(help)
    }
}

struct BigReadout: View {
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .valueFade(value)
            Text(unit)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

struct MetricBox: View {
    let label: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SmallLabel(label)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct KeyValueRow: View {
    let key: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text(key).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 12.5, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}

struct IconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 48

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
    }
}

struct RingGauge: View {
    let fraction: Double
    let color: Color
    let value: String
    let caption: String
    var size: CGFloat = 112
    var lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.07), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.45), radius: 6)
                .animation(.smooth(duration: 0.4), value: fraction)
            VStack(spacing: 1) {
                Text(value)
                    .font(.system(size: size * 0.21, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .valueFade(value)
                Text(caption)
                    .font(.system(size: max(10, size * 0.09), weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(width: size, height: size)
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(Theme.textTertiary)
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}

struct InsightRow: View {
    let insight: Insight
    var compact = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: insight.severity.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(insight.severity.color)
                .frame(width: 28, height: 28)
                .background(insight.severity.color.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(insight.title).font(.system(size: 13, weight: .semibold))
                Text(insight.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(2)
                    .lineLimit(compact ? 3 : nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 10)
    }
}

/// A row that highlights on hover and runs `action` when clicked.
struct HoverRow<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            content
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(hovering ? Theme.raised : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.15)) { hovering = inside }
        }
    }
}

struct BackgroundGlow: View {
    var body: some View {
        ZStack {
            Theme.background
            RadialGradient(colors: [Theme.powerIn.opacity(0.08), .clear], center: .topLeading, startRadius: 0, endRadius: 700)
            RadialGradient(colors: [Theme.mac.opacity(0.06), .clear], center: .topTrailing, startRadius: 0, endRadius: 650)
        }
        .ignoresSafeArea()
    }
}
