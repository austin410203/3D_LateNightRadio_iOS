import Foundation

// 節目狀態和數值規則：game.js 逐條移植（規則在程式，LLM 只寫台詞）

public struct HistLine: Codable, Sendable, Hashable { public var who: String; public var text: String
    public init(who: String, text: String) { self.who = who; self.text = text } }

/// 一位來電者在這檔節目裡的狀態（game.js freshCaller）
public struct CallState: Codable, Sendable {
    public var id: String
    public var night: String
    public var phase: String            // new | callback
    public var mood: Int
    public var trust: Int
    public var status: String           // waiting | onair | done | paused | missed
    public var turns = 0
    public var hits: [String] = []
    public var harms = 0
    public var types: [String: Int] = [:]
    public var tags: [String] = []
    public var plan = ""
    public var advice: [String] = []
    public var connects = false
    public var concrete = false
    public var outcome: String?
    public var hist: [HistLine] = []
    public var sms = false
    public var safety: String?
}

public struct NightState: Codable, Sendable {
    public var pair: [String]
    public var summary: [String: String]?
    public var crossover = false
}

/// 一檔節目（可以一直播下去）：每集＝上週新來電者的回電＋今晚新的三位
public struct Show: Codable, Sendable {
    public var show: Int
    public var ep = 1
    public var clock = 60
    public var end = 120
    public var listeners = 1200
    public var peak = 1200
    public var songs = 0
    public var songsTotal = 0
    public var calls = 0
    public var safetyStops = 0
    public var smsRead = 0
    public var aired: [String] = []
    public var cast: [String] = []
    public var callers: [String: CallState] = [:]
    public var nights: [String: NightState] = [:]
    public var sealed: [String: String] = [:]
    public var live: [String: CallerData] = [:]
    public var used: [String] = []
    public var link = false
    public var ended = false
    public var met: [String] = []
    public var theme: String?
    public var custom: String?
    public var themeKey: String?
    public init(show: Int) { self.show = show }
}

/// 今晚的一組新來電者（/api/night 生成的，或從池子抽的）
public struct NewNight: Sendable {
    public var id: String
    public var cast: [String]
    public var pair: [String]
    public var summary: [String: String]?
    public var live: [CallerData] = []
    public var sealed: [String: String] = [:]
    public init(id: String, cast: [String], pair: [String], summary: [String: String]?, live: [CallerData] = [], sealed: [String: String] = [:]) {
        self.id = id; self.cast = cast; self.pair = pair; self.summary = summary; self.live = live; self.sealed = sealed
    }
}

public let TURNS = ["new": 4, "callback": 2]
public let SONGS_PER_EP = 2

/// 遊戲資料＋規則（App 和 coretest 共用）
public final class Engine: @unchecked Sendable {
    public let data: GameData
    public let safety: Safety
    public private(set) var mock: Mock!
    var fixed: [String: CallerData] = [:]
    var pool: [String: CallerData] = [:]
    var liveReg: [String: CallerData] = [:]
    public var nights: [NightData] { data.nights }

    public init(_ data: GameData) {
        self.data = data
        safety = Safety(data.safety)
        for c in data.callers {
            let n = c.normalized(langs: data.langs)
            if data.fixedCast.contains(c.id) { fixed[c.id] = n } else { pool[c.id] = n }
        }
        mock = Mock(data.mock, safety: safety, byId: { [unowned self] in self.byId($0) })
    }
    public func byId(_ id: String) -> CallerData? { fixed[id] ?? liveReg[id] ?? pool[id] }
    /// 即時生成的來電者（id 以 x 開頭）：只有公開欄位
    public func registerLive(_ cs: [CallerData]) { for c in cs where c.id.hasPrefix("x") { liveReg[c.id] = c.normalized(langs: data.langs) } }
    public func t(_ lang: String, _ k: String, _ p: [String: String] = [:]) -> String {
        var s = data.ui[lang]?[k] ?? data.ui["en"]?[k] ?? data.ui["zh"]?[k] ?? k
        for (a, b) in p { s = s.replacingOccurrences(of: "{\(a)}", with: b) }
        return s
    }

    // ── 頭像（callers.js portraitOf）──
    static let PORTRAITS = ["female": ["young": [0, 1], "middle": [4, 7, 9, 11], "old": [13, 15]], "male": ["young": [2, 3], "middle": [5, 6, 8, 10], "old": [12, 14]]]
    static let FIXED_PORTRAIT = ["azhe": 5, "yun": 1, "lin": 12]
    public func portrait(_ id: String) -> String {
        guard let c = byId(id) else { return "dj" }
        var n = Self.FIXED_PORTRAIT[id]
        if n == nil {
            let list = Self.PORTRAITS[c.sex]![c.band]!
            var h: UInt32 = 0
            for ch in id.unicodeScalars { h = h &* 31 &+ UInt32(ch.value) }
            n = list[Int(h % UInt32(list.count))]
        }
        return String(format: "p%02d", n!)
    }

