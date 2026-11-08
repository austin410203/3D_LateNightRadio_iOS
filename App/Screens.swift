import SwiftUI
import LNRCore

// 標題（圖文版：主視覺＋一句話＋三格圖解＋一顆主按鈕＋一排圖示鍵）、集數卡、結算

struct TitleView: View {
    @EnvironmentObject var m: GameModel
    @State private var sureNew = false
    var body: some View {
        ScrollView {
            Card {
                HStack(spacing: 14) {
                    ZStack(alignment: .bottom) {
                        Portrait(name: "dj", size: 100, radius: 20)
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.amber.opacity(0.4), lineWidth: 2))
                        Text("ON AIR").font(.system(size: 10.5, weight: .bold, design: .monospaced)).tracking(2)
                            .padding(.horizontal, 8).padding(.vertical, 3).background(RoundedRectangle(cornerRadius: 6).fill(Color.onair))
                            .foregroundStyle(.white).offset(y: 9).shadow(color: .onair.opacity(0.7), radius: 8)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(m.t("gameName")).font(.system(size: 32, weight: .black, design: .serif)).foregroundStyle(Color.paper).minimumScaleFactor(0.6).lineLimit(1)
                        Text("LATE NIGHT RADIO").font(.system(size: 11, design: .monospaced)).tracking(3).foregroundStyle(Color.onair)
                        Text(m.t("tagline")).font(.system(size: 13.5)).foregroundStyle(Color.paper.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(spacing: 6) {
                    step("phone.fill", .amber, m.t("st1"), m.t("st1s"))
                    step("mic.fill", .onair, m.t("st2"), m.t("st2s"))
                    step("envelope.fill", .vu, m.t("st3"), m.t("st3s"))
                }.padding(.top, 6)
                ThemePicker { Task { await m.start() } }
                Button { Task { await m.start() } } label: {
                    Label(m.savedShow.map { m.t("continueN", ["n": "\($0.ended ? $0.ep + 1 : $0.ep)"]) } ?? m.t("start"), systemImage: "mic.fill")
                }.buttonStyle(PrimaryButton()).accessibilityIdentifier("start")
                if m.savedShow != nil {
                    Button(sureNew ? m.t("newShowSure") : m.t("newShow")) {
                        if !sureNew { sureNew = true; return }
                        sureNew = false; Task { await m.startNewShow() }
                    }.buttonStyle(SoftButton(big: true))
                }
                HStack(spacing: 8) {
                    ToolButton(icon: "text.bubble.fill", label: m.t("history")) { m.sheet = .history }
                    ToolButton(icon: "square.and.arrow.down.fill", label: m.t("slotN", ["n": "\(m.saves.active)"])) { m.sheet = .settings }
                    ToolButton(icon: "gearshape.fill", label: m.t("settings")) { m.sheet = .settings }
                }
                Text(m.live ? "\(m.t("modeLive"))・\(m.t("logShort"))" : m.t("modeMock"))
                    .font(.system(size: 12)).foregroundStyle(m.live ? Color.vu : Color.amber).frame(maxWidth: .infinity)
                HStack(spacing: 6) {
                    Text(m.t("discShort")).foregroundStyle(Color.dim)
                    Button(m.t("needHelp")) { m.sheet = .help(fromStop: false) }.foregroundStyle(Color.amber)
                }.font(.system(size: 12)).frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 14).padding(.vertical, 18)
        }
        .scrollIndicators(.hidden)
        .onChange(of: m.screen) { _, _ in sureNew = false }
    }
    func step(_ icon: String, _ c: Color, _ a: String, _ b: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 19)).foregroundStyle(c).frame(width: 44, height: 44).background(Circle().fill(c.opacity(0.15)))
            Text(a).font(.system(size: 13, weight: .bold)).foregroundStyle(Color.paper).multilineTextAlignment(.center)
            Text(b).font(.system(size: 11)).foregroundStyle(Color.dim).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10).padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.07)))
    }
}

struct EpisodeCard: View {
    @EnvironmentObject var m: GameModel
    var body: some View {
        let s = m.S
        let first = (s?.ep ?? 1) == 1
        VStack {
            Spacer()
            Card {
                VStack(spacing: 10) {
                    Text(first ? m.t("ep1Kicker") : m.t("epNKicker", ["n": "\(s?.ep ?? 1)"])).font(.system(size: 12)).tracking(3).foregroundStyle(Color.amber)
                    Text(first ? m.t("ep1Title") : m.t("epNTitle")).font(.system(size: 28, weight: .black, design: .serif)).foregroundStyle(Color.paper)
                    Text(first ? m.t("ep1Lede") : m.t("epNLede")).font(.system(size: 15)).foregroundStyle(Color.paper.opacity(0.85)).multilineTextAlignment(.center)
                    let th = m.themeLabel(s?.theme, custom: s?.custom)
                    if !th.isEmpty { Text(m.t("themeTonight", ["t": th])).foregroundStyle(Color.amber) }
                    Button { m.goLive() } label: {
                        if m.loading { HStack { ProgressView().tint(.white); Text(m.t("genLoading")).lineLimit(1).minimumScaleFactor(0.7) } }
                        else { Label(m.t("goLive"), systemImage: "mic.fill") }
                    }.buttonStyle(PrimaryButton()).disabled(m.loading).padding(.top, 6).accessibilityIdentifier("goLive")
                }.frame(maxWidth: .infinity)
            }.padding(.horizontal, 18)
            Spacer()
        }
    }
}

