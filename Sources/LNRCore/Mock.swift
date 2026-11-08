import Foundation

// ── JS 正規表示式 → NSRegularExpression ──
// JS 的 \b 只認 ASCII 字元（[A-Za-z0-9_]），ICU 的 \b 認所有文字（中文、é…）：換成只看 ASCII 的寫法，結果才和網頁一樣。
public struct JSRegex: @unchecked Sendable {
    let re: NSRegularExpression?
    public init(_ src: String, i: Bool) {
        var out = "", inClass = false, it = Array(src), k = 0
        let w = "[A-Za-z0-9_]"
        while k < it.count {
            let ch = it[k]
            if ch == "\\" && k + 1 < it.count {
                let n = it[k + 1]
                if n == "b" && !inClass { out += "(?:(?<=\(w))(?!\(w))|(?<!\(w))(?=\(w)))" } else { out.append(ch); out.append(n) }
                k += 2; continue
            }
            if ch == "[" { inClass = true } else if ch == "]" { inClass = false }
            out.append(ch); k += 1
        }
        re = try? NSRegularExpression(pattern: out, options: i ? [.caseInsensitive] : [])
    }
    public init(_ r: RXSrc) { self.init(r.src, i: r.i) }
    public func test(_ s: String) -> Bool {
        guard let re else { return false }
        return re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }
}

/// JS 的 String.normalize('NFKC')
@inline(__always) func nfkc(_ s: String) -> String { s.precomposedStringWithCompatibilityMapping }
/// JS 的 str.replace('{x}', y)：只換第一個
func replaceFirst(_ s: String, _ a: String, _ b: String) -> String {
    guard let r = s.range(of: a) else { return s }
    return s.replacingCharacters(in: r, with: b)
}

// ── 安全檢查（safety.js）──
public struct Safety: @unchecked Sendable {
    let patterns: [JSRegex], medlegal: JSRegex
    public let data: SafetyData
    public init(_ d: SafetyData) { data = d; patterns = d.patterns.map(JSRegex.init); medlegal = JSRegex(d.medlegal) }
    public func crisis(_ text: String) -> Bool {
        if text.isEmpty { return false }
        let t = nfkc(text)
        return patterns.contains { $0.test(t) }
    }
    public func medLegal(_ text: String) -> Bool { medlegal.test(nfkc(text)) }
    public func resources(_ lang: String) -> Resources { data.resources[lang] ?? data.resources["en"]! }
    public func stopLine(_ lang: String) -> String { data.stop[lang] ?? data.stop["en"] ?? "" }
    public func medTip(_ lang: String) -> String { data.medTip[lang] ?? data.medTip["en"] ?? "" }
}

// ── LLM 的回覆格式（Worker 和離線劇本一樣）──
public struct ReplyData: Codable, Sendable, Equatable {
    public var player_distress: Bool
    public var advice_type: String
    public var tags: [String]
    public var connects_other_caller: Bool
    public var plan: String
    public var caller_emotion: String
    public var caller_line: String
    public init(player_distress: Bool = false, advice_type: String, tags: [String], connects_other_caller: Bool, plan: String, caller_emotion: String, caller_line: String) {
        self.player_distress = player_distress; self.advice_type = advice_type; self.tags = tags
        self.connects_other_caller = connects_other_caller; self.plan = plan; self.caller_emotion = caller_emotion; self.caller_line = caller_line
    }
}
public struct FollowData: Codable, Sendable, Equatable { public var caller_emotion: String; public var lines: [String] }

/// 送給 /api/llm 或離線劇本的請求（worker/prompts.js sanitize 的欄位）
public struct AskReq: Sendable {
    public var kind: String          // reply | followup
    public var caller: String
    public var lang: String
    public var ep: Int = 1
    public var turn: Int = 1
    public var maxTurns: Int = 4
    public var mood: Int = 50
    public var trust: Int = 50
    public var history: [HistLine] = []
    public var host: String = ""
    public var closing = false
    public var plan = ""
    public var advice = ""
    public var outcome = "mixed"
    public var crossover = false
    public var aired: [String] = []
    public var cards: [String: String] = [:]
    public var call = ""
    public init(kind: String, caller: String, lang: String) { self.kind = kind; self.caller = caller; self.lang = lang }
    public var json: [String: Any] {
        var o: [String: Any] = ["kind": kind, "caller": caller, "lang": lang, "ep": ep, "turn": turn, "maxTurns": maxTurns, "mood": mood, "trust": trust,
                                "history": history.map { ["who": $0.who, "text": $0.text] }, "host": host, "closing": closing, "plan": plan, "advice": advice,
                                "outcome": outcome, "crossover": crossover, "aired": aired, "call": call]
        if !cards.isEmpty { o["cards"] = cards }
        return o
    }
}

// ── 離線劇本（mockllm.js）──
public final class Mock: @unchecked Sendable {
    let d: MockData
    let rx: [String: JSRegex], tagrx: [(String, JSRegex)], link: [String: JSRegex]
    let safety: Safety
    let byId: (String) -> CallerData?
    public init(_ d: MockData, safety: Safety, byId: @escaping (String) -> CallerData?) {
        self.d = d; self.safety = safety; self.byId = byId
        rx = d.rx.mapValues(JSRegex.init); tagrx = d.tagrx.map { ($0.key, JSRegex($0.rx)) }; link = d.link.mapValues(JSRegex.init)
    }