    // ── 抽池子（離線、或即時生成失敗時）：callers.js drawCast ──
    public func drawCast<R: RandomNumberGenerator>(theme: String, rng: inout R) -> (cast: [String], night: String) {
        let ns = data.nights.filter { $0.id != "n0" && ($0.pair + $0.solo).allSatisfy { byId($0) != nil } }
        guard !ns.isEmpty else { return (data.fixedCast, "n0") }
        let want = data.themes[theme] ?? nil
        let fits = { (id: String) in want?.contains(self.byId(id)?.topic ?? "") ?? false }
        let pairFit = ns.filter { $0.pair.contains(where: fits) }
        let from = pairFit.isEmpty ? ns : pairFit
        let pn = from.randomElement(using: &rng)!
        let others = ns.filter { $0.id != pn.id && !$0.solo.isEmpty }
        let soloFit = ns.flatMap(\.solo).filter(fits)
        let sn = others.isEmpty || Double.random(in: 0..<1, using: &rng) < 0.35 ? pn : others.randomElement(using: &rng)!
        let solo = soloFit.isEmpty ? (sn.solo.randomElement(using: &rng) ?? pn.solo.first!) : soloFit.randomElement(using: &rng)!
        return ((pn.pair + [solo]).shuffled(using: &rng), pn.id)
    }

    // ── 節目流程 ──
    public func fresh(_ id: String, night: String) -> CallState {
        let s = byId(id)?.start ?? Start(mood: 40, trust: 35)
        return CallState(id: id, night: night, phase: "new", mood: Int(s.mood), trust: Int(s.trust), status: "waiting")
    }
    public func addNight(_ S: inout Show, _ n: NewNight) {
        for id in n.cast { S.callers[id] = fresh(id, night: n.id); if !S.used.contains(id) { S.used.append(id) } }
        S.nights[n.id] = NightState(pair: n.pair, summary: n.summary)
        for (k, v) in n.sealed { S.sealed[k] = v }
        for c in n.live { S.live[c.id] = c }
        S.cast += n.cast
    }
    /// 收播時間：新來電者每位 20 分鐘、回電每位 12 分鐘，至少到 02:00
    public func showEnd(_ S: Show) -> Int { 60 + max(60, S.cast.reduce(0) { $0 + ((S.callers[$1]?.phase == "new") ? 20 : 12) }) }
    public func prune(_ S: inout Show) {
        S.sealed = S.sealed.filter { S.cast.contains($0.key) }
        S.live = S.live.filter { S.cast.contains($0.key) }
        S.used = Array(S.used.suffix(60))
    }
    /// 下一集：上週新來電者（講完的）變成回電，其他人退場（之後再接今晚的新來電者）
    public func beginNext(_ S: inout Show) {
        let back = S.cast.filter { S.callers[$0]?.phase == "new" && S.callers[$0]?.status == "done" }
        var callers: [String: CallState] = [:]
        for id in back { var c = S.callers[id]!; c.phase = "callback"; c.status = "waiting"; c.turns = 0; c.hist = []; callers[id] = c }
        S.ep += 1; S.clock = 60; S.songs = 0; S.aired = []; S.cast = back; S.callers = callers; S.link = false; S.ended = false
        S.nights = S.nights.filter { k, _ in back.contains { callers[$0]?.night == k } }
    }
    public func valid(_ S: Show?) -> Bool {
        guard let S else { return false }
        if !S.live.isEmpty { registerLive(Array(S.live.values)) }
        return !S.cast.isEmpty && S.cast.allSatisfy { byId($0) != nil && S.callers[$0] != nil }
    }

    // ── 數值規則：LLM 只分類主持人的話，加減由程式決定（game.js applyReply）──
    public struct Delta { public var mood: Double; public var trust: Double; public var ear: Double }
    public func applyReply(_ S: inout Show, _ id: String, _ d: ReplyData, hostText: String, jitter: Double = 1) -> Delta {
        guard var c = S.callers[id], let cd = byId(id) else { return Delta(mood: 0, trust: 0, ear: 0) }
        let type = d.advice_type, b = data.base[type] ?? data.base["smalltalk"]!
        let n = (c.types[type] ?? 0) + 1; c.types[type] = n
        let w = cd.needs?[type] ?? 1, fade = 1 / (1 + 0.5 * Double(n - 1))
        let k = { (v: Double) in v > 0 ? v * w * fade : v }
        var dm = k(b.mood), dt = k(b.trust)
        for tag in d.tags {
            if !c.tags.contains(tag) { c.tags.append(tag) }
            if (cd.helpful ?? []).contains(tag) && !c.hits.contains(tag) { c.hits.append(tag); dt += 6; dm += 4 }
            if (cd.harmful ?? []).contains(tag) { c.harms += 1; dt -= 8 }
        }
        if type == "concrete_step" { c.concrete = true }
        if d.connects_other_caller && cd.cross != nil && !c.connects { dt += 8; dm += 8 }
        if c.phase == "callback" { dm *= 0.5; dt *= 0.5 }
        c.mood = clamp100(Double(c.mood) + dm); c.trust = clamp100(Double(c.trust) + dt)
        if d.connects_other_caller && cd.cross != nil { c.connects = true; S.link = true }
        if c.phase == "new" && !d.plan.isEmpty { c.plan = String(d.plan.prefix(60)) }
        if c.phase == "new" && ["concrete_step", "empathy", "risky"].contains(type) { c.advice.append(String(hostText.prefix(80))); c.advice = Array(c.advice.suffix(2)) }
        S.callers[id] = c
        let ear = (b.ear ?? 0) * jitter + (d.connects_other_caller ? 180 : 0)
        return Delta(mood: dm, trust: dt, ear: ear)
    }
    public func ears(_ S: inout Show, _ delta: Double) {
        S.listeners = max(300, Int(jsRound(Double(S.listeners) + delta))); S.peak = max(S.peak, S.listeners)
    }

