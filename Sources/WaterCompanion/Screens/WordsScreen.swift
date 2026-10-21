import SwiftUI

// ════════════════════════════════════════════════════════════════════
//  单词页
// ════════════════════════════════════════════════════════════════════
//
//  组卷规则与网站 startWordSession 一致：
//  先取到期词（最多 max(6, 40%×批量)），再补足新词；评「忘了」会把词插回队尾当天再见。
//
//  ⚠️「每天学多少」**必须落盘**到 `progress.dailyWords`，不能用本地 @State。
//  听力和练习的每日量都跟着它走（DailyPlan.listenCount / readCount / paperCount
//  都以它做输入）。用本地状态的话，一重启就复位，而且和 DailyPlan 读到的值是
//  两份互不相干的数据 —— 表现就是「单词页选了 30 词，听力页还按 20 词算出的 6 句给」。
//
//  版式：列表态用系统 `List` + `.insetGrouped`（分组圆角、原生分隔线、原生行高），
//  只有翻卡会话与结算卡这两块「设计过的内容面」才自己排版。

// MARK: - 会话项

private struct SessionWord: Identifiable {

    let id = UUID()
    let word: String
    let isNew: Bool

    init(word: String, isNew: Bool) {
        self.word = word
        self.isNew = isNew
    }
}

// MARK: - 页面

struct WordsScreen: View {

    @Environment(ProgressStore.self) private var store
    @Environment(ContentStore.self) private var content
    @Environment(AudioPlayer.self) private var audio

    let onGoFamily: () -> Void

    @State private var queue: [SessionWord] = []
    @State private var index: Int = 0
    @State private var flipped: Bool = false
    @State private var finished: Bool = false
    @State private var ratedCount: Int = 0
    @State private var showsEmptyNotice: Bool = false

    // MARK: 派生状态

    private var progress: Progress { store.progress }
    private var batch: Int { max(progress.dailyWords, 1) }

    private var dueWords: [String] { Srs.dueWords(progress.wordProgress) }
    private var masteredCount: Int { Srs.mastered(progress.wordProgress) }
    private var todayLearned: Int { store.todayLog.words }

    private var newWords: [Word] {
        content.words.filter { progress.wordProgress[$0.w] == nil }
    }

    /// 「正在翻卡」= 队列里还有词且还没走到头
    private var inSession: Bool {
        !queue.isEmpty && index < queue.count
    }

    /// 分段控件的选择。
    ///
    /// get 里做了兜底：存档可能是网站导出的任意值（比如 15），
    /// 不在 10/20/30 里时按 20 显示 —— 否则 Picker 找不到匹配 tag，
    /// 会当场打印运行时告警并显示成「一个都没选中」。
    private var batchSelection: Binding<Int> {
        Binding(
            get: { [10, 20, 30].contains(batch) ? batch : 20 },
            set: { store.setDailyWords($0) }
        )
    }

    var body: some View {
        ZStack {
            AppBackground()
            page
        }
        .navigationTitle("单词")
        .navigationBarTitleDisplayMode(.large)
    }

    /// 三态：列表 / 翻卡 / 结算。
    /// 命名成 `page` 而不是 `content`：`content` 已经是 ContentStore 的名字，
    /// 同作用域重名会直接编译失败。
    @ViewBuilder
    private var page: some View {
        if finished {
            FormPage { finishPanel }
        } else if inSession {
            FormPage { sessionPanel }
        } else {
            overviewList
        }
    }

    // MARK: - 概览（系统分组列表）

