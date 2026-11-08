import SwiftUI

@main
struct LateNightRadioApp: App {
    @StateObject private var m = GameModel()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(m).preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var m: GameModel
    @Environment(\.scenePhase) private var phase
    var body: some View {
        ZStack {
            Backdrop()
            switch m.screen {
            case .title: TitleView()
            case .epCard: EpisodeCard()
            case .live: LiveView()
            case .summary: SummaryView()
            }
            if let t = m.toast {
                VStack { Spacer(); Text(t).font(.system(size: 13)).foregroundStyle(Color.paper).padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Capsule().fill(Color.night.opacity(0.95))).overlay(Capsule().stroke(Color.lineC)).padding(.bottom, 24) }
                    .transition(.opacity).allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: m.screen)
        .sheet(item: $m.sheet) { k in SheetHost(kind: k).environmentObject(m) }
        .task { await m.boot() }
        .onChange(of: phase) { _, p in if p != .active, m.S != nil { m.persist() } }
    }
}