    /// 這週的結果：完全由程式依數值決定
    public func outcomeOf(_ c: CallState) -> (o: String, score: Int) {
        let cd = byId(c.id)
        let score = 0.45 * Double(c.trust) + 0.35 * Double(c.mood) + 10 * Double(min(c.hits.count, 2)) - 18 * Double(c.harms)
        var o = score >= 62 ? "good" : score >= 42 ? "mixed" : "bad"
        if o == "good" && (cd?.needConcrete ?? false) && !c.concrete && c.plan.isEmpty { o = "mixed" }
        return (o, Int(jsRound(score)))
    }
    /// 一對有隱藏關聯的新來電者：一位順利、另一位不是不順，而且（點出關聯，或兩人都用了會讓他們碰面的做法）→ 下一集兩人說見面了
    public func decideCrossover(_ S: Show, _ pair: [String]) -> Bool {
        guard pair.count == 2, let a = S.callers[pair[0]], let b = S.callers[pair[1]],
              [a, b].allSatisfy({ $0.phase == "new" && $0.status == "done" }) else { return false }
        let usedCross = { (c: CallState) in c.connects || c.tags.contains { (self.byId(c.id)?.crossTags ?? []).contains($0) } }
        let (good, other) = a.outcome == "good" ? (a, b) : (b, a)
        return good.outcome == "good" && other.outcome != "bad" && ((usedCross(good) && usedCross(other)) || (S.link && (a.connects || b.connects)))
    }
    public func crossFor(_ S: Show, _ c: CallState) -> Bool { (S.nights[c.night]?.crossover ?? false) && (S.nights[c.night]?.pair.contains(c.id) ?? false) }

    /// 一集結束：沒接的算錯過、決定誰在現實中相遇；回傳這集的結果列表（遊玩紀錄用）
    public func endEpisode(_ S: inout Show) -> [(id: String, o: String)] {
        for (k, c) in S.callers where c.status == "waiting" { S.callers[k]!.status = "missed" }
        var met: [String] = []
        for (nid, n) in S.nights {
            if n.pair.count == 2 && n.pair.allSatisfy({ S.callers[$0]?.phase == "new" }) && decideCrossover(S, n.pair) {
                S.nights[nid]!.crossover = true
                for id in n.pair where S.callers[id]?.outcome == "mixed" { S.callers[id]!.outcome = "good" }
            }
            if S.nights[nid]!.crossover && n.pair.contains(where: { S.callers[$0]?.phase == "callback" && S.callers[$0]?.status == "done" }) { met.append(nid) }
        }
        S.ended = true; S.met = met
        return S.cast.compactMap { id in
            guard let c = S.callers[id], c.status != "missed" else { return nil }
            return (id, c.status == "paused" ? "paused" : c.phase == "callback" ? (c.outcome ?? "paused") : "new")
        }
    }

    /// 送給 LLM 的請求：封存卡片只帶這通電話用得到的（自己、有關聯的那位、今晚講過的）
    public func request(_ S: Show, _ c: CallState, kind: String, lang: String, call: String) -> AskReq {
        var r = AskReq(kind: kind, caller: c.id, lang: lang)
        var need: [String] = []
        for id in [c.id, byId(c.id)?.cross].compactMap({ $0 }) + S.aired where !need.contains(id) && S.sealed[id] != nil { need.append(id) }
        for id in need.prefix(6) { r.cards[id] = S.sealed[id] }
        r.ep = c.phase == "callback" ? 2 : 1; r.turn = c.turns + 1; r.maxTurns = TURNS[c.phase] ?? 4
        r.mood = c.mood; r.trust = c.trust; r.aired = S.aired.filter { $0 != c.id }; r.history = c.hist; r.call = call
        r.plan = c.plan; r.outcome = c.outcome ?? "mixed"; r.crossover = crossFor(S, c); r.advice = c.advice.joined(separator: " / ")
        return r
    }
}
