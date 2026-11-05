import AVFoundation
import Foundation

// MARK: - 听力的中途兜底
//
// Android 的发音是三层：assets 离线包 -> 网络 TTS -> 系统 TTS。
// iOS 目前只有离线包这一层，命中不了就彻底没声。这个类补后两层，
// **不替代** 现有 `AudioPlayer`：调用方先试离线包，失败再找这里。
//
// 策略：
//   1. 有道词典的 dictvoice 接口拿一段 mp3，用 AVPlayer 播；
//   2. 网络失败、返回错误、或 3.5 秒还没 ready，就退到系统 TTS。
//
// 为什么系统 TTS 一开始朗读就回调 true：调用方只关心「有没有出声」，
// 不关心读到第几个词。等读完再回调会让 UI 上的「播放中」状态晚十几秒才出现。
//
// 委托对象是 weak，所以 delegate 必须由 self 长期持有（单例天然满足）。

@MainActor
final class SpeechFallback: NSObject, AVSpeechSynthesizerDelegate {

    static let shared = SpeechFallback()

    private let synthesizer = AVSpeechSynthesizer()

    private var player: AVPlayer?
    private var statusObservation: NSKeyValueObservation?
    private var timeoutWork: DispatchWorkItem?

    private var pendingText: String = ""
    private var pendingCompletion: ((Bool) -> Void)?
    /// 一次播放只允许回调一次：KVO 可能连续给出 ready / failed，
    /// 超时也可能在 ready 之后才到。没有这个闸门，调用方会收到两次结果。
    private var didResolve = false

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    deinit {
        // 单例实际上走不到这里，但保持「离开就静音」的语义，
        // 以后改成非单例也不会留下一个还在朗读的合成器。
        synthesizer.stopSpeaking(at: .immediate)
        player?.pause()
    }

    // MARK: - 对外状态

    var isSpeaking: Bool {
        if synthesizer.isSpeaking { return true }
        guard let player else { return false }
        return player.timeControlStatus == .playing
    }

    // MARK: - 播放

    /// 依次尝试网络 TTS、系统 TTS。两层都起不来时回调 false。
    func play(text: String, completion: @escaping (Bool) -> Void) {
        stop()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(false)
            return
        }

        pendingText = trimmed
        pendingCompletion = completion
        didResolve = false

        // 百分号编码失败说明这段文本连 URL 都拼不出来，直接走系统 TTS。
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://dict.youdao.com/dictvoice?audio=\(encoded)&type=2") else {
            speakWithSystem()
            return
        }

        let item = AVPlayerItem(url: url)
        let networkPlayer = AVPlayer(playerItem: item)
        player = networkPlayer

        // KVO 回调不保证在主线程，统一跳回 MainActor 再改状态。
        statusObservation = item.observe(\.status, options: [.new, .initial]) { [weak self] observed, _ in
            Task { @MainActor [weak self] in
                self?.handleStatus(observed.status)
            }
        }

        // 网络半天不 ready 时不能一直干等：听力页的「播放中」会一直转圈。
        // 3.5 秒足够一次正常请求，超时就换系统 TTS。
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.speakWithSystem()
            }
        }
        timeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: work)
    }

    func stop() {
        cancelTimeout()

        statusObservation?.invalidate()
        statusObservation = nil

        player?.pause()
        player = nil

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        pendingCompletion = nil
        pendingText = ""
        didResolve = true
    }

    // MARK: - 网络层

    private func handleStatus(_ status: AVPlayerItem.Status) {
        guard !didResolve else { return }

        switch status {
        case .readyToPlay:
            cancelTimeout()
            player?.play()
            resolve(true)

        case .failed:
            speakWithSystem()

        default:
            // .unknown：还在等，交给超时兜底。
            break
        }
    }

    // MARK: - 系统层

    private func speakWithSystem() {
        guard !didResolve else { return }

        cancelTimeout()
        statusObservation?.invalidate()
        statusObservation = nil
        player?.pause()
        player = nil

        guard !pendingText.isEmpty,
              let voice = AVSpeechSynthesisVoice(language: "en-US") else {
            // 连系统语音都拿不到（极少数精简系统会这样），如实回 false。
            resolve(false)
            return
        }

        let utterance = AVSpeechUtterance(string: pendingText)
        utterance.voice = voice
        utterance.rate = 0.48
        synthesizer.speak(utterance)

        // 开始朗读就回调，不等读完。
        resolve(true)
    }

    // MARK: - 收尾

    private func resolve(_ ok: Bool) {
        guard !didResolve else { return }
        didResolve = true

        let callback = pendingCompletion
        pendingCompletion = nil
        callback?(ok)
    }

    private func cancelTimeout() {
        timeoutWork?.cancel()
        timeoutWork = nil
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            // 读完把文本放掉：长句可能有几百个字符，没必要一直攥着。
            self?.pendingText = ""
        }
    }
}
