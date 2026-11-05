import AVFoundation
import CryptoKit
import Foundation
import Observation

// ════════════════════════════════════════════════════════════════════
//  离线发音
// ════════════════════════════════════════════════════════════════════
//
//  音频包随 App 打包在 `Audio/` 下，索引是 `Audio/index.json`。
//
//  查找方式：对文本做**规范化**后取 SHA-1 的前 6 位十六进制。
//  规范化规则必须与生成脚本完全一致：
//      小写 → 把连续的非 [a-z0-9] 字符替换成一个空格 → 去掉首尾空格
//  只要有一处不同，key 就对不上，表现是「一条都命中不了」。
//
//  为什么要核验原文：key 只有 24 bit，三千多条里**真的会撞**
//  （实测 fade / immense 撞了一组）。撞了会让「点 fade 念出 immense」——
//  放错音等于在教错发音，比不出声严重得多。所以命中后还要比一遍原文，
//  不符就当作没命中，静默失败。
//
//  播放器**不用 delegate**：`AVAudioPlayerDelegate` 的方法是非隔离的，
//  在 @MainActor 类里实现它要处理跨隔离调用。这里改用每 200ms 轮询一次
//  `isPlaying`，逻辑更短，也不会有并发标注的坑。

@MainActor
@Observable
final class AudioPlayer {

    /// 播放队列里的一项
    struct Item: Identifiable, Hashable {
        let id: String
        let text: String

        init(id: String, text: String) {
            self.id = id
            self.text = text
        }
    }

    // MARK: - 对外状态

    /// 当前正在播的条目 id（没有就是 nil）
    var nowPlayingId: String?
    /// 是否正在出声
    var isPlaying: Bool = false
    /// 播放倍速（0.5 … 2.0），调一次全局生效
    var playbackRate: Float = 1.0
    /// 播放位置（秒）。播放中由轮询任务每 200ms 写一次，界面靠它刷新进度条。
    ///
    /// 为什么不直接暴露 `AVAudioPlayer.currentTime`：它不是 KVO 友好的属性，
    /// 视图读它读不出变化。轮询任务顺手写进这个可观察状态，SwiftUI 才会重绘。
    var currentTime: Double = 0
    /// 当前音频总时长（秒）。没有加载音频时为 0。
    var duration: Double = 0
    /// 连续播放：一条播完自动接下一句（听力页的「连续播放」开关）。
    /// 播到最后一句就停住，不循环 —— 循环会让「听到第几句了」变得没有意义。
    var continuous: Bool = true
    /// 索引里有多少条音频（0 表示音频包不可用）
    var indexedCount: Int = 0
    /// 播完一条后的回调（播队列时用来推进「下一句」）
    var onFinish: ((Item) -> Void)?

    // MARK: - 内部

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var index: [String: Entry] = [:]
    @ObservationIgnored private var queue: [Item] = []
    @ObservationIgnored private var queueIndex: Int = 0
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var didLoadIndex = false

    /// index.json 里的一条
    private struct Entry: Decodable {
        var f: String = ""
        var t: String = ""
        var c: String = ""
        var d: Int = 0
        var b: Int = 0

        enum CodingKeys: String, CodingKey {
            case f, t, c, d, b
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            f = try container.decodeIfPresent(String.self, forKey: .f) ?? ""
            t = try container.decodeIfPresent(String.self, forKey: .t) ?? ""
            c = try container.decodeIfPresent(String.self, forKey: .c) ?? ""
            d = try container.decodeIfPresent(Int.self, forKey: .d) ?? 0
            b = try container.decodeIfPresent(Int.self, forKey: .b) ?? 0
        }
    }

    private struct AudioIndex: Decodable {
        var items: [String: Entry] = [:]

        enum CodingKeys: String, CodingKey {
            case items
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            items = try container.decodeIfPresent([String: Entry].self, forKey: .items) ?? [:]
        }
    }

    // MARK: - 索引

    private func ensureIndex() {
        guard !didLoadIndex else { return }
        didLoadIndex = true

        guard let url = AudioPlayer.indexURL() else {
            indexedCount = 0
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let parsed = try JSONDecoder().decode(AudioIndex.self, from: data)
            index = parsed.items
            indexedCount = parsed.items.count
        } catch {
            index = [:]
            indexedCount = 0
        }
    }

