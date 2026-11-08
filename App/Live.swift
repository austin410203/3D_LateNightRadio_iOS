import SwiftUI
import LNRCore

// 播出中：上半是場景（主持人／來電者大頭像＋字幕泡泡＋聽眾簡訊），下半是線路抽屜或通話面板（對話預設收合、麥克風大顆置中）

struct LiveView: View {
    @EnvironmentObject var m: GameModel
    var body: some View {
        VStack(spacing: 0) {
            HUD()
            SceneArea().padding(.horizontal, 12).padding(.top, 6)
            Spacer(minLength: 8)
            if m.cur != nil { CallPanel() } else { Board() }
        }
        .overlay(alignment: .trailing) {
            VStack(alignment: .trailing, spacing: 4) {
                ForEach(m.floaties) { f in
                    Text(f.text).font(.system(size: 13, weight: .semibold)).foregroundStyle(f.up ? Color.vu : Color(red: 1, green: 0.54, blue: 0.54))
                        .padding(.horizontal, 8).padding(.vertical, 2).background(Capsule().fill(Color.night.opacity(0.85)))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }.padding(.trailing, 14).padding(.top, 200).animation(.easeOut, value: m.floaties.count)
        }
    }
}

struct HUD: View {
    @EnvironmentObject var m: GameModel
    var body: some View {
        HStack(spacing: 12) {
            if let s = m.S {
                Text(m.clock(s.clock)).font(.system(size: 21, design: .monospaced)).foregroundStyle(Color.vu).shadow(color: .vu.opacity(0.5), radius: 6)
                TimelineView(.periodic(from: .now, by: 2)) { _ in
                    Label("\(s.listeners + Int.random(in: -12...12))", systemImage: "headphones").font(.system(size: 15, design: .monospaced)).foregroundStyle(Color.amber)
                }
            }
            Spacer()
            Text(m.t("onair")).font(.system(size: 13, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 4).background(RoundedRectangle(cornerRadius: 7).fill(Color.onair)).shadow(color: .onair.opacity(0.7), radius: 8)
            Spacer()
            Button { m.sheet = .help(fromStop: false) } label: { Image(systemName: "lifepreserver").font(.system(size: 19)).foregroundStyle(Color(red: 1, green: 0.7, blue: 0.7)).frame(width: 40, height: 40).background(Circle().fill(Color.white.opacity(0.08))) }
                .accessibilityLabel(m.t("needHelp"))
            Button { m.sheet = .settings } label: { Image(systemName: "line.3.horizontal").font(.system(size: 19)).foregroundStyle(Color.paper).frame(width: 40, height: 40).background(Circle().fill(Color.white.opacity(0.08))) }
                .accessibilityLabel(m.t("settings"))
        }
        .padding(.horizontal, 14).padding(.top, 4)
    }
}

struct SceneArea: View {
    @EnvironmentObject var m: GameModel
    var body: some View {
        VStack(spacing: 10) {
            if let id = m.cur, let cd = m.E.byId(id), let c = m.S?.callers[id] {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        ZStack {
                            Portrait(name: m.E.portrait(id), size: 92, radius: 20)
                            if m.talking { RoundedRectangle(cornerRadius: 24).stroke(Color.vu, lineWidth: 2).frame(width: 100, height: 100).modifier(Pulse()) }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(cd.nameIn(m.lang)).font(.system(size: 20, weight: .bold)).foregroundStyle(Color.paper)
                            Text("\(cd.age.map(String.init) ?? "")・\(cd.jobIn(m.lang))").font(.system(size: 12.5)).foregroundStyle(Color.dim).lineLimit(2)
                            meter(m.t("mood"), c.mood, .amber)
                            meter(m.t("trust"), c.trust, .vu)
                        }
                    }
                    if !m.bubble.isEmpty {
                        ScrollView { Text(m.bubble).font(.system(size: 15)).foregroundStyle(Color.paper).frame(maxWidth: .infinity, alignment: .leading) }
                            .frame(maxHeight: 104).padding(12).background(UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 16, bottomTrailingRadius: 16, topTrailingRadius: 16).fill(Color.white.opacity(0.1)))
                            .onTapGesture { m.skipSpeech() }
                    }
                }
                .padding(12).background(RoundedRectangle(cornerRadius: 20).fill(Color.glass)).overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.lineC))
            } else {
                VStack(spacing: 8) {
                    Portrait(name: "dj", size: 112, radius: 24).overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.onair.opacity(0.6), lineWidth: 3))
                    Text(m.songing ? m.t("songOn") : m.t("idleCap")).font(.system(size: 13.5)).foregroundStyle(Color.paper).padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(Color.night.opacity(0.75)))
                        .onTapGesture { m.skipSong() }
                }.padding(.top, 8)
            }
            if let s = m.sms {
                HStack(spacing: 10) {
                    Image(systemName: "message.fill").font(.system(size: 22)).foregroundStyle(Color.amber)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.t("smsTitle")).font(.system(size: 11.5)).foregroundStyle(Color.amber)
                        Text(s.text).font(.system(size: 13.5)).foregroundStyle(Color.paper).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Button(m.t("smsRead")) { m.readSms() }.buttonStyle(PrimaryButton(big: false)).frame(width: 96)
                }
                .padding(10).background(RoundedRectangle(cornerRadius: 16).fill(Color(red: 0.16, green: 0.12, blue: 0.04).opacity(0.92)))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.amber.opacity(0.55)))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }.animation(.easeOut(duration: 0.3), value: m.sms)
    }
    func meter(_ label: String, _ v: Int, _ c: Color) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 12)).foregroundStyle(Color.dim).frame(width: 52, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) { Capsule().fill(Color.white.opacity(0.1)); Capsule().fill(c).frame(width: g.size.width * CGFloat(v) / 100) }
            }.frame(height: 7).animation(.easeOut(duration: 0.8), value: v)
        }
    }
}