    private var overviewList: some View {
        List {
            Section {
                VStack(spacing: Space.md) {
                    HStack(spacing: Space.sm) {
                        StatBox("\(todayLearned)", "今日已学")
                        StatBox("\(dueWords.count)", "待复习")
                        StatBox("\(masteredCount)", "已掌握")
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text("按你的节奏设置一次学多少。")
                            .appCaption()
                        // 三选一用系统的分段控件 —— 自己画三个胶囊要额外处理
                        // 选中态、无障碍与动态字号，系统控件这些都自带。
                        Picker("每天背多少", selection: batchSelection) {
                            Text("10 词").tag(10)
                            Text("20 词").tag(20)
                            Text("30 词").tag(30)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    PrimaryButton("开始背单词", icon: "play.fill") {
                        startSession()
                    }

                    if showsEmptyNotice {
                        Text("今天没有到期的词，也没有新词了。明天再来。")
                            .appCaption()
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, Space.xs)
            } footer: {
                Text("每天的量同时决定听力与阅读的份量，改一处即可。")
            }

            Section {
                if newWords.isEmpty {
                    ContentUnavailableView(
                        "词库已全部接触一遍",
                        systemImage: "checkmark.circle",
                        description: Text("接下来主要是复习")
                    )
                } else {
                    ForEach(Array(newWords.prefix(8))) { word in
                        HStack(spacing: Space.sm) {
                            Text(word.w)
                                .font(Typography.body)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Spacer(minLength: Space.sm)
                            Text(word.m)
                                .font(Typography.micro)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .lineLimit(1)
                        }
                        .frame(minHeight: 30)
                    }
                }

                Button {
                    onGoFamily()
                } label: {
                    HStack(spacing: Space.md) {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(Theme.Colors.primary)
                            .frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("记不住单词？换个方法")
                                .font(Typography.bodyEmph)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text("词族 · 锚词辐射法")
                                .font(Typography.micro)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Colors.idle)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } header: {
                HStack {
                    Text("接下来会学")
                    Spacer()
                    Text("\(newWords.count) 个新词")
                        .font(Typography.micro)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - 卡片会话

    private var sessionPanel: some View {
        VStack(spacing: Space.itemGap) {
            HStack(spacing: Space.sm) {
                Text("\(index + 1) / \(queue.count)")
                    .font(Typography.captionEmph)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(queue[index].isNew ? "新词" : "复习")
                    .font(Typography.micro)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer(minLength: 0)
                QuietButton("退出") {
                    exitSession()
                }
            }

            wordCard
                .id(queue[index].id)

            if flipped {
                ratingGrid
            } else {
                Text("先自己想一下意思，再翻开对答案。")
                    .appCaption()
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var wordCard: some View {
        let meta = content.wordOrPlaceholder(queue[index].word)
        let hasWordAudio = audio.hasAudio(for: meta.w)

        return AppCard(padding: Space.lg) {
            VStack(spacing: Space.sm) {
                VStack(spacing: Space.xs) {
                    Text(meta.w)
                        .font(Typography.display)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if !meta.p.isEmpty {
                        Text(meta.p)
                            .font(Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.snappy) { flipped = true }
                }

                HStack(spacing: Space.sm) {
                    SoundChip("单词", enabled: hasWordAudio) {
                        audio.togglePlay(text: meta.w)
                    }
                    SoundChip("例句", enabled: !meta.e.isEmpty) {
                        audio.togglePlay(text: meta.e)
                    }
                }
                .padding(.top, Space.xs)

                Text(hasWordAudio ? "离线发音 · 无需网络" : "暂无离线发音")
                    .font(Typography.micro)
                    .foregroundStyle(hasWordAudio ? Theme.Colors.primary : Theme.Colors.idle)

                Divider()
                    .padding(.vertical, Space.xs)

                if flipped {
                    VStack(spacing: Space.xs) {
                        if !meta.t.isEmpty {
                            Text(meta.t)
                                .font(Typography.micro)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Text(meta.m)
                            .font(Typography.title)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        if !meta.e.isEmpty {
                            Text(meta.e)
                                .font(Typography.caption)
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, Space.xs)
                        }
                        if !meta.ec.isEmpty {
                            Text(meta.ec)
                                .font(Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
                } else {
                    Button {
                        withAnimation(.snappy) { flipped = true }
                    } label: {
                        Text("点一下看意思")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.Colors.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: Touch.min)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var ratingGrid: some View {
        VStack(spacing: Space.sm) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Space.sm),
                    GridItem(.flexible(), spacing: Space.sm)
                ],
                spacing: Space.sm
            ) {
                RateButton("忘了", subtitle: "待会再来") { rate(1) }
                RateButton("模糊", subtitle: "明天复习") { rate(2) }
                RateButton("认识", subtitle: "3 天后再见") { rate(3) }
                RateButton("很熟", subtitle: "7 天后再见") { rate(4) }
            }
            Text("评「忘了」的词会在这一组最后再出现一次。")
                .font(Typography.micro)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - 完成

    private var finishPanel: some View {
        AppCard {
            VStack(spacing: Space.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 36, weight: .regular))
                    .foregroundStyle(Theme.Colors.primary)
                    .symbolEffect(.bounce, value: finished)
                Text("这一组完成了")
                    .font(Typography.title)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("你刚刚认了 \(ratedCount) 个词。")
                    .appCaption()
                    .multilineTextAlignment(.center)

                HStack(spacing: Space.sm) {
                    PrimaryButton("再来一组", icon: "arrow.clockwise") {
                        startSession()
                    }
                    SecondaryButton("回列表") {
                        exitSession()
                    }
                }
                .padding(.top, Space.sm)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - 动作

    private func startSession() {
        showsEmptyNotice = false

        let dueLimit = max(6, Int((Double(batch) * 0.4).rounded()))
        let duePart = Array(dueWords.prefix(dueLimit))
        let newPart = Array(newWords.prefix(max(batch - duePart.count, 0)))

        var next: [SessionWord] = duePart.map { SessionWord(word: $0, isNew: false) }
        next.append(contentsOf: newPart.map { SessionWord(word: $0.w, isNew: true) })

        if next.isEmpty {
            queue = []
            index = 0
            ratedCount = 0
            finished = false
            flipped = false
            showsEmptyNotice = true
            return
        }

        queue = next
        index = 0
        ratedCount = 0
        flipped = false
        finished = false
    }

    private func exitSession() {
        queue = []
        index = 0
        ratedCount = 0
        flipped = false
        finished = false
    }

    private func rate(_ rating: Int) {
        guard index < queue.count else { return }
        let item = queue[index]

        store.recordWordRating(word: item.word, rating: rating)

        // 忘了：当天还要再见一次 —— 插回队尾，所以队列会变长
        if rating == 1 {
            queue.append(SessionWord(word: item.word, isNew: false))
        }

        ratedCount += 1
        flipped = false
        index += 1

        if index >= queue.count {
            finished = true
        }
    }
}
