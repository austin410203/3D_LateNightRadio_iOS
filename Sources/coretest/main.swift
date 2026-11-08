import Foundation
import LNRCore

// 對照網頁：tools/export_native.mjs 用真的 JS 算出 Tests/golden.json，這裡用 Swift 算同樣的輸入，結果要一模一樣。
// 跑法：sh tools/swift.sh（Docker swift:6.2-noble）
let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let game = try GameData.load(Data(contentsOf: root.appendingPathComponent("Resources/GameData/game.json")))
let golden = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("Tests/golden.json"))) as! [String: Any]
let E = Engine(game)
var pass = 0, fail = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String) { if ok { pass += 1 } else { fail += 1; if fail <= 25 { print("  FAIL", what()) } } }

for g in golden["classify"] as! [[String: Any]] {
    let t = g["t"] as! String, r = g["r"] as! [String: Any]
    let (type, tags) = E.mock.classify(t)
    check(type == r["type"] as! String && tags == r["tags"] as! [String], "classify \(t) → \(type) \(tags) ≠ \(r)")
}
for g in golden["crisis"] as! [[String: Any]] {
    let t = g["t"] as! String
    check(E.safety.crisis(t) == g["r"] as! Bool, "crisis \(t)")
}
for g in golden["medlegal"] as! [[String: Any]] {
    let t = g["t"] as! String
    check(E.safety.medLegal(t) == g["r"] as! Bool, "medlegal \(t)")
}
for g in golden["hash"] as! [[String: Any]] {
    check(lineHash(g["c"] as! String, g["l"] as! String, g["t"] as! String) == g["r"] as! String, "hash \(g)")
}
for g in golden["reply"] as! [[String: Any]] {
    let q = g["req"] as! [String: Any], r = g["r"] as! [String: Any]
    var req = AskReq(kind: "reply", caller: q["caller"] as! String, lang: q["lang"] as! String)
    req.ep = q["ep"] as! Int; req.turn = q["turn"] as! Int; req.host = q["host"] as! String; req.closing = q["closing"] as! Bool
    req.plan = q["plan"] as! String; req.outcome = q["outcome"] as! String; req.aired = q["aired"] as! [String]
    switch E.mock.reply(req) {
    case .safety(let s): check(r["safety"] as? String == s, "reply safety \(q)")
    case .reply(let d):
        let x = r["data"] as? [String: Any] ?? [:]
        let ok = d.advice_type == x["advice_type"] as? String && d.tags == x["tags"] as? [String] && d.plan == x["plan"] as? String
            && d.caller_line == x["caller_line"] as? String && d.connects_other_caller == x["connects_other_caller"] as? Bool && d.caller_emotion == x["caller_emotion"] as? String
        check(ok, "reply \(q["caller"]!) \(q["lang"]!) ep\(q["ep"]!) closing=\(q["closing"]!) “\(q["host"]!)” → \(d.advice_type) \(d.tags) “\(d.caller_line)” ≠ \(x["advice_type"] ?? "") \(x["tags"] ?? "") “\(x["caller_line"] ?? "")”")
    default: check(false, "reply kind")
    }
}
for g in golden["follow"] as! [[String: Any]] {
    let q = g["req"] as! [String: Any], r = (g["r"] as! [String: Any])["data"] as! [String: Any]
    var req = AskReq(kind: "followup", caller: q["caller"] as! String, lang: q["lang"] as! String)
    req.outcome = q["outcome"] as! String; req.crossover = q["crossover"] as! Bool; req.plan = q["plan"] as! String
    if case .follow(let d) = E.mock.followup(req) {
        check(d.lines == r["lines"] as! [String] && d.caller_emotion == r["caller_emotion"] as! String, "follow \(q) → \(d.lines) ≠ \(r["lines"]!)")
    } else { check(false, "follow kind") }
}

// 規則的煙霧測試：一檔節目（池子抽人）、套回話、結果、下一集回電
var rng = SystemRandomNumberGenerator()
var S = Show(show: 1)
let d = E.drawCast(theme: "work", rng: &rng)
E.addNight(&S, NewNight(id: d.night, cast: d.cast, pair: E.nights.first { $0.id == d.night }!.pair, summary: nil))
S.end = E.showEnd(S)
check(S.cast.count == 3 && S.end == 120, "draw cast \(S.cast)")
let id = S.cast[0]
S.callers[id]!.status = "onair"
for _ in 0..<4 {
    let dlt = E.applyReply(&S, id, ReplyData(advice_type: "concrete_step", tags: ["write_it_down"], connects_other_caller: false, plan: "寫下來", caller_emotion: "determined", caller_line: "…"), hostText: "寫下來")
    check(dlt.trust != 0, "delta")
}
S.callers[id]!.status = "done"; S.callers[id]!.outcome = E.outcomeOf(S.callers[id]!).o
let res = E.endEpisode(&S)
check(S.ended && res.count == 1, "end episode \(res)")
E.beginNext(&S)
check(S.ep == 2 && S.cast == [id] && S.callers[id]?.phase == "callback", "next episode")
check(E.portrait("azhe") == "p05" && E.portrait("n1a").hasPrefix("p"), "portrait")
check(E.t("es", "send") == "Enviar" && E.t("zh", "continueN", ["n": "3"]) == "繼續：第 3 集", "i18n")

print("\(pass) passed, \(fail) failed")
if fail > 0 { exit(1) }
print("CORE TEST PASS")
