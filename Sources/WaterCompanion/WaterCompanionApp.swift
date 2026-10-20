import SwiftUI

// ════════════════════════════════════════════════════════════════════
//  App 入口
// ════════════════════════════════════════════════════════════════════
//
//  三个 store 都在这里建一次，用 `.environment()` 注入给整棵视图树。
//  为什么不在每个页面各自 `@State` 新建：进度是全局唯一的事实来源，
//  建多份就会出现「单词页记了、首页不知道」这种对不上账的情况。
//
//  主题：`progress.theme` 取值与网站一致（auto / light / dark）。
//  auto 时传 nil，交给系统；手动钉死时 `.preferredColorScheme` 会压住系统设置。

@main
struct WaterCompanionApp: App {

    @State private var progressStore = ProgressStore()
    @State private var contentStore = ContentStore()
    @State private var audioPlayer = AudioPlayer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(progressStore)
                .environment(contentStore)
                .environment(audioPlayer)
                .tint(Theme.Colors.primary)
                .preferredColorScheme(
                    Theme.Mode.fromKey(progressStore.progress.theme).colorScheme
                )
        }
    }
}
