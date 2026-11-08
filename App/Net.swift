import Foundation
import LNRCore

/// 跟網頁同一個 Worker（radio.emptyoffice.app）：Haiku 對話、即時生成來電者、語音。
/// X-EO-App 標頭讓 App 通過內部測試密碼鎖（worker/index.js APP_KEY）；金鑰都在 Worker，App 裡沒有。
final class Net: @unchecked Sendable {
    static let base = URL(string: "https://radio.emptyoffice.app/")!
    static let appKey = "lnr-ios-7f3a"
    let pid: String
    var forceMock = false

    init() {
        if let p = UserDefaults.standard.string(forKey: "lnr_pid") { pid = p }
        else { let p = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(24); pid = String(p); UserDefaults.standard.set(pid, forKey: "lnr_pid") }
    }

    private func request(_ path: String, body: [String: Any]?, timeout: TimeInterval) -> URLRequest {
        var r = URLRequest(url: Self.base.appendingPathComponent(path), timeoutInterval: timeout)
        r.setValue(Self.appKey, forHTTPHeaderField: "X-EO-App")
        if let body {
            r.httpMethod = "POST"
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var b = body; b["pid"] = pid
            r.httpBody = try? JSONSerialization.data(withJSONObject: b)
        }
        return r
    }
    private func json(_ path: String, _ body: [String: Any]?, timeout: TimeInterval) async -> [String: Any]? {
        guard let (d, _) = try? await URLSession.shared.data(for: request(path, body: body, timeout: timeout)) else { return nil }
        return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
    }

    struct Health { var live = false; var tts = false }
    func health() async -> Health {
        if forceMock { return Health() }
        guard let j = await json("api/health", nil, timeout: 8) else { return Health() }
        return Health(live: j["live"] as? Bool ?? false, tts: j["tts"] as? Bool ?? false)
    }

    /// 每集開播：Haiku 生成三位新來電者（一對有隱藏關聯＋一位單獨）
    func night(lang: String, avoid: [String], theme: String, custom: String?) async -> NewNight? {
        var b: [String: Any] = ["lang": lang, "avoid": avoid, "theme": theme]
        if let custom { b["custom"] = custom }
        guard let j = await json("api/night", b, timeout: 45), j["ok"] as? Bool == true,
              let n = j["night"] as? [String: Any], let id = n["id"] as? String,
              let pair = n["pair"] as? [String], let solo = n["solo"] as? [String],
              let cs = j["callers"], let cd = try? JSONSerialization.data(withJSONObject: cs),
              let callers = try? JSONDecoder().decode([CallerData].self, from: cd) else { return nil }
        let sealed = j["sealed"] as? [String: String] ?? [:]
        return NewNight(id: id, cast: (pair + solo).shuffled(), pair: pair, summary: n["summary"] as? [String: String], live: callers, sealed: sealed)
    }

    enum Answer { case reply(ReplyData), follow(FollowData), safety(String), cap, fail }
    /// /api/llm；失敗就回 .fail（呼叫的地方改用離線劇本）
    func llm(_ r: AskReq) async -> Answer {
        guard let j = await json("api/llm", r.json, timeout: 15) else { return .fail }
        if j["ok"] as? Bool != true { return (j["error"] as? String ?? "").hasPrefix("cap_") ? .cap : .fail }
        if let s = j["safety"] as? String { return .safety(s) }
        guard let d = j["data"], let data = try? JSONSerialization.data(withJSONObject: d) else { return .fail }
        if r.kind == "followup" {
            if let f = try? JSONDecoder().decode(FollowData.self, from: data), !f.lines.isEmpty { return .follow(f) }
        } else if let x = try? JSONDecoder().decode(ReplyData.self, from: data), !x.caller_line.trimmingCharacters(in: .whitespaces).isEmpty { return .reply(x) }
        return .fail
    }

    /// 即時台詞的語音（Google Cloud）：8 秒逾時，太慢就讓呼叫的地方改用手機語音
    func tts(caller: CallerData, lang: String, text: String) async -> (Data, String)? {
        let b: [String: Any] = ["caller": caller.id, "gender": caller.sex, "ageBand": caller.band, "lang": lang, "text": text]
        guard let (d, resp) = try? await URLSession.shared.data(for: request("api/tts", body: b, timeout: 8)),
              let h = resp as? HTTPURLResponse, h.statusCode == 200 else { return nil }
        return (d, h.value(forHTTPHeaderField: "X-TTS-Engine") ?? "")
    }

    /// 預錄的人聲（網頁 public/audio/<hash>.mp3），下載一次存在快取
    func prerecorded(_ hash: String) async -> Data? {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("audio", isDirectory: true)
        let f = dir.appendingPathComponent("\(hash).mp3")
        if let d = try? Data(contentsOf: f) { return d }
        guard let (d, resp) = try? await URLSession.shared.data(for: request("audio/\(hash).mp3", body: nil, timeout: 8)),
              (resp as? HTTPURLResponse)?.statusCode == 200, d.count > 200 else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? d.write(to: f)
        return d
    }
}
