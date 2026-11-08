import AVFoundation
import LNRCore

/// 來電者的聲音＋音效＋播歌（voice.js 的原生版）
/// - 台詞一律排隊：上一句真的播完才播下一句（公司手冊 llm-games §3）；只有玩家操作才 stop()
/// - 聲音來源：預錄 mp3 → Worker /api/tts（Google 神經語音）→ 手機內建語音
/// - 預錄／神經語音經過輕微電話音色（高通 190 Hz、低通 5.2 kHz、1.9 kHz +2.5 dB）＋很小聲的線路雜訊
@MainActor
final class VoiceOut: NSObject, AVSpeechSynthesizerDelegate {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 3)
    private let hiss = AVAudioPlayerNode()
    private let sfx = AVAudioPlayerNode()
    private let music = AVAudioPlayerNode()
    private let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    private let synth = AVSpeechSynthesizer()
    private var synthDone: CheckedContinuation<Void, Never>?
    private var token = 0
    private var queue: Task<Void, Never>?
    private var started = false
    var voiceOn = true
    var apiTts = false
    var manifest: Set<String> = []
    weak var net: Net?
    private(set) var speaking = false

    override init() {
        super.init()
        synth.delegate = self
    }

    func setup() {
        guard !started else { return }
        started = true
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try? s.setActive(true)
        let b = eq.bands
        b[0].filterType = .highPass; b[0].frequency = 190; b[0].bypass = false
        b[1].filterType = .lowPass; b[1].frequency = 5200; b[1].bypass = false
        b[2].filterType = .parametric; b[2].frequency = 1900; b[2].gain = 2.5; b[2].bandwidth = 1.1; b[2].bypass = false
        for n in [player, hiss, sfx, music] as [AVAudioNode] { engine.attach(n) }
        engine.attach(eq)
        engine.connect(player, to: eq, format: fmt)
        engine.connect(eq, to: engine.mainMixerNode, format: fmt)
        engine.connect(hiss, to: engine.mainMixerNode, format: fmt)
        engine.connect(sfx, to: engine.mainMixerNode, format: fmt)
        engine.connect(music, to: engine.mainMixerNode, format: fmt)
        hiss.volume = 0
        try? engine.start()
        // 電話線雜訊：粉紅雜訊（低通）循環播放，來電者說話時才打開
        let n = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 88200)!
        n.frameLength = 88200
        var l: Float = 0
        let p = n.floatChannelData![0]
        for i in 0..<88200 { l = 0.97 * l + 0.03 * Float.random(in: -1...1); p[i] = l * 3 * 0.6 }
        hiss.scheduleBuffer(n, at: nil, options: .loops)
        hiss.play()
    }
    private func ensure() { setup(); if !engine.isRunning { try? engine.start() } }
    private func line(_ on: Bool) { speaking = on; hiss.volume = on ? 0.03 : 0 }

    // ── 說一句話（排隊）──
    func speak(_ text: String, _ c: CallerData, _ lang: String) async {
        if !voiceOn { try? await Task.sleep(nanoseconds: 350_000_000); return }
        let my = token
        let prev = queue
        let t = Task { @MainActor in
            await prev?.value
            if my != self.token { return }
            await self.speakNow(text, c, lang, my)
        }
        queue = t
        await t.value
    }
    /// 停掉正在說的、丟掉還沒輪到的（只有玩家操作會叫）
    func stop() {
        token += 1
        player.stop()
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        synthDone?.resume(); synthDone = nil
        line(false)
    }

    private func speakNow(_ text: String, _ c: CallerData, _ lang: String, _ my: Int) async {
        ensure()
        var got: (Data, String)?
        let h = lineHash(c.id, lang, text)
        if manifest.contains(h), let d = await net?.prerecorded(h) { got = (d, "mp3") }
        else if apiTts, let r = await net?.tts(caller: c, lang: lang, text: text) { got = r }
        if my != token { return }
        // MeloTTS 只有女聲（網頁用變聲處理）：男性來電者改用手機語音
        if let (d, eng) = got, !(eng == "melotts" && c.sex == "male"), let buf = decode(d) {
            line(true); await play(buf); if my == token { line(false) }
            return
        }
        if my != token { return }
        await systemSpeak(text, c, lang)
    }

    private final class Once { var done = false }
    private func play(_ buf: AVAudioPCMBuffer) async {
        let once = Once()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let finish = { DispatchQueue.main.async { if !once.done { once.done = true; cont.resume() } } }
            player.scheduleBuffer(buf, at: nil, options: .interrupts, completionCallbackType: .dataPlayedBack) { _ in finish() }
            player.play()
            // 保險：完成回呼沒來也不會卡住佇列（音檔長度＋1.5 秒）
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(buf.frameLength) / fmt.sampleRate + 1.5) { finish() }
        }
    }

    /// mp3／wav → 44.1 kHz 單聲道
    private func decode(_ d: Data) -> AVAudioPCMBuffer? {
        let ext = d.prefix(4) == Data("RIFF".utf8) ? "wav" : "mp3"
        let f = FileManager.default.temporaryDirectory.appendingPathComponent("lnr_\(UUID().uuidString).\(ext)")
        defer { try? FileManager.default.removeItem(at: f) }
        guard (try? d.write(to: f)) != nil, let file = try? AVAudioFile(forReading: f) else { return nil }
        let inF = file.processingFormat
        guard let src = AVAudioPCMBuffer(pcmFormat: inF, frameCapacity: AVAudioFrameCount(file.length)), (try? file.read(into: src)) != nil else { return nil }
        if inF.sampleRate == fmt.sampleRate && inF.channelCount == 1 && inF.commonFormat == .pcmFormatFloat32 { return src }
        guard let conv = AVAudioConverter(from: inF, to: fmt) else { return nil }
        let cap = AVAudioFrameCount(Double(src.frameLength) * fmt.sampleRate / inF.sampleRate) + 4096
        guard let out = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: cap) else { return nil }
        var fed = false
        var err: NSError?
        conv.convert(to: out, error: &err) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true; status.pointee = .haveData; return src
        }
        return err == nil && out.frameLength > 0 ? out : nil
    }

    // ── 手機內建語音（最後的備援）──
    static let locale = ["zh": "zh-TW", "en": "en-US", "ja": "ja-JP", "ko": "ko-KR", "es": "es-MX"]
    private func pickVoice(_ lang: String, _ gender: String) -> AVSpeechSynthesisVoice? {
        let loc = Self.locale[lang] ?? "en-US"
        var vs = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == loc }
        if vs.isEmpty { vs = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(String(loc.prefix(2))) } }
        let g: AVSpeechSynthesisVoiceGender = gender == "male" ? .male : .female
        let rank = { (v: AVSpeechSynthesisVoice) in (v.gender == g ? 10 : 0) + (v.quality == .premium ? 2 : v.quality == .enhanced ? 1 : 0) }
        return vs.max { rank($0) < rank($1) } ?? AVSpeechSynthesisVoice(language: loc)
    }
    private func systemSpeak(_ text: String, _ c: CallerData, _ lang: String) async {
        let u = AVSpeechUtterance(string: text)
        u.voice = pickVoice(lang, c.sex)
        u.pitchMultiplier = Float(min(2, max(0.5, c.voice?.pitch ?? 1)))
        u.rate = AVSpeechUtteranceDefaultSpeechRate * Float(c.voice?.rate ?? 1)
        line(true)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            synthDone = cont
            synth.speak(u)
            let guardSec = 6 + Double(text.count) * 0.6
            DispatchQueue.main.asyncAfter(deadline: .now() + guardSec) { [weak self] in self?.finishSynth(u) }
        }
        line(false)
    }
    private func finishSynth(_ u: AVSpeechUtterance?) { synthDone?.resume(); synthDone = nil }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { Task { @MainActor in self.finishSynth(u) } }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { Task { @MainActor in self.finishSynth(u) } }

    // ── 音效（合成）──
    private enum Wave { case sine, triangle, square }
    private func tones(_ list: [(Double, Double, Double, Float, Wave)], total: Double) -> AVAudioPCMBuffer {
        let sr = fmt.sampleRate, n = AVAudioFrameCount(total * sr)
        let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: n)!
        b.frameLength = n
        let p = b.floatChannelData![0]
        for i in 0..<Int(n) { p[i] = 0 }
        for (f, t0, dur, vol, w) in list {
            let s0 = Int(t0 * sr), len = Int(dur * sr)
            for k in 0..<len where s0 + k < Int(n) {
                let t = Double(k) / sr
                let ph = (t * f).truncatingRemainder(dividingBy: 1)
                let v: Double
                switch w { case .sine: v = sin(2 * .pi * ph); case .triangle: v = 4 * abs(ph - 0.5) - 1; case .square: v = ph < 0.5 ? 1 : -1 }
                let env = min(1, t / 0.015, max(0, (dur - t) / 0.03))
                p[s0 + k] += Float(v * env) * vol
            }
        }
        return b
    }
    private func blip(_ b: AVAudioPCMBuffer) { ensure(); sfx.scheduleBuffer(b, at: nil); sfx.play() }
    func ring() { blip(tones((0..<2).flatMap { i in [(880, Double(i) * 0.5, 0.35, 0.05, .sine), (1320, Double(i) * 0.5, 0.35, 0.03, .sine)] }, total: 1.0)) }
    func pickup() { blip(tones([(160, 0, 0.05, 0.2, .square), (2400, 0.04, 0.03, 0.05, .sine)], total: 0.12)) }
    func hangup() { blip(tones((0..<3).map { i in (480, 0.1 + Double(i) * 0.32, 0.2, 0.07, .square) }, total: 1.1)) }
    func chime() { blip(tones([523, 659, 784].enumerated().map { (i, f) in (Double(f), Double(i) * 0.12, 0.5, 0.06, .triangle) }, total: 0.9)) }

    // ── 播歌：程式合成的 lo-fi 小曲（約 20 秒，跟網頁同一套和弦）──
    private var songDone: CheckedContinuation<Void, Never>?
    func playSong(seconds: Double = 20) async {
        ensure()
        let beat = 60.0 / 72, prog = [[53, 57, 60, 64], [52, 55, 59, 62], [50, 53, 57, 60], [48, 52, 55, 59]]
        let mf = { (m: Int) in 440 * pow(2, Double(m - 69) / 12) }
        let penta = [72, 74, 76, 79, 81, 84]
        var notes: [(Double, Double, Double, Float, Wave)] = []
        var k = 0, bar = 0
        while Double(bar) * 4 * beat < seconds - 1 {
            let ch = prog[bar % 4], tb = Double(bar) * 4 * beat
            for m in ch { notes.append((mf(m), tb, 4 * beat - 0.05, 0.025, .triangle)) }
            notes.append((mf(ch[0] - 12), tb, 1.5 * beat, 0.07, .sine)); notes.append((mf(ch[0] - 12), tb + 2 * beat, 1.2 * beat, 0.05, .sine))
            for s in 0..<4 {
                if (bar * 7 + s * 3 + k) % 5 < 3 { notes.append((mf(penta[(bar * 3 + s * 2 + (k % 3)) % penta.count]), tb + Double(s) * beat + Double(s % 2) * 0.18, beat * 0.7, 0.035, .sine)) }
                k += 1
            }
            bar += 1
        }
        let b = tones(notes, total: seconds)
        // 低通 1.8 kHz＋淡入淡出
        let p = b.floatChannelData![0], n = Int(b.frameLength), sr = fmt.sampleRate
        let a = Float(1 - exp(-2 * Double.pi * 1800 / sr))
        var y: Float = 0
        for i in 0..<n {
            y += a * (p[i] - y)
            let t = Double(i) / sr
            p[i] = y * Float(min(1, t / 1.5, max(0, (seconds - t) / 2))) * 0.9
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            songDone = cont
            music.scheduleBuffer(b, at: nil, options: .interrupts) { [weak self] in DispatchQueue.main.async { self?.endSong() } }
            music.play()
        }
    }
    private func endSong() { songDone?.resume(); songDone = nil }
    func skipSong() { music.stop(); endSong() }
}
