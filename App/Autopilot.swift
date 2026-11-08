import SwiftUI
import UIKit
import LNRCore

/// CI 用的自動試玩（-autotest tour）：離線劇本跑完一集＋第二集回電，每個畫面截圖存到 Documents/shots，最後寫 done.txt。
@MainActor
struct Autopilot {
    let model: GameModel
    static let lines = [
        "zh": ["你可以先把想說的重點寫下來，再找時間當面聊聊。", "辛苦了，這真的不容易。", "要不要先試一小步，明天就去？"],
        "en": ["You could write down what you want to say first, then talk to them face to face.", "That must be hard. I understand.", "How about one small step tomorrow?"],
        "ja": ["まず言いたいことを書き出して、会って話してみたら？", "大変でしたね、わかります。", "明日、小さな一歩からどう？"],
        "ko": ["먼저 하고 싶은 말을 적어 보고, 직접 만나서 얘기해 봐요.", "힘들었겠어요, 이해해요.", "내일 작은 한 걸음부터 어때요?"],
        "es": ["Podrías escribir primero lo que quieres decir y luego hablar con él en persona.", "Te entiendo, debe ser difícil.", "¿Qué tal si das un paso pequeño mañana?"],
    ]

    func run() {
        Task { @MainActor in
            let m = model
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("shots", isDirectory: true)
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var k = 0
            @MainActor func shot(_ name: String) async {
                try? await Task.sleep(nanoseconds: 900_000_000)
                k += 1
                guard let w = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return }
                let img = UIGraphicsImageRenderer(bounds: w.bounds).image { _ in w.drawHierarchy(in: w.bounds, afterScreenUpdates: true) }
                try? img.pngData()?.write(to: dir.appendingPathComponent(String(format: "%02d_%@.png", k, name)))
                print("AUTOPILOT shot \(name)")
            }
            @MainActor func idle() async {
                for _ in 0..<200 {
                    let waiting = m.busy || m.loading
                    if !waiting { break }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
            let host = Self.lines[m.lang] ?? Self.lines["en"]!

            // 每次從乾淨的存檔開始
            m.saves.delete(m.saves.active); m.S = nil; m.settings.theme = "random"
            await shot("title")
            m.settings.theme = "custom"; m.setCustom(m.lang == "zh" ? "第一次養貓" : "first cat")
            await shot("title_custom")
            m.settings.theme = "random"
            await m.start(); await idle()
            await shot("epcard")
            m.goLive()
            await shot("board")
            // 第一集：三通電話都接完（第一通示範聽眾簡訊）
            var first = true
            while let id = m.S?.cast.first(where: { m.S?.callers[$0]?.status == "waiting" }) {
                await m.pickUp(id); await idle()
                if first { await shot("call_opening") }
                for i in 0..<4 {
                    guard m.cur == id else { break }
                    m.input = host[i % host.count]
                    await m.send(); await idle()
                    if first && i == 0 { await shot("call_reply"); if m.sms != nil { await shot("sms"); m.readSms() } }
                    if first && i == 1 { m.logOpen = true; await shot("call_log_open"); m.logOpen = false }
                }
                first = false
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            if m.screen == .live { m.endEpisode() }
            await shot("summary")
            m.sheet = .history; await shot("history"); m.sheet = nil
            try? await Task.sleep(nanoseconds: 500_000_000)
            m.sheet = .settings; await shot("settings"); m.sheet = nil
            try? await Task.sleep(nanoseconds: 500_000_000)
            m.sheet = .help(fromStop: false); await shot("help"); m.sheet = nil
            try? await Task.sleep(nanoseconds: 500_000_000)
            // 第二集：上週的人回電
            await m.nextEpisode(); await idle()
            await shot("ep2_card")
            m.goLive()
            await shot("ep2_board")
            if let id = m.S?.cast.first(where: { m.S?.callers[$0]?.phase == "callback" }) {
                await m.pickUp(id); await idle()
                await shot("ep2_callback")
            }
            // 危機字眼：停下電話、打開求助資訊
            if m.cur != nil {
                m.input = ["zh": "我想死", "en": "I want to die", "ja": "死にたい", "ko": "죽고 싶어", "es": "me quiero morir"][m.lang] ?? "I want to die"
                await m.send(); await idle()
                await shot("safety_help")
                m.sheet = nil
            }
            try? "ok".write(to: dir.appendingPathComponent("done.txt"), atomically: true, encoding: .utf8)
            print("AUTOPILOT done")
        }
    }
}
