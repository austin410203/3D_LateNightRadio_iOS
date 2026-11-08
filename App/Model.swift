import SwiftUI
import LNRCore

enum Screen { case title, epCard, live, summary }
enum SheetKind: Identifiable, Equatable {
    case history, settings, help(fromStop: Bool)
    var id: String { switch self { case .history: return "h"; case .settings: return "s"; case .help: return "help" } }
}
struct Msg: Identifiable, Equatable { let id = UUID(); var who: String; var text: String; var name = "" }
struct Floaty: Identifiable { let id = UUID(); var text: String; var up: Bool }
struct SMS: Equatable { var text: String; var caller: String }

/// 節目流程（game.js 的原生版）。規則在 LNRCore.Engine，這裡管畫面狀態、聲音、網路、存檔。
@MainActor
final class GameModel: ObservableObject {
    let E: Engine
    let saves = SaveStore()
    let net = Net()
    let voice = VoiceOut()
    let mic = SpeechIn()

    @Published var settings: Settings { didSet { SettingsStore.save(settings); voice.voiceOn = settings.voice && !noVoice } }
    @Published var screen: Screen = .title
    @Published var S: Show?
    @Published var loading = false
    @Published var cur: String?
    @Published var busy = false
    @Published var closingNext = false
    @Published var msgs: [Msg] = []
    @Published var bubble = ""
    @Published var talking = false
    @Published var input = ""
    @Published var inputReady = false
    @Published var listening = false
    @Published var micHint = ""
    @Published var floaties: [Floaty] = []
    @Published var sms: SMS?
    @Published var songing = false
    @Published var logOpen = false
    @Published var sheet: SheetKind?
    @Published var toast: String?
    @Published var live = false
    @Published var booted = false

    private var callLines: [[String]] = []
    private var callId = ""
    private var skipTalk = false
    private var capHit = false
    private var micBase = ""
    private var micOK: SpeechIn.Status?
    private var smsToken = 0
    private var toastToken = 0
    var rng = SystemRandomNumberGenerator()
    let fast: Bool, noVoice: Bool, forceSMS: Bool
    let autotest: String?

    var lang: String { settings.lang }
    func t(_ k: String, _ p: [String: String] = [:]) -> String {
        if let x = Extra.s[lang]?[k] ?? Extra.s["en"]?[k] {
            var s = x; for (a, b) in p { s = s.replacingOccurrences(of: "{\(a)}", with: b) }; return s
        }
        return E.t(lang, k, p)
    }

    init() {
        let url = Bundle.main.url(forResource: "game", withExtension: "json", subdirectory: "GameData")!
        E = Engine(try! GameData.load(Data(contentsOf: url)))
        settings = SettingsStore.load()
        let a = ProcessInfo.processInfo.arguments
        func arg(_ k: String) -> String? { a.firstIndex(of: k).flatMap { $0 + 1 < a.count ? a[$0 + 1] : nil } }
        autotest = arg("-autotest")
        fast = a.contains("-fast") || autotest != nil
        noVoice = a.contains("-novoice") || autotest != nil
        forceSMS = autotest != nil
        if let l = arg("-lang"), E.data.langs.contains(l) { settings.lang = l }
        if a.contains("-mock") || autotest != nil { net.forceMock = true }
        if !E.data.langs.contains(settings.lang) { settings.lang = "en" }
        voice.net = net
        voice.manifest = Set(E.data.audio)
        voice.voiceOn = settings.voice && !noVoice
    }

    func boot() async {
        guard !booted else { return }
        booted = true
        voice.setup()
        let h = await net.health()
        live = h.live
        voice.apiTts = h.tts
        if autotest != nil { Autopilot(model: self).run() }
    }

