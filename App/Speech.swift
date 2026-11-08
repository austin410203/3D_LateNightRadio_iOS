import AVFoundation
import Speech

/// 主持人按住麥克風說話（SFSpeechRecognizer）。支援的話在 iPhone 上辨識（不經過網路）；
/// 辨識結果放進輸入框，玩家改完再按送出（老闆 2026-10-31：不要說完自動送出）。音訊不會傳到我們的伺服器。
@MainActor
final class SpeechIn {
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var text = ""
    private var finalCont: CheckedContinuation<Void, Never>?
    private(set) var listening = false

    enum Status { case ok, denied, unavailable }

    func authorize() async -> Status {
        let s = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard s == .authorized else { return .denied }
        let mic = await AVAudioApplication.requestRecordPermission()
        return mic ? .ok : .denied
    }

    func onDevice(_ lang: String) -> Bool { SFSpeechRecognizer(locale: Self.locale(lang))?.supportsOnDeviceRecognition ?? false }
    static func locale(_ lang: String) -> Locale { Locale(identifier: VoiceOut.locale[lang] ?? "en-US") }

    func start(lang: String, onText: @escaping (String) -> Void) -> Bool {
        guard !listening, let rec = SFSpeechRecognizer(locale: Self.locale(lang)), rec.isAvailable else { return false }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if rec.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        req.addsPunctuation = true
        let input = engine.inputNode
        let f = input.outputFormat(forBus: 0)
        guard f.sampleRate > 0 else { return false }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: f) { buf, _ in req.append(buf) }
        engine.prepare()
        guard (try? engine.start()) != nil else { input.removeTap(onBus: 0); return false }
        text = ""; request = req; listening = true
        task = rec.recognitionTask(with: req) { [weak self] result, error in
            let s = result?.bestTranscription.formattedString
            let done = error != nil || (result?.isFinal ?? false)
            Task { @MainActor in
                guard let self else { return }
                if let s, !s.isEmpty { self.text = s; onText(s) }
                if done { self.finalCont?.resume(); self.finalCont = nil }
            }
        }
        return true
    }

    /// 放開麥克風：等最後結果（最多 1.5 秒），回傳辨識到的字
    func stop() async -> String {
        guard listening else { return text }
        listening = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            finalCont = c
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.finalCont?.resume(); self?.finalCont = nil }
        }
        task?.cancel(); task = nil; request = nil
        try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        return text
    }
}