struct Pulse: ViewModifier {
    @State private var on = false
    func body(content: Content) -> some View {
        content.scaleEffect(on ? 1.12 : 0.96).opacity(on ? 0 : 0.8)
            .onAppear { withAnimation(.easeOut(duration: 1).repeatForever(autoreverses: false)) { on = true } }
    }
}

/// 線路（下方抽屜，上半個畫面留給場景）：今晚照主題生成的新來電者排前面，上週回電排後面
struct Board: View {
    @EnvironmentObject var m: GameModel
    var body: some View {
        if let s = m.S {
            let order = s.cast.filter { s.callers[$0]?.phase == "new" } + s.cast.filter { s.callers[$0]?.phase != "new" }
            let th = m.themeLabel(s.theme, custom: s.custom)
            VStack(alignment: .leading, spacing: 8) {
                Text(m.t("lines")).font(.system(size: 13, weight: .semibold)).tracking(2).foregroundStyle(Color.dim)
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(order.enumerated()), id: \.element) { i, id in
                            let c = s.callers[id]!
                            if i == 0 && c.phase == "new" && !th.isEmpty { sub(m.t("themeTonight", ["t": th])) }
                            if c.phase != "new" && (i == 0 || s.callers[order[i - 1]]?.phase == "new") { sub(m.t("sumBack")) }
                            line(id, c, i + 1)
                        }
                    }
                }.frame(maxHeight: 330)
                HStack(spacing: 8) {
                    if m.anyLeft {
                        Button { Task { await m.playSong() } } label: { Label(m.t("playSong"), systemImage: "music.note") }
                            .buttonStyle(SoftButton()).disabled(!m.canSong).opacity(m.canSong ? 1 : 0.45)
                    } else {
                        Button(m.t("endShow")) { m.endEpisode() }.buttonStyle(PrimaryButton(big: false)).accessibilityIdentifier("endShow")
                    }
                }.frame(maxWidth: .infinity)
                Text(!m.anyLeft ? m.t("tipAll") : s.songs >= SONGS_PER_EP ? m.t("songNone") : s.cast.contains { s.callers[$0]?.phase == "callback" } ? m.t("tipEpN") : m.t("tipEp1"))
                    .font(.system(size: 12)).foregroundStyle(Color.dim)
            }
            .padding(12).background(RoundedRectangle(cornerRadius: 20).fill(Color.glass)).overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.lineC))
            .padding(.horizontal, 10).padding(.bottom, 6)
        }
    }
    func sub(_ s: String) -> some View { Text(s).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Color.amber).padding(.top, 4) }
    func line(_ id: String, _ c: CallState, _ n: Int) -> some View {
        let cd = m.E.byId(id)
        let ringing = c.status == "waiting"
        return HStack(alignment: .top, spacing: 10) {
            Portrait(name: m.E.portrait(id), size: 46, radius: 12)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(cd?.nameIn(m.lang) ?? "").bold().foregroundStyle(Color.paper)
                    Text("\(cd?.age.map(String.init) ?? "")・\(cd?.jobIn(m.lang) ?? "")").font(.system(size: 12)).foregroundStyle(Color.dim).lineLimit(1)
                }
                Text(c.phase == "callback" && !c.plan.isEmpty ? m.t("planLabel") + c.plan : cd?.screenerIn(m.lang) ?? "").font(.system(size: 13)).foregroundStyle(Color.paper.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("L\(n)・\(m.lineStatus(c))").font(.system(size: 12)).foregroundStyle(Color.dim)
                    Spacer()
                    if ringing && m.cur == nil {
                        Button { Task { await m.pickUp(id) } } label: { Label(m.t("pick"), systemImage: "phone.fill") }
                            .buttonStyle(PrimaryButton(big: false)).frame(width: 110).accessibilityIdentifier("pick_\(n)")
                    }
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ringing ? Color.onair.opacity(0.55) : .clear))
        .opacity(["done", "paused", "missed"].contains(c.status) ? 0.55 : 1)
    }
}