    // ── 主題 ──
    var themeNow: String { settings.theme == "custom" && settings.custom.trimmingCharacters(in: .whitespaces).isEmpty ? "random" : settings.theme }
    var themeKey: String { "\(themeNow)|\(themeNow == "custom" ? settings.custom.trimmingCharacters(in: .whitespaces) : "")" }
    func themeLabel(_ th: String?, custom: String?) -> String {
        guard let th, th != "random" else { return "" }
        return th == "custom" ? (custom ?? "") : t("theme_\(th)")
    }
    /// 自訂主題也先過第一層安全檢查：有危機字眼就清掉、打開求助資訊
    func setCustom(_ v: String) {
        let s = String(v.replacingOccurrences(of: "<", with: "").replacingOccurrences(of: ">", with: "").prefix(30))
        if E.safety.crisis(s) { settings.custom = ""; sheet = .help(fromStop: false); return }
        settings.custom = s
    }

    // ── 存檔 ──
    var savedShow: Show? { E.valid(saves.slot.progress) ? saves.slot.progress : nil }
    func persist() { saves.slot.progress = S; saves.save() }
    func say(toast s: String) {
        toast = s; toastToken += 1
        let my = toastToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in if self?.toastToken == my { self?.toast = nil } }
    }

    // ── 開播／繼續 ──
    func start() async {
        guard !loading else { return }
        if var p = savedShow {
            if p.ended { S = p; await nextEpisode(); return }
            // 換了主題：今晚的新來電者都還沒接過 → 馬上照新主題重新生成；已經接過 → 下一集才換
            if (p.themeKey ?? "random|") != themeKey {
                let fresh = p.cast.filter { p.callers[$0]?.phase == "new" }
                if !fresh.isEmpty && fresh.allSatisfy({ p.callers[$0]?.status == "waiting" }) {
                    for id in fresh { p.callers[id] = nil }
                    p.cast.removeAll { fresh.contains($0) }
                    p.nights = p.nights.filter { k, _ in p.cast.contains { p.callers[$0]?.night == k } }
                    S = p
                    await prepare { await self.addTonight(first: false) }
                    return
                }
                if !fresh.isEmpty { say(toast: t("themeLater")) }
            }
            S = p; persist(); screen = .epCard
            return
        }
        await startNewShow()
    }
    func startNewShow() async {
        saves.slot.stats.shows += 1
        S = Show(show: saves.slot.stats.shows)
        await prepare { await self.addTonight(first: true) }
    }
    func nextEpisode() async {
        guard var s = S else { return }
        E.beginNext(&s); S = s
        await prepare { await self.addTonight(first: false) }
    }
    private func addTonight(first: Bool) async {
        let n = await newNight(first: first)
        guard var s = S else { return }
        E.addNight(&s, n); s.end = E.showEnd(s); E.prune(&s)
        S = s
    }
    /// 標題卡先出來，「開麥」等總機接好今晚的電話
    private func prepare(_ fn: @escaping () async -> Void) async {
        S?.theme = themeNow
        S?.custom = themeNow == "custom" ? settings.custom.trimmingCharacters(in: .whitespaces) : nil
        S?.themeKey = themeKey
        screen = .epCard; loading = true
        await fn()
        loading = false
        persist()
    }
    /// 今晚的新來電者：即時模式請 Haiku 生成；失敗或離線從來電者池抽，第一集離線固定阿哲／小芸／林伯
    private func newNight(first: Bool) async -> NewNight {
        if live && !capHit {
            var recent = UserDefaults.standard.stringArray(forKey: "lnr_recent") ?? []
            if let g = await net.night(lang: lang, avoid: recent, theme: themeNow, custom: themeNow == "custom" ? settings.custom : nil) {
                E.registerLive(g.live)
                recent += g.live.map { "\($0.nameIn(lang))（\(String($0.screenerIn(lang).prefix(18)))）" }
                UserDefaults.standard.set(Array(recent.suffix(30)), forKey: "lnr_recent")
                return g
            }
        }
        if first && !live && themeNow == "random" { return NewNight(id: "n0", cast: E.data.fixedCast, pair: ["yun", "lin"], summary: nil) }
        let s = S ?? Show(show: 1)
        var d = E.drawCast(theme: themeNow, rng: &rng)
        for _ in 0..<12 where d.cast.contains(where: { s.used.contains($0) || s.callers[$0] != nil }) { d = E.drawCast(theme: themeNow, rng: &rng) }
        let n = E.nights.first { $0.id == d.night }
        return NewNight(id: d.night, cast: d.cast.filter { s.callers[$0] == nil }, pair: n?.pair ?? [], summary: n?.summary)
    }

    func goLive() {
        voice.chime()
        screen = .live
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.voice.ring() }
    }
    func toTitle() {
        voice.stop()
        if let id = cur, S != nil { S!.callers[id]?.status = "waiting"; S!.callers[id]?.turns = 0; S!.callers[id]?.hist = []; callLines = []; cur = nil; busy = false }
        if S != nil { persist() }
        sms = nil; screen = .title
    }

    // ── 小工具 ──
    func tick(_ m: Int) { S?.clock += m }
    func ears(_ d: Double) { guard var s = S else { return }; E.ears(&s, d); S = s }
    func clock(_ m: Int) -> String { String(format: "%02d:%02d", (m / 60) % 24, m % 60) }
    private func msg(_ who: String, _ text: String) {
        var m = Msg(who: who, text: text)
        if who == "caller", let id = cur { m.name = E.byId(id)?.nameIn(lang) ?? "" }
        msgs.append(m)
        if cur != nil && !text.isEmpty && who != "typing" { callLines.append([String(who.prefix(1)), text]) }
    }
    private func floaty(_ text: String, _ up: Bool) {
        let f = Floaty(text: text, up: up); floaties.append(f)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.floaties.removeAll { $0.id == f.id } }
    }
    func lineStatus(_ c: CallState) -> String {
        switch c.status { case "waiting": return c.phase == "callback" ? t("callback") : t("waiting"); case "onair": return t("onCall"); case "paused": return t("paused"); default: return t("done") }
    }

    // ── 播歌 ──
    var canSong: Bool { cur == nil && !songing && (S?.songs ?? 9) < SONGS_PER_EP }
    func playSong() async {
        guard canSong else { return }
        songing = true; S!.songs += 1; S!.songsTotal += 1
        await voice.playSong(seconds: fast ? 1 : 20)
        songing = false; tick(4); ears(80 + Double.random(in: 0..<60))
    }
    func skipSong() { if songing { voice.skipSong() } }

    // ── LLM（失敗或額度用完就用離線劇本）──
    private func ask(_ r: AskReq) async -> Mock.Out {
        if live && !capHit {
            switch await net.llm(r) {
            case .reply(let d): return .reply(d)
            case .follow(let f): return .follow(f)
            case .safety(let s): return .safety(s)
            case .cap: capHit = true; live = false; say(toast: t("modeCap"))
            case .fail: break
            }
        }
        return r.kind == "followup" ? E.mock.followup(r) : E.mock.reply(r)
    }

    // ── 接電話 ──
    func pickUp(_ id: String) async {
        guard cur == nil, !busy, S != nil, let cd = E.byId(id), S!.callers[id] != nil else { return }
        skipSong()
        cur = id; S!.callers[id]!.status = "onair"; busy = true; closingNext = false; skipTalk = false
        callLines = []; callId = String(UUID().uuidString.prefix(10)).lowercased()
        if !S!.aired.contains(id) { S!.aired.append(id) }
        S!.calls += 1
        voice.pickup(); tick(1)
        msgs = []; input = ""; bubble = ""; logOpen = false; sms = nil; inputReady = false; micHint = ""
        var lines: [String]
        let c = S!.callers[id]!
        if c.phase == "new" { lines = cd.openingIn(lang) }
        else {
            msg("typing", "")
            let r = await ask(E.request(S!, c, kind: "followup", lang: lang, call: callId))
            msgs.removeAll { $0.who == "typing" }
            guard case .follow(let f) = r, !f.lines.isEmpty else { await safetyStop("crisis_output"); return }
            lines = f.lines
        }
        tick(2)
        for l in lines { if cur != id { return }; await say(l) }
        busy = false
    }
    /// 點字幕可以跳過正在說的話（這通電話接下來的台詞也直接顯示字幕）
    func skipSpeech() { if talking { skipTalk = true; voice.stop() } }
    private func say(_ text: String) async {
        guard let id = cur, let cd = E.byId(id) else { return }
        msg("caller", text); bubble = text
        S!.callers[id]!.hist.append(HistLine(who: "caller", text: text))
        S!.callers[id]!.hist = Array(S!.callers[id]!.hist.suffix(8))
        if skipTalk { return }
        talking = true
        await voice.speak(text, cd, lang)
        talking = false
    }

    // ── 主持人說話 ──
    func send() async { await hostSay(input) }
    func wrap() async {
        guard cur != nil, !busy else { return }
        closingNext = true
        if input.trimmingCharacters(in: .whitespaces).isEmpty { await hostSay(t("wrapDefault")) }
    }
    var canWrap: Bool { guard let id = cur, let c = S?.callers[id] else { return false }; return !busy && c.turns >= 1 }
    func hostSay(_ raw: String) async {
        let text = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
        guard let id = cur, !busy, !text.isEmpty else { return }
        voice.stop(); skipTalk = false
        busy = true; input = ""; inputReady = false; micHint = ""
        msg("host", text); tick(3)
        // 第一層：送出前先檢查（命中就不送給 LLM）
        if E.safety.crisis(text) { await safetyStop("crisis_input"); return }
        let c = S!.callers[id]!
        let closing = closingNext || c.turns + 1 >= (TURNS[c.phase] ?? 4)
        msg("typing", "")
        var req = E.request(S!, c, kind: "reply", lang: lang, call: callId)
        req.host = text; req.closing = closing
        let r = await ask(req)
        msgs.removeAll { $0.who == "typing" }
        S!.callers[id]!.hist.append(HistLine(who: "host", text: text))
        switch r {
        case .safety(let s): await safetyStop(s); return
        case .reply(let d):
            S!.callers[id]!.turns += 1
            var s = S!
            let dl = E.applyReply(&s, id, d, hostText: text, jitter: 0.8 + Double.random(in: 0..<0.4))
            E.ears(&s, dl.ear); S = s
            if Int(dl.trust.rounded()) != 0 { floaty("\(t("trust")) \(dl.trust > 0 ? "+" : "")\(Int(dl.trust.rounded()))", dl.trust > 0) }
            if Int(dl.mood.rounded()) != 0 { floaty("\(t("mood")) \(dl.mood > 0 ? "+" : "")\(Int(dl.mood.rounded()))", dl.mood > 0) }
            if d.advice_type == "medical_legal" { msg("sys", E.safety.medTip(lang)) }
            await say(d.caller_line)
            if cur != id { return }
            if closing { await endCall(id); return }
            busy = false
            maybeSms(id)
        default:
            msg("sys", t("micErr")); busy = false
        }
    }

    // ── 聽眾簡訊（小互動）──
    private func maybeSms(_ id: String) {
        guard cur == id, S?.callers[id]?.sms == false, forceSMS || Double.random(in: 0..<1) < 0.45 else { return }
        S!.callers[id]!.sms = true
        let pool = t("smsPool").split(separator: "|").map(String.init)
        let text = (pool.randomElement() ?? "").replacingOccurrences(of: "%n", with: E.byId(id)?.nameIn(lang) ?? "")
        sms = SMS(text: text, caller: id)
        smsToken += 1
        let my = smsToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 16) { [weak self] in if self?.smsToken == my { self?.sms = nil } }
    }
    func readSms() {
        guard let s = sms, cur == s.caller else { sms = nil; return }
        sms = nil
        msg("sys", "\(t("smsAired"))「\(s.text)」")
        S!.smsRead += 1
        ears(90 + Double.random(in: 0..<60))
        S!.callers[s.caller]!.mood = clamp100(Double(S!.callers[s.caller]!.mood) + 3)
        S!.callers[s.caller]!.trust = clamp100(Double(S!.callers[s.caller]!.trust) + 2)
        floaty("\(t("mood")) +3", true)
    }

    // ── 掛電話 ──
    private func endCall(_ id: String) async {
        voice.hangup(); msg("sys", t("hangup"))
        S!.callers[id]!.status = "done"
        if S!.callers[id]!.phase == "new" { S!.callers[id]!.outcome = E.outcomeOf(S!.callers[id]!).o }
        await finishCall(id)
    }
    private func saveTranscript(_ id: String?) {
        guard let id, let s = S, let c = s.callers[id], let cd = E.byId(id), !callLines.isEmpty else { return }
        saves.slot.transcripts.append(Transcript(show: s.show, ep: s.ep, caller: id, name: cd.nameIn(lang), job: cd.jobIn(lang), phase: c.phase, at: Date(),
                                                 plan: c.plan, res: c.phase == "callback" ? c.outcome : nil, lines: Array(callLines.prefix(80))))
        callLines = []
    }
    private func finishCall(_ id: String?) async {
        saveTranscript(id)
        try? await Task.sleep(nanoseconds: fast ? 50_000_000 : 900_000_000)
        cur = nil; busy = false; closingNext = false; sms = nil; talking = false
        persist(); say(toast: t("autosaved", ["n": "\(saves.active)"]))
        guard let s = S else { return }
        if s.clock >= s.end { endEpisode() }
        else if s.callers.values.contains(where: { $0.status == "waiting" }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in if self?.cur == nil && self?.screen == .live { self?.voice.ring() } }
        }
    }

    // ── 停止流程（危機偵測；固定台詞，不經過 LLM）──
    private func safetyStop(_ why: String) async {
        let id = cur
        S?.safetyStops += 1
        if let id, let cd = E.byId(id) {
            let line = E.safety.stopLine(lang)
            msg("caller", line); bubble = line
            talking = true; await voice.speak(line, cd, lang); talking = false
            voice.hangup()
            S!.callers[id]!.status = "paused"
            if S!.callers[id]!.phase == "new" { S!.callers[id]!.outcome = nil }
            S!.callers[id]!.safety = why
        }
        await finishCall(id)
        sheet = .help(fromStop: true)
    }

    // ── 一集結束 ──
    var anyLeft: Bool { S?.callers.values.contains { $0.status == "waiting" || $0.status == "onair" } ?? false }
    func endEpisode() {
        guard cur == nil, var s = S else { return }
        voice.stop()
        let res = E.endEpisode(&s)
        S = s
        saves.slot.log.append(LogEntry(at: Date(), show: s.show, ep: s.ep, peak: s.peak,
                                       res: res.map { [E.byId($0.id)?.nameIn(lang) ?? "?", $0.o] }))
        saves.slot.stats.eps += 1; saves.slot.stats.crossovers += s.met.count
        persist()
        screen = .summary
    }

    // ── 麥克風（按住說話；說完先進輸入框，改完再送出）──
    func micDown() async {
        guard cur != nil, !busy, !listening else { return }
        voice.stop()
        if micOK == nil { micOK = await mic.authorize() }
        guard micOK == .ok else { micHint = t("micDenied"); return }
        micBase = input.trimmingCharacters(in: .whitespaces)
        let ok = mic.start(lang: lang) { [weak self] s in self?.input = self?.joinMic(s) ?? s }
        listening = ok
        micHint = ok ? t("micListening") : t("micNone")
    }
    func micUp() async {
        guard listening else { return }
        let s = await mic.stop()
        listening = false
        if s.isEmpty { micHint = t("micErr"); return }
        input = joinMic(s); inputReady = true; micHint = t("micEdit")
    }
    private func joinMic(_ s: String) -> String {
        guard !micBase.isEmpty else { return s }
        let cjk = micBase.unicodeScalars.last.map { (0x3000...0x9FFF).contains($0.value) || (0xAC00...0xD7AF).contains($0.value) } ?? false
        return micBase + (cjk ? "" : " ") + s
    }

    // ── 通話紀錄匯出 ──
    func historyText() -> String {
        saves.slot.transcripts.map { r in
            let head = "【\(t("showEp", ["s": "\(r.show)", "e": "\(r.ep)"]))】\(r.name)（\(r.job)）\(r.phase == "callback" ? t("callbackCall") : t("firstCall"))　\(r.at.formatted(date: .abbreviated, time: .shortened))"
            return head + "\n" + r.lines.map { l in "\(l[0] == "h" ? t("host") : l[0] == "c" ? r.name : "—")：\(l.count > 1 ? l[1] : "")" }.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}