    private static func indexURL() -> URL? {
        if let url = audioURL(fileName: "index.json") { return url }
        return nil
    }

    private static func audioURL(fileName: String) -> URL? {
        let ns = fileName as NSString
        let name = ns.deletingPathExtension
        let ext = ns.pathExtension

        if !name.isEmpty, !ext.isEmpty {
            if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Audio") {
                return url
            }
            if let url = Bundle.main.url(forResource: name, withExtension: ext) {
                return url
            }
        }
        if let url = Bundle.main.url(forResource: fileName, withExtension: nil, subdirectory: "Audio") {
            return url
        }
        return Bundle.main.url(forResource: fileName, withExtension: nil)
    }

    // MARK: - 文本 → key

    /// 规范化：小写 → 非 [a-z0-9] 连续段替换成单个空格 → 去首尾空格
    static func normalize(_ text: String) -> String {
        let lower = text.lowercased()
        var out = ""
        out.reserveCapacity(lower.count)
        var pendingSpace = false

        for ch in lower {
            // isASCII + isLetter/isNumber ⇒ 只可能是 a-z / 0-9
            let isWordChar = ch.isASCII && (ch.isLetter || ch.isNumber)
            if isWordChar {
                if pendingSpace && !out.isEmpty {
                    out.append(" ")
                }
                pendingSpace = false
                out.append(ch)
            } else {
                pendingSpace = true
            }
        }
        return out
    }

    /// 文本 → 6 位十六进制 key（规范化后为空时返回 nil）
    static func key(of text: String) -> String? {
        let normalized = normalize(text)
        if normalized.isEmpty { return nil }
        guard let data = normalized.data(using: .utf8) else { return nil }
        let digest = Insecure.SHA1.hash(data: data)
        let bytes = Array(digest)
        guard bytes.count >= 3 else { return nil }
        var hex = ""
        for i in 0..<3 {
            hex += String(format: "%02x", bytes[i])
        }
        return hex
    }

    /// 带原文核验的查表
    private func entry(for text: String) -> Entry? {
        ensureIndex()
        guard let k = AudioPlayer.key(of: text), let found = index[k] else { return nil }
        if !found.t.isEmpty, AudioPlayer.normalize(found.t) != AudioPlayer.normalize(text) {
            return nil
        }
        return found
    }

    // MARK: - 查询

    /// 这条文本在本地有音频吗
    func hasAudio(for text: String) -> Bool {
        entry(for: text) != nil
    }

    /// 本地音频路径
    func url(for text: String) -> URL? {
        guard let found = entry(for: text), !found.f.isEmpty else { return nil }
        return AudioPlayer.audioURL(fileName: found.f)
    }

    /// 音频时长（毫秒）
    func durationMs(for text: String) -> Int? {
        guard let found = entry(for: text) else { return nil }
        return found.d
    }

    // MARK: - 播放（单条）

    /// 播一句话。找不到音频 / 解码失败时返回 false，**不抛异常、不崩**。
    @discardableResult
    func play(text: String, id: String? = nil) -> Bool {
        guard let fileURL = url(for: text) else { return false }
        return play(fileURL: fileURL, id: id ?? AudioPlayer.key(of: text) ?? text)
    }

    @discardableResult
    private func play(fileURL: URL, id: String) -> Bool {
        stop()
        activateSession()

        do {
            let p = try AVAudioPlayer(contentsOf: fileURL)
            p.enableRate = true
            p.rate = playbackRate
            p.prepareToPlay()
            let started = p.play()
            player = p
            nowPlayingId = id
            isPlaying = started
            currentTime = 0
            duration = p.duration
            if started {
                startPolling()
            }
            return started
        } catch {
            player = nil
            nowPlayingId = nil
            isPlaying = false
            currentTime = 0
            duration = 0
            return false
        }
    }

    /// 让声音走「播放」通道。
    ///
    /// 不设这一步的话，iPhone 侧边静音开关一拨，听力就整段没声音 ——
    /// 用户只会以为 App 坏了。`.spokenAudio` 是给口语/朗读内容准备的模式，
    /// 它不做音乐那种响度归一化，人声更清楚。
    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }

    /// 播放 / 暂停 切换
    func toggle() {
        guard let p = player else { return }
        if p.isPlaying {
            p.pause()
            isPlaying = false
            stopPolling()
        } else {
            p.rate = playbackRate
            let started = p.play()
            isPlaying = started
            if started { startPolling() }
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopPolling()
    }

    func stop() {
        stopPolling()
        player?.stop()
        player = nil
        isPlaying = false
        nowPlayingId = nil
        currentTime = 0
        duration = 0
    }

    /// 跳到第 `seconds` 秒。
    ///
    /// 暂停状态下也要生效（`AVAudioPlayer.currentTime` 是赋值式的），
    /// 否则「拖到一半松手」会跳回去 —— 用户会以为进度条坏了。
    func seek(to seconds: Double) {
        guard let p = player else { return }
        let total = max(p.duration, 0)
        let target = min(max(seconds, 0), total)
        p.currentTime = target
        currentTime = target
    }

    /// 调倍速。`enableRate` 必须为 true，且只在播放中生效
    /// （暂停时改 rate 不会让它自己响起来）。
    func setRate(_ rate: Float) {
        let clamped = min(max(rate, 0.5), 2.0)
        playbackRate = clamped
        if let p = player, p.isPlaying {
            p.rate = clamped
        }
    }

    // MARK: - 播放（队列）

    /// 装一份列表并开始播第 `startAt` 条
    @discardableResult
    func playQueue(_ items: [Item], startAt: Int = 0) -> Bool {
        guard !items.isEmpty else { return false }
        queue = items
        queueIndex = min(max(startAt, 0), items.count - 1)
        return playCurrent()
    }

    /// 当前这条在队列里的位置（没有队列时为 nil）
    var queuePosition: (index: Int, total: Int)? {
        guard !queue.isEmpty else { return nil }
        return (index: queueIndex, total: queue.count)
    }

    @discardableResult
    func playCurrent() -> Bool {
        guard queueIndex >= 0, queueIndex < queue.count else { return false }
        let item = queue[queueIndex]
        guard let fileURL = url(for: item.text) else {
            isPlaying = false
            nowPlayingId = item.id
            return false
        }
        return play(fileURL: fileURL, id: item.id)
    }

    /// 下一句。已经是最后一句时停住并返回 false。
    @discardableResult
    func next() -> Bool {
        guard !queue.isEmpty, queueIndex + 1 < queue.count else { return false }
        queueIndex += 1
        return playCurrent()
    }

    /// 上一句。已经是第一句时返回 false。
    @discardableResult
    func previous() -> Bool {
        guard !queue.isEmpty, queueIndex - 1 >= 0 else { return false }
        queueIndex -= 1
        return playCurrent()
    }

    // MARK: - 播完检测

    private func startPolling() {
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard let self else { return }
                guard self.isPlaying else { return }
                self.pollOnce()
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func pollOnce() {
        guard let p = player else {
            isPlaying = false
            stopPolling()
            return
        }

        // 还在响 → 只刷新进度，不动别的
        if p.isPlaying {
            currentTime = p.currentTime
            if p.duration > 0 {
                duration = p.duration
            }
            return
        }

        // 轮询只在「我们认为正在播」时运行 —— 主动暂停 / 停止都会先取消轮询。
        // 所以能走到这里，说明是自然播完（或被系统打断），两种情况都该结束本条。
        // 不拿 currentTime 和 duration 比：播完后 currentTime 会被系统归零，
        // 用「到没到尾巴」判断反而会漏掉结束事件。
        isPlaying = false
        stopPolling()

        guard let id = nowPlayingId else { return }
        if let item = queue.first(where: { $0.id == id }) {
            onFinish?(item)
        }

        // 连续播放：自动接下一句。最后一句播完就停在这儿，
        // 让「今天听到第几句」停在一个确定的位置上。
        if continuous, queueIndex + 1 < queue.count {
            queueIndex += 1
            playCurrent()
        }
    }
}