/// 通話面板：對話紀錄預設收合（只看最後兩句），輸入框＋送出，大顆麥克風置中
struct CallPanel: View {
    @EnvironmentObject var m: GameModel
    @State private var pressed = false
    @FocusState private var focus: Bool
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Spacer()
                Button { withAnimation { m.logOpen.toggle() } } label: {
                    HStack(spacing: 4) { Text(m.t(m.logOpen ? "collapse" : "expand")); Image(systemName: m.logOpen ? "chevron.down" : "chevron.up") }
                        .font(.system(size: 12.5)).foregroundStyle(Color.paper).padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill(Color.night.opacity(0.95))).overlay(Capsule().stroke(Color.lineC))
                }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(m.msgs) { x in bubble(x).id(x.id) }
                    }.padding(.vertical, 2)
                }
                .frame(height: m.logOpen ? 330 : 84)
                .mask(LinearGradient(colors: m.logOpen ? [.black, .black] : [.clear, .black, .black], startPoint: .top, endPoint: .bottom))
                .onChange(of: m.msgs.count) { _, _ in if let l = m.msgs.last { withAnimation { proxy.scrollTo(l.id, anchor: .bottom) } } }
                .onAppear { if let l = m.msgs.last { proxy.scrollTo(l.id, anchor: .bottom) } }
                .onTapGesture { m.skipSpeech() }
            }
            HStack(spacing: 8) {
                TextField(m.closingNext ? m.t("phWrap") : m.t("ph"), text: $m.input, axis: .vertical)
                    .lineLimit(1...3).focused($focus).submitLabel(.send).onSubmit { Task { await m.send() } }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 22).fill(Color.black.opacity(0.35))).overlay(RoundedRectangle(cornerRadius: 22).stroke(focus ? Color.amber.opacity(0.6) : Color.lineC))
                    .foregroundStyle(Color.paper).disabled(m.busy)
                Button(m.t("send")) { focus = false; Task { await m.send() } }
                    .buttonStyle(PrimaryButton(big: false)).frame(width: 84).disabled(m.busy || m.input.trimmingCharacters(in: .whitespaces).isEmpty)
                    .overlay(Capsule().stroke(Color.onair.opacity(m.inputReady ? 0.6 : 0), lineWidth: 4).padding(-3))
                    .accessibilityIdentifier("send")
            }
            ZStack {
                HStack {
                    Button(m.t("wrap")) { Task { await m.wrap() } }.buttonStyle(SoftButton()).disabled(!m.canWrap).opacity(m.canWrap ? 1 : 0.45)
                    Spacer()
                }
                // 按住說話（老闆 2026-10-31：大顆、置中，手機好按）
                Image(systemName: "mic.fill").font(.system(size: 30)).foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(m.listening ? Color.onair : Color(red: 0.11, green: 0.16, blue: 0.25)))
                    .overlay(Circle().stroke(Color.onair, lineWidth: 3))
                    .shadow(color: m.listening ? Color.onair.opacity(0.6) : .black.opacity(0.45), radius: m.listening ? 16 : 8)
                    .scaleEffect(pressed ? 1.08 : 1)
                    .opacity(m.busy ? 0.45 : 1)
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { _ in if !pressed { pressed = true; focus = false; Task { await m.micDown() } } }
                        .onEnded { _ in pressed = false; Task { await m.micUp() } })
                    .accessibilityLabel("push to talk").accessibilityAddTraits(.isButton)
            }
            if !m.micHint.isEmpty { Text(m.micHint).font(.system(size: 12)).foregroundStyle(Color.dim).multilineTextAlignment(.center) }
        }
        .padding(12).background(RoundedRectangle(cornerRadius: 20).fill(Color.glass)).overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.lineC))
        .padding(.horizontal, 8).padding(.bottom, 4)
    }
    @ViewBuilder func bubble(_ x: Msg) -> some View {
        switch x.who {
        case "host":
            HStack { Spacer(minLength: 40); Text(x.text).padding(.horizontal, 12).padding(.vertical, 8).background(RoundedRectangle(cornerRadius: 12).fill(Color.onair.opacity(0.22))).foregroundStyle(Color.paper) }
        case "sys":
            Text(x.text).font(.system(size: 12.5)).foregroundStyle(Color.dim).multilineTextAlignment(.center).frame(maxWidth: .infinity)
        case "typing":
            HStack { Text("…").padding(.horizontal, 14).padding(.vertical, 6).background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07))).foregroundStyle(Color.paper); Spacer() }
        default:
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(x.name).font(.system(size: 11.5)).foregroundStyle(Color.amber)
                    Text(x.text).foregroundStyle(Color.paper)
                }.padding(.horizontal, 12).padding(.vertical, 8).background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07)))
                Spacer(minLength: 40)
            }
        }
    }
}