struct SummaryView: View {
    @EnvironmentObject var m: GameModel
    @State private var sureNew = false
    var body: some View {
        ScrollView {
            if let s = m.S {
                Card {
                    Text(m.t("sumEpN", ["n": "\(s.ep)"])).font(.system(size: 24, weight: .black, design: .serif)).foregroundStyle(Color.paper)
                    ForEach(s.met, id: \.self) { nid in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(m.t("crossTitle")).font(.system(size: 15, weight: .bold)).foregroundStyle(Color.amber)
                            Text(s.nights[nid]?.summary?[m.lang] ?? s.nights[nid]?.summary?["en"] ?? m.t("crossBody")).foregroundStyle(Color.paper)
                        }.padding(12).background(RoundedRectangle(cornerRadius: 14).fill(Color.amber.opacity(0.12)))
                    }
                    let back = s.cast.filter { s.callers[$0]?.phase == "callback" && s.callers[$0]?.status != "missed" }
                    let fresh = s.cast.filter { s.callers[$0]?.phase == "new" && s.callers[$0]?.status != "missed" }
                    if !back.isEmpty {
                        head(m.t("sumBack"))
                        ForEach(back, id: \.self) { id in
                            let c = s.callers[id]!, paused = c.status == "paused" || c.outcome == nil
                            row(id, c, Text(m.t(paused ? "res_paused" : "res_\(c.outcome!)")).foregroundStyle(paused ? Color.dim : c.outcome == "good" ? Color.vu : c.outcome == "bad" ? Color.onair : Color.amber).bold())
                        }
                    }
                    if !fresh.isEmpty {
                        head(m.t("sumNew"))
                        Text(m.t("sumEp1Lede")).font(.system(size: 13)).foregroundStyle(Color.dim)
                        ForEach(fresh, id: \.self) { id in
                            let c = s.callers[id]!
                            row(id, c, Text(c.status == "paused" ? m.t("res_paused") : m.t("planLabel") + (c.plan.isEmpty ? m.t("noPlan") : c.plan)).foregroundStyle(Color.paper.opacity(0.85)))
                        }
                    }
                    HStack {
                        stat(m.t("statPeak"), s.peak); stat(m.t("statCalls"), s.calls); stat(m.t("statSongs"), s.songsTotal)
                    }
                    Text(m.t("autosaved", ["n": "\(m.saves.active)"])).font(.system(size: 13)).foregroundStyle(Color.vu)
                    ThemePicker { Task { await m.nextEpisode() } }
                    Button(m.t("nextWeek")) { Task { await m.nextEpisode() } }.buttonStyle(PrimaryButton()).accessibilityIdentifier("nextWeek")
                    HStack(spacing: 8) {
                        Button(m.t("history")) { m.sheet = .history }.buttonStyle(SoftButton())
                        Button(sureNew ? m.t("newShowSure") : m.t("newShow")) {
                            if !sureNew { sureNew = true; return }
                            sureNew = false; Task { await m.startNewShow() }
                        }.buttonStyle(SoftButton()).lineLimit(2)
                        Button(m.t("backTitle")) { m.toTitle() }.buttonStyle(SoftButton())
                    }
                    Text(m.t("discShort")).font(.system(size: 12)).foregroundStyle(Color.dim)
                }.padding(.horizontal, 14).padding(.vertical, 18)
            }
        }.scrollIndicators(.hidden)
    }
    func head(_ s: String) -> some View { Text(s).font(.system(size: 13, weight: .semibold)).tracking(1.5).foregroundStyle(Color.dim).padding(.top, 6) }
    func row(_ id: String, _ c: CallState, _ line: Text) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Portrait(name: m.E.portrait(id), size: 44, radius: 10)
            VStack(alignment: .leading, spacing: 3) {
                Text(m.E.byId(id)?.nameIn(m.lang) ?? "").bold().foregroundStyle(Color.paper)
                line.font(.system(size: 14))
                Text(m.t("why", ["t": "\(c.trust)", "m": "\(c.mood)"])).font(.system(size: 12)).foregroundStyle(Color.dim)
            }
        }
    }
    func stat(_ label: String, _ n: Int) -> some View {
        VStack(spacing: 2) { Text("\(n)").font(.system(size: 20, weight: .bold, design: .monospaced)).foregroundStyle(Color.paper); Text(label).font(.system(size: 11)).foregroundStyle(Color.dim) }
            .frame(maxWidth: .infinity).padding(.vertical, 8).background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
    }
}
