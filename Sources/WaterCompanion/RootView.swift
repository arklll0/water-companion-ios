import SwiftUI

// ════════════════════════════════════════════════════════════════════
//  根容器：五个页签 + 二级页导航
// ════════════════════════════════════════════════════════════════════
//
//  底栏是**自己画的悬浮胶囊**，不是 `TabView`：
//  系统 TabView 在 iOS 17 上没法做成「浮在内容之上、圆角胶囊、毛玻璃」的样子，
//  而这一条是品牌观感的重点。代价是要自己管页签状态，就一个 enum，不值一提。
//
//  导航：一个 `NavigationStack` 包住整屏。切页签时清空 `path`，
//  因为「单词 → 词族 → 切到今日 → 再切回单词」不该停在词族页里，
//  用户点的是页签，期待的是回到那一页的顶层。

// MARK: - 页签

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case words
    case listen
    case practice
    case me

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "今日"
        case .words: return "单词"
        case .listen: return "听力"
        case .practice: return "练习"
        case .me: return "我的"
        }
    }

    /// 图标一律用 SF Symbols，不引图片、不手绘 Path。
    /// 系统里有现成的就用系统语义最贴近的那一个：
    /// 房子 = 今日、字在书里 = 单词、耳朵 = 听力、笔 + 清单 = 练习、人像 = 我的。
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .words: return "character.book.closed.fill"
        case .listen: return "ear.fill"
        case .practice: return "pencil.and.list.clipboard"
        case .me: return "person.crop.circle.fill"
        }
    }
}

// MARK: - 二级页

/// 二级页路由。用 `NavigationLink(value:)` 推入，不在页面里自己管状态，
/// 这样「我的 → 统计 → 错题」能一路返回，也自动带上系统的返回手势与返回按钮。
enum AppRoute: Hashable {
    case family
    case stats
    case wrong
    case translate
    /// 讲义目录
    case lecture
    /// 讲义正文。带上章 id 与篇 id，路由本身不持有文章内容：
    /// 内容在 `ContentStore` 里按 id 现查，存档和导航栈都不需要跟着讲义文件走。
    case lesson(chapterId: String, lessonId: String)
}

// MARK: - 根视图

struct RootView: View {

    @Environment(ProgressStore.self) private var store
    @Environment(ContentStore.self) private var content

    @State private var tab: AppTab = .home
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                page
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                TabBar(selection: $tab)
                    .padding(.horizontal, Space.pageEdge)
                    .padding(.top, Space.sm)
                    .padding(.bottom, Space.xs)
            }
            .background(AppBackground())
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .family:
                    FamilyScreen()
                case .stats:
                    StatsScreen()
                case .wrong:
                    // 「重做」只切到练习页的阅读分段，不定位原题，
                    // 错题里的 ref 指向的那道题可能已经不在今天的切片里了，
                    // 强行定位会做出一堆「跳过去却是另一道题」的错觉。
                    WrongScreen(onRedo: {
                        tab = .practice
                        if !path.isEmpty {
                            path.removeLast(path.count)
                        }
                    })
                case .translate:
                    TranslateScreen()
                case .lecture:
                    LectureScreen(lectures: content.lectures) { chapterId, lessonId in
                        path.append(AppRoute.lesson(chapterId: chapterId, lessonId: lessonId))
                    }
                case .lesson(let chapterId, let lessonId):
                    // 讲义是按 id 现查的，查不到只有两种可能：文件没加载完、id 写错了。
                    // 两种情况用户能做的动作都一样（退回去重点一次），所以合成一个兜底页，
                    // 文案与 Android 端保持一致，不给用户一句「未知错误」。
                    if let lesson = findLesson(chapterId: chapterId, lessonId: lessonId) {
                        LessonScreen(lesson: lesson) {
                            if !path.isEmpty {
                                path.removeLast()
                            }
                        }
                    } else {
                        ContentUnavailableView {
                            Label("这篇没找到", systemImage: "doc.questionmark")
                        } description: {
                            Text("讲义可能还没加载完，退回去重新点一次。")
                        } actions: {
                            Button("返回目录") {
                                if !path.isEmpty {
                                    path.removeLast()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
        }
        // 首次启动先选级。挂在 NavigationStack 外层，才能连底栏一起盖住：
        // 挂在里面的 VStack 上，底栏会留在下面，用户能先切页再选级。
        .overlay {
            if CetLevel.fromKey(store.progress.level) == nil {
                LevelPickerOverlay { key in
                    store.setLevel(key)
                }
            }
        }
        .task {
            // 首次启动写入开始日期、维护连续打卡。幂等，重复调用没有副作用。
            store.touchStreak()
        }
        .onChange(of: tab) { _, _ in
            if !path.isEmpty {
                path.removeLast(path.count)
            }
        }
    }

    @ViewBuilder
    private var page: some View {
        switch tab {
        case .home:
            HomeScreen(onNavigate: handleNavigate)
        case .words:
            WordsScreen(onGoFamily: { path.append(AppRoute.family) })
        case .listen:
            ListenScreen()
        case .practice:
            PracticeScreen()
        case .me:
            MeScreen()
        }
    }

    /// 首页的四个任务卡按字符串路由跳页签，与 Android 版 `TASKS` 的 `go` 字段同构。
    private func handleNavigate(_ target: String) {
        switch target {
        case "words":
            tab = .words
        case "listen":
            tab = .listen
        case "practice", "read":
            tab = .practice
        case "wrong":
            // 首页第 4 张卡「记 10 个易错点」指向错题本，不是「我的」。
            // 之前落到 default 会跳到设置页，用户点完发现没看到错题。
            path.append(AppRoute.wrong)
        default:
            tab = .me
        }
    }

    /// 按章 id + 篇 id 找讲义。目录与正文共用同一份内容，不额外建索引：
    /// 52 篇的线性查找比维护一张会跟文件不同步的 id 表更稳。
    private func findLesson(chapterId: String, lessonId: String) -> LectureLesson? {
        guard let chapter = content.lectures.chapters.first(where: { $0.id == chapterId }) else {
            return nil
        }
        return chapter.lessons.first(where: { $0.id == lessonId })
    }
}

// MARK: - 悬浮胶囊底栏

private struct TabBar: View {

    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { item in
                Button {
                    // 系统动效（iOS 17 `.snappy`），不手调 spring 参数
                    withAnimation(.snappy) {
                        selection = item
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon)
                            .font(.system(size: 19, weight: .semibold))
                            .frame(height: 22)
                        Text(item.title)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(
                        selection == item ? Theme.Colors.primary : Theme.Colors.idle
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: Touch.min)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
            }
        }
        .padding(.horizontal, Space.xs)
        .padding(.vertical, Space.xs)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule().strokeBorder(Theme.Colors.separator.opacity(0.7), lineWidth: 0.8)
        }
        .shadow(color: Color.black.opacity(0.10), radius: 14, x: 0, y: 5)
    }
}
