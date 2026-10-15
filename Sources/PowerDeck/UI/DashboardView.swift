import SwiftUI

enum DashboardTab: String, CaseIterable, Identifiable {
    case overview, devices, power, system

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .devices: "Devices"
        case .power: "Power"
        case .system: "System"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2.fill"
        case .devices: "cable.connector"
        case .power: "bolt.fill"
        case .system: "cpu"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .overview: "1"
        case .devices: "2"
        case .power: "3"
        case .system: "4"
        }
    }
}

struct DashboardView: View {
    let monitor: Monitor
    @SceneStorage("dashboardTab") private var tab: DashboardTab = .overview

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 0).id("top")
                    DashboardContent(monitor: monitor, tab: $tab)
                        .padding(.horizontal, 28)
                        .padding(.top, 6)
                        .padding(.bottom, 28)
                }
            }
            .onChange(of: tab) {
                proxy.scrollTo("top", anchor: .top)
            }
        }
        .overlay(alignment: .topTrailing) {
            ToastStack(toasts: monitor.toasts, dismiss: monitor.dismissToast)
                .padding(.top, 74)
                .padding(.trailing, 28)
        }
    }
}

/// The header and the selected tab, without the scroll view so it can also be rendered to an image.
struct DashboardContent: View {
    let monitor: Monitor
    @Binding var tab: DashboardTab

    var body: some View {
        Group {
            if let snapshot = monitor.snapshot {
                VStack(alignment: .leading, spacing: 20) {
                    HeaderView(snapshot: snapshot, tab: $tab)
                    Group {
                        switch tab {
                        case .overview:
                            OverviewTab(monitor: monitor, snapshot: snapshot) { target in
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { tab = target }
                            }
                        case .devices:
                            DevicesTab(monitor: monitor, snapshot: snapshot)
                        case .power:
                            PowerTab(monitor: monitor, snapshot: snapshot)
                        case .system:
                            SystemTab(monitor: monitor, snapshot: snapshot)
                        }
                    }
                    .id(tab)
                    .transition(.opacity)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 400)
            }
        }
        .foregroundStyle(Theme.textPrimary)
    }
}

struct HeaderView: View {
    let snapshot: Snapshot
    @Binding var tab: DashboardTab

    var body: some View {
        let status = PowerStatus.describe(snapshot)
        HStack(alignment: .center, spacing: 14) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(LinearGradient(colors: [Theme.powerIn, Theme.tip], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.75))
                )
                .shadow(color: Theme.powerIn.opacity(0.35), radius: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text("PowerDeck").font(.system(size: 20, weight: .bold))
                Text(snapshot.mac.modelName)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 16)
            TabBar(selection: $tab, badges: [.devices: snapshot.devices.count])
            Spacer(minLength: 16)
            Pill(text: status.text, color: status.color, symbol: status.symbol)
            HStack(spacing: 7) {
                LiveDot()
                Text("LIVE")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Theme.powerIn)
                Text(snapshot.date.formatted(date: .omitted, time: .standard))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.card, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.border))
            SettingsLink {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(Theme.card, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.border))
            }
            .buttonStyle(.plain)
            .help("Settings (⌘,)")
        }
    }
}

struct TabBar: View {
    @Binding var selection: DashboardTab
    let badges: [DashboardTab: Int]
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(DashboardTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { selection = tab }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.symbol).font(.system(size: 11, weight: .semibold))
                        Text(tab.title).font(.system(size: 12.5, weight: .semibold))
                        if let count = badges[tab], count > 0 {
                            Text("\(count)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.accessory)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Theme.accessory.opacity(0.2), in: Capsule())
                        }
                    }
                    .foregroundStyle(selection == tab ? Theme.textPrimary : Theme.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background {
                        if selection == tab {
                            Capsule()
                                .fill(Theme.raised)
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.1)))
                                .matchedGeometryEffect(id: "selectedTab", in: namespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(tab.shortcut, modifiers: .command)
                .help("\(tab.title) (⌘\(String(tab.shortcut.character)))")
            }
        }
        .padding(4)
        .background(Theme.card, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.border))
    }
}

struct ToastStack: View {
    let toasts: [ActivityEvent]
    let dismiss: (UUID) -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            ForEach(toasts) { event in
                ToastView(event: event) { dismiss(event.id) }
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .opacity.combined(with: .scale(scale: 0.95))))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: toasts.map(\.id))
    }
}

struct ToastView: View {
    let event: ActivityEvent
    let close: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(symbol: event.symbol, color: event.kind.color, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title).font(.system(size: 13, weight: .semibold))
                Text(event.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 350)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(event.kind.color.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
        .foregroundStyle(Theme.textPrimary)
    }
}
