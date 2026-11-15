import AVFoundation

// MARK: - 背单词提示音
//
// 木鱼声：一响 = 认识，两响 = 忘了 / 模糊（评分 1、2 都是两响，3 及以上一响）。
//
// 为什么是木鱼：背单词是连续几十次的高频动作，叮咚这类带明确音高的铃声
// 重复二十遍会变成噪音；木鱼是噪音型短瞬态，没有旋律记忆点，响一百次也不烦。
// 单响和双响的区别在节奏（170ms / 235ms）而不在音高，闭着眼也能分出对错。
// 这三条理由来自 Android 版 `audio/WordTick.kt`，两端必须是同一副声音。
//
// 下面是播放器的部分，仍然成立：
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

        for name in ["tick_known", "tick_unknown"] {
            _ = player(named: name)
        }
    }

    /// 评一次分敲一下木鱼。1、2 -> 两响，3 及以上 -> 一响。
    static func judge(_ rating: Int) {
        let name: String
        switch rating {
        case 1, 2:
            name = "tick_unknown"
        case 3...:
            name = "tick_known"
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

        // 文件名就是 tick_known / tick_unknown，不再加前缀：
        // Android 那边资源就叫这两个名字，保持一致才好对账。
        let fileName = name
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
