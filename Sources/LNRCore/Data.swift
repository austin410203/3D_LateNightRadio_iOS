import Foundation

// 網頁匯出的遊戲資料（LateNightRadio/tools/export_native.mjs → Resources/GameData/game.json）

/// 字串或字串陣列（離線劇本裡 close_plan 是字串、empathy 是陣列）
public enum StrOrArr: Codable, Sendable {
    case s(String), a([String])
    public init(from d: Decoder) throws {
        let c = try d.singleValueContainer()
        if let s = try? c.decode(String.self) { self = .s(s) } else { self = .a(try c.decode([String].self)) }
    }
    public func encode(to e: Encoder) throws {
        var c = e.singleValueContainer()
        switch self { case .s(let s): try c.encode(s); case .a(let a): try c.encode(a) }
    }
    public var list: [String] { switch self { case .s(let s): return [s]; case .a(let a): return a } }
    public var text: String { switch self { case .s(let s): return s; case .a(let a): return a.first ?? "" } }
}

public struct RXSrc: Codable, Sendable { public let src: String; public let i: Bool }

public struct Voice: Codable, Sendable, Hashable { public var gender: String; public var pitch: Double; public var rate: Double }
public struct Start: Codable, Sendable, Hashable { public var mood: Double; public var trust: Double }

public struct CallerData: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var age: Int?
    public var gender: String?
    public var ageBand: String?
    public var topic: String?
    public var icon: String?
    public var color: String?
    public var night: String?
    public var name: [String: String]
    public var job: [String: String]
    public var screener: [String: String]
    public var opening: [String: [String]]
    public var cross: String?
    public var helpful: [String]?
    public var harmful: [String]?
    public var crossTags: [String]?
    public var needs_style: String?
    public var voice: Voice?
    public var needs: [String: Double]?
    public var start: Start?
    public var needConcrete: Bool?

    public var sex: String { (gender ?? voice?.gender) == "male" ? "male" : "female" }
    public var band: String {
        if let b = ageBand, ["young", "middle", "old"].contains(b) { return b }
        let a = age ?? 40
        return a < 30 ? "young" : a < 55 ? "middle" : "old"
    }
    public func t(_ m: [String: String], _ lang: String) -> String { m[lang] ?? m["en"] ?? m.values.first ?? "" }
    public func nameIn(_ l: String) -> String { t(name, l) }
    public func jobIn(_ l: String) -> String { t(job, l) }
    public func screenerIn(_ l: String) -> String { t(screener, l) }
    public func openingIn(_ l: String) -> [String] { opening[l] ?? opening["en"] ?? [] }

    // callers.js normalize()：只有 needs_style 的（池子、即時生成）補上權重、起始值、聲音
    static let NEEDS: [String: [String: Double]] = [
        "comfort_first": ["empathy": 1.3, "concrete_step": 1.0, "question": 1.0, "risky": 1.2],
        "action_first": ["empathy": 0.8, "concrete_step": 1.4, "question": 1.0, "risky": 1.0],
        "talk_it_out": ["empathy": 1.1, "concrete_step": 0.9, "question": 1.3, "risky": 1.0],
    ]
    static let START: [String: Start] = ["comfort_first": Start(mood: 40, trust: 35), "action_first": Start(mood: 35, trust: 30), "talk_it_out": Start(mood: 42, trust: 35)]
    static let BROWSER: [String: [String: (Double, Double)]] = [
        "female": ["young": (1.2, 1.1), "middle": (1.05, 1.0), "old": (0.95, 0.9)],
        "male": ["young": (1.05, 1.08), "middle": (0.9, 1.0), "old": (0.72, 0.88)],
    ]
    public func normalized(langs: [String]) -> CallerData {
        var c = self
        let style = ["comfort_first", "action_first", "talk_it_out"].contains(needs_style ?? "") ? needs_style! : "comfort_first"
        if c.needs == nil { c.needs = Self.NEEDS[style] }
        if c.start == nil { c.start = Self.START[style] }
        if c.needConcrete == nil { c.needConcrete = style == "action_first" }
        if c.voice == nil { let p = Self.BROWSER[sex]![band]!; c.voice = Voice(gender: sex, pitch: p.0, rate: p.1) }
        for l in langs {   // 缺的語言用英文頂替
            if c.name[l] == nil, let e = c.name["en"] { c.name[l] = e }
            if c.job[l] == nil, let e = c.job["en"] { c.job[l] = e }
            if c.screener[l] == nil, let e = c.screener["en"] { c.screener[l] = e }
            if c.opening[l] == nil, let e = c.opening["en"] { c.opening[l] = e }
        }
        return c
    }
}

