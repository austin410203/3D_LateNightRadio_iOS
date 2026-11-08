import Foundation
import LNRCore

// 設定（全部存檔欄位共用）＋ 3 個存檔欄位（進度、統計、通話紀錄、遊玩紀錄），對應網頁的 save.js

struct Settings: Codable {
    var lang = Settings.guessLang()
    var voice = true
    var theme = "random"
    var custom = ""
    /// zh* → 繁中，ja/ko/es → 該語言，其他 → 英文（公司規則：五語、跟著手機語言）
    static func guessLang() -> String {
        let l = (Locale.preferredLanguages.first ?? "en").lowercased()
        return l.hasPrefix("zh") ? "zh" : l.hasPrefix("ja") ? "ja" : l.hasPrefix("ko") ? "ko" : l.hasPrefix("es") ? "es" : "en"
    }
}

struct Stats: Codable { var eps = 0; var crossovers = 0; var shows = 0 }

/// 一通電話的完整對話（[誰, 內容]：c 來電者、h 主持人、s 系統）
struct Transcript: Codable, Identifiable {
    var id = UUID()
    var show: Int
    var ep: Int
    var caller: String
    var name: String
    var job: String
    var phase: String
    var at: Date
    var plan: String
    var res: String?
    var lines: [[String]]
    enum CodingKeys: String, CodingKey { case show, ep, caller, name, job, phase, at, plan, res, lines }
    init(show: Int, ep: Int, caller: String, name: String, job: String, phase: String, at: Date, plan: String, res: String?, lines: [[String]]) {
        self.show = show; self.ep = ep; self.caller = caller; self.name = name; self.job = job; self.phase = phase; self.at = at; self.plan = plan; self.res = res; self.lines = lines
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        show = try c.decode(Int.self, forKey: .show); ep = try c.decode(Int.self, forKey: .ep); caller = try c.decode(String.self, forKey: .caller)
        name = try c.decode(String.self, forKey: .name); job = try c.decode(String.self, forKey: .job); phase = try c.decode(String.self, forKey: .phase)
        at = try c.decode(Date.self, forKey: .at); plan = try c.decode(String.self, forKey: .plan); res = try? c.decode(String.self, forKey: .res)
        lines = try c.decode([[String]].self, forKey: .lines)
    }
}

/// 遊玩紀錄：一集一筆
struct LogEntry: Codable, Identifiable {
    var id = UUID()
    var at: Date
    var show: Int
    var ep: Int
    var peak: Int
    var res: [[String]]      // [名字, 結果]
    enum CodingKeys: String, CodingKey { case at, show, ep, peak, res }
}

struct Slot: Codable {
    var game = "LateNightRadio"
    var progress: Show?
    var stats = Stats()
    var transcripts: [Transcript] = []
    var log: [LogEntry] = []
    var saved: Date?
}

@MainActor
final class SaveStore: ObservableObject {
    static let slots = 3
    @Published private(set) var active: Int
    @Published var slot: Slot
    private let dir: URL

    init() {
        dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("saves", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let a = UserDefaults.standard.integer(forKey: "lnr_slot")
        active = (1...Self.slots).contains(a) ? a : 1
        slot = Slot()
        slot = read(active) ?? Slot()
    }
    private func url(_ n: Int) -> URL { dir.appendingPathComponent("slot\(n).json") }
    func read(_ n: Int) -> Slot? {
        guard let d = try? Data(contentsOf: url(n)) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .millisecondsSince1970
        return try? dec.decode(Slot.self, from: d)
    }
    func encoded(_ s: Slot) -> Data? {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .millisecondsSince1970
        return try? enc.encode(s)
    }
    /// 自動存檔（每通電話、每集）
    func save() {
        slot.saved = Date()
        if slot.transcripts.count > 300 { slot.transcripts.removeFirst(slot.transcripts.count - 300) }
        if slot.log.count > 100 { slot.log.removeFirst(slot.log.count - 100) }
        if let d = encoded(slot) { try? d.write(to: url(active), options: .atomic) }
    }
    func use(_ n: Int) {
        save()
        active = n; UserDefaults.standard.set(n, forKey: "lnr_slot")
        slot = read(n) ?? Slot()
    }
    func delete(_ n: Int) {
        try? FileManager.default.removeItem(at: url(n))
        if n == active { slot = Slot() }
    }
    func exportData(_ n: Int) -> Data? { n == active ? encoded(slot) : (try? Data(contentsOf: url(n))) }
    /// 匯入 .json（網頁版匯出的格式不同：只接受 App 的格式）
    func importData(_ d: Data, into n: Int) -> Bool {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .millisecondsSince1970
        guard let s = try? dec.decode(Slot.self, from: d), s.game == "LateNightRadio" else { return false }
        try? d.write(to: url(n), options: .atomic)
        if n == active { slot = s }
        return true
    }
    func summary(_ n: Int) -> (has: Bool, ep: Int, peak: Int, saved: Date?) {
        let s = n == active ? slot : read(n)
        guard let s, let p = s.progress else { return (false, 0, 0, s?.saved) }
        return (true, p.ep, p.peak, s.saved)
    }
}

/// 設定存在 UserDefaults
enum SettingsStore {
    static func load() -> Settings {
        guard let d = UserDefaults.standard.data(forKey: "lnr_settings"), let s = try? JSONDecoder().decode(Settings.self, from: d) else { return Settings() }
        return s
    }
    static func save(_ s: Settings) { if let d = try? JSONEncoder().encode(s) { UserDefaults.standard.set(d, forKey: "lnr_settings") } }
}