    public func classify(_ text: String) -> (type: String, tags: [String]) {
        let t = nfkc(text)
        var tags = tagrx.filter { $0.1.test(t) }.map(\.0)
        let R = { (k: String) in self.rx[k]!.test(t) }
        if R("risky") { tags.append(JSRegex("報復|revenge|get back|仕返し|복수|vengan|v[eé]ngate", i: true).test(t) ? "revenge" : "quit_or_confront") }
        if R("ignore_it") { tags.append("ignore_it") }
        var type: String
        if safety.medLegal(t) { type = "medical_legal" }
        else if R("dismissive") || (tags.contains("ignore_it") && !R("empathy")) { type = "dismissive" }
        else if tags.contains("quit_or_confront") || tags.contains("revenge") { type = "risky" }
        else if !tags.isEmpty || R("advise") { type = "concrete_step"; if tags.isEmpty { tags.append("take_small_step") } }
        else if R("empathy") { type = "empathy" }
        else if R("question") { type = "question" }
        else if R("smalltalk") || t.utf16.count < 8 { type = "smalltalk" }
        else { type = "empathy" }
        var seen = Set<String>(), uniq: [String] = []
        for x in tags where seen.insert(x).inserted { uniq.append(x) }
        return (type, uniq)
    }

    func pick(_ a: [String], _ i: Int) -> String { a.isEmpty ? "" : a[abs(i) % a.count] }
    func planText(_ tags: [String], _ lang: String) -> String {
        guard let k = tags.first(where: { d.plan[$0] != nil && $0 != "take_small_step" }) ?? tags.first else { return "" }
        return d.plan[k]?[lang] ?? ""
    }
    func linkTest(_ c: CallerData, _ host: String) -> Bool {
        if let r = link[c.id] { return r.test(host) }
        guard let cross = c.cross, let p = byId(cross) else { return false }
        let alts = p.name.values.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        return JSRegex(alts, i: true).test(host)
    }

    public enum Out { case reply(ReplyData), follow(FollowData), safety(String) }

    public func reply(_ r: AskReq) -> Out {
        if safety.crisis(r.host) { return .safety("crisis_input") }
        guard let c = byId(r.caller) else { return .safety("bad") }
        let L = d.lines[r.caller]?[r.lang] ?? d.generic[r.lang] ?? d.generic["en"]!
        let get = { (k: String) in L[k]?.list ?? [] }
        let (type, tags) = classify(r.host)
        let plan = ["concrete_step", "risky"].contains(type) ? planText(tags, r.lang) : ""
        let small = d.plan["take_small_step"]?[r.lang] ?? ""
        let connects = c.cross != nil && r.aired.contains(c.cross!) && linkTest(c, r.host)
        var line: String
        if r.ep == 2 {
            line = pick(["dismissive", "risky", "off_topic"].contains(type) ? get("ep2_neg") : r.outcome == "bad" ? get("ep2_bad") : get("ep2_pos"), r.turn)
            if r.closing { line = L["bye2"]?.text ?? line }
        } else if connects {
            line = replaceFirst(pick(get("connect"), r.turn), "{partner}", byId(c.cross!)?.nameIn(r.lang) ?? "")
        } else {
            line = replaceFirst(pick(get(type), r.turn + r.host.utf16.count), "{plan}", plan.isEmpty ? small : plan)
        }
        if r.closing && r.ep == 1 {
            let p = plan.isEmpty ? r.plan : plan
            line = p.isEmpty ? (L["close_none"]?.text ?? "") : replaceFirst(L["close_plan"]?.text ?? "", "{plan}", p)
        }
        return .reply(ReplyData(advice_type: type, tags: tags, connects_other_caller: connects, plan: plan,
                                caller_emotion: connects ? "amused" : (d.emo[type] ?? "neutral"), caller_line: line))
    }

    public func followup(_ r: AskReq) -> Out {
        guard let c = byId(r.caller) else { return .safety("bad") }
        let f = d.follow[r.caller]?[r.lang] ?? d.gfollow[r.lang] ?? d.gfollow["en"]!
        let key = r.outcome == "good" && r.crossover && f["good_cross"] != nil ? "good_cross" : r.outcome
        let plan = r.plan.isEmpty ? (d.plan["take_small_step"]?[r.lang] ?? "") : r.plan
        let partner = c.cross.flatMap(byId)?.nameIn(r.lang) ?? ""
        let emo = ["good": "relieved", "good_cross": "amused", "mixed": "hopeful", "bad": "hurt"][key] ?? "neutral"
        let lines = (f[key] ?? []).map { replaceFirst(replaceFirst(replaceFirst($0, "{plan}", plan), "{name}", c.nameIn(r.lang)), "{partner}", partner) }
        return .follow(FollowData(caller_emotion: emo, lines: lines))
    }
}
