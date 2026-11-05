import AVFoundation

// MARK: - 单词判定音效
//
// 评分是三档反馈：1 忘了（down）、2 模糊（mid）、3/4 认识（up）。
// 音效只在「评完分」这一下响，属于高频轻反馈，所以：
//   · 播放器常驻缓存，不每次新建。`AVAudioPlayer` 的初始化要读文件头，
//     连点四次评分时新建会明显慢半拍。
//   · `warmUp()` 提前把三个播放器建好并 prepareToPlay，第一次点击就没有延迟。
//   · 会话只设一次 `.mixWithOthers`，不反复 `setActive(true)`：
//     那会把正在播的听力掐掉，用户会以为听力自己断了。
//
// 文件缺失时静默跳过。音效是锦上添花，不该因为少一个 wav 就让评分流程报错。

@MainActor
enum JudgeSfx {

    private static var players: [String: AVAudioPlayer] = [:]
    private static var didWarmUp = false

    /// 预热。App 启动或进入单词页时调一次即可，重复调用没有副作用。
    static func warmUp() {
        guard !didWarmUp else { return }
        didWarmUp = true

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.mixWithOthers])

        for name in ["down", "mid", "up"] {
            _ = player(named: name)
        }
    }

    /// 评一次分放一个音效。1 -> down，2 -> mid，3 及以上 -> up。
    static func judge(_ rating: Int) {
        let name: String
        switch rating {
        case 1:
            name = "down"
        case 2:
            name = "mid"
        case 3...:
            name = "up"
        default:
            // 0、负数、以及未来可能出现的其它值都不发声。
            return
        }

        guard let player = player(named: name) else { return }
        // 连着评同一个档时要能从头发声，而不是「已经在播，忽略」。
        player.currentTime = 0
        _ = player.play()
    }

    // MARK: - 缓存

    private static func player(named name: String) -> AVAudioPlayer? {
        if let cached = players[name] {
            return cached
        }

        let fileName = "sfx_judge_\(name)"
        let url = Bundle.main.url(forResource: fileName, withExtension: "wav", subdirectory: "Audio")
            ?? Bundle.main.url(forResource: fileName, withExtension: "wav")

        guard let url, let player = try? AVAudioPlayer(contentsOf: url) else {
            return nil
        }

        player.prepareToPlay()
        players[name] = player
        return player
    }
}