public struct NightData: Codable, Sendable {
    public var id: String
    public var pair: [String]
    public var solo: [String]
    public var summary: [String: String]?
}

public struct BaseFx: Codable, Sendable { public var mood: Double; public var trust: Double; public var ear: Double? }

public struct Resources: Codable, Sendable {
    public var title: String, lead: String, items: [[String]], emergency: String, note: String
}

public struct MockData: Codable, Sendable {
    public var lines: [String: [String: [String: StrOrArr]]]
    public var follow: [String: [String: [String: [String]]]]
    public var generic: [String: [String: StrOrArr]]
    public var gfollow: [String: [String: [String]]]
    public var plan: [String: [String: String]]
    public var emo: [String: String]
    public var rx: [String: RXSrc]
    public var tagrx: [TagRX]
    public var link: [String: RXSrc]
}
/// ["write_it_down", {src, i}]（順序有意義）
public struct TagRX: Codable, Sendable {
    public var key: String, rx: RXSrc
    public init(from d: Decoder) throws { var c = try d.unkeyedContainer(); key = try c.decode(String.self); rx = try c.decode(RXSrc.self) }
    public func encode(to e: Encoder) throws { var c = e.unkeyedContainer(); try c.encode(key); try c.encode(rx) }
}

public struct SafetyData: Codable, Sendable {
    public var patterns: [RXSrc], medlegal: RXSrc
    public var resources: [String: Resources]
    public var stop: [String: String], medTip: [String: String]
}

public struct GameData: Codable, Sendable {
    public var langs: [String]
    public var poolLangs: [String]
    public var ui: [String: [String: String]]
    public var base: [String: BaseFx]
    public var advice: [String]
    public var tags: [String]
    public var themes: [String: [String]?]
    public var topics: [String]
    public var fixedCast: [String]
    public var callers: [CallerData]
    public var nights: [NightData]
    public var teaser: [String: String]
    public var mock: MockData
    public var safety: SafetyData
    public var audio: [String]

    public static func load(_ data: Data) throws -> GameData { try JSONDecoder().decode(GameData.self, from: data) }
    /// 主題按鈕的順序（JSON 物件沒有順序，照網頁 THEMES 的寫法）
    public static let themeOrder = ["random", "work", "home", "people", "life", "hobby"]
}

/// FNV-1a 32 位元，對 UTF-16 碼元（跟 callers.js lineHash 一樣：預錄 mp3 的檔名）
public func lineHash(_ caller: String, _ lang: String, _ text: String) -> String {
    var h: UInt32 = 0x811c9dc5
    let s = "\(caller)|\(lang)|\(text.trimmingCharacters(in: .whitespacesAndNewlines))"
    for u in s.utf16 { h ^= UInt32(u); h = h &* 0x01000193 }
    let hex = String(h, radix: 16)
    return String(repeating: "0", count: max(0, 8 - hex.count)) + hex
}

/// JS 的 Math.round（.5 往正無限大）
@inline(__always) func jsRound(_ v: Double) -> Double { (v + 0.5).rounded(.down) }
public func clamp100(_ v: Double) -> Int { Int(max(0, min(100, jsRound(v)))) }
