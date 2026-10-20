import Foundation
import SwiftUI

// ════════════════════════════════════════════════════════════════════
//  听力页
// ════════════════════════════════════════════════════════════════════
//
//  主视图是「今天该听的这几句」：条数由当天单词量决定（见 `DailyPlan`），
//  第 1 天和第 90 天听到的内容不同。全部素材退到页面底部一个折叠区，
//  只在「想自己挑一段精听」时展开 —— 一上来就摊开五百多句，人只会关掉它。
//
//  ## 播放器为什么自己维护一份 `queue`
//
//  `AudioPlayer.nowPlayingId` 只说明「现在响的是哪一条」，而 `N / M` 里的 M
//  取决于**按下播放时的那份列表**。今天的 6 句和全部素材 540 句的 M 不是一回事，
//  所以「当前列表」必须由页面自己记住：播哪份列表就把哪份记下来，
//  否则从全部素材里点第 300 句时，卡片会按 6 句算，显示出「300 / 6」这种东西。
//
//  ## 「完成」的语义
//
//  切到某一句就算听过 —— 不等它播完。听力是「过一遍、磨耳朵」，
//  等一句播完再记，用户听到一半切走就白听了；而等他真的想精听某一句时，
//  他会自己拖回去。判据落在 `listenDone` 的 id 上（`ListenItem.en`），
//  与今天/全部这两份列表无关，所以两边的高亮是同步的。
//
//  记账只在**第一次**听这句时做：反复点同一条不该把「今天听了 30 句」刷上去。

struct ListenScreen: View {

    @Environment(ProgressStore.self) private var store
    @Environment(ContentStore.self) private var content
    @Environment(AudioPlayer.self) private var audio

    /// 难度分档（全部素材区用）
    private enum Level: String, CaseIterable, Identifiable {
        case basic
        case dialog
        case passage

        var id: String { rawValue }

        var title: String {
            switch self {
            case .basic: return "入门短句"
            case .dialog: return "短对话"
            case .passage: return "短篇"
            }
        }
    }

    /// 播放器支持的倍速。四档足够 —— 再细的档位在听感上分不出来。
    private static let speeds: [Double] = [0.7, 0.85, 1.0, 1.25]

    @State private var showChinese = false
    @State private var showAll = false
    @State private var level: Level = .basic
    @State private var sliderValue: Double = 0
    @State private var isDragging = false

    /// 上一次真正按下播放时用的那份列表（今天这几句 / 某一档全部素材）
    @State private var queue: [ListenItem] = []
    /// 那份列表的名字，显示在播放器卡片顶上
    @State private var queueTitle = "今天这几句"
    /// 播放失败的提示（离线包里没有这一条时会出现）
    @State private var notice: String?

    // MARK: - 派生状态

    private var progress: Progress { store.progress }
    private var dayNumber: Int { DailyPlan.dayNumber(startDate: progress.startDate) }

    /// 今天该听哪几句：纯函数推导，同一天里多次打开结果一致
    private var todayItems: [ListenItem] {
        DailyPlan.slice(
            content.allListening,
            DailyPlan.dayIndex(startDate: progress.startDate),
            DailyPlan.listenCount(progress.dailyWords)
        )
    }

    private var doneIds: Set<String> { Set(progress.listenDone) }

    private var doneInToday: Int {
        DailyPlan.doneCount(todayItems) { doneIds.contains($0.id) }
    }

    private var todayPercent: Double {
        todayItems.isEmpty ? 0 : Double(doneInToday) / Double(todayItems.count)
    }

    private var shownAll: [ListenItem] {
        switch level {
        case .basic: return content.listeningBasic
        case .dialog: return content.listeningDialog
        case .passage: return content.listeningPassage
        }
    }

    /// 正在响的那一条。不在当前列表里（比如刚在单词页点过发音）就算没有。
    private var currentItem: ListenItem? {
        guard let id = audio.nowPlayingId else { return nil }
        return queue.first { $0.id == id }
    }

    private var currentIndex: Int? {
        guard let item = currentItem else { return nil }
        return queue.firstIndex { $0.id == item.id }
    }

    private var canScrub: Bool { audio.duration > 0 }

    // MARK: - 视图

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: Space.section) {
                    progressionSection
                    sentenceSection
                    allSection
                }
                .padding(.horizontal, Space.pageEdge)
                .padding(.top, Space.md)
                .padding(.bottom, Space.xxl)
            }
        }
        .navigationTitle("听力精听")
        .navigationBarTitleDisplayMode(.large)
        .onChange(of: audio.nowPlayingId) { _, newValue in
            markHeard(newValue)
        }
    }

    // MARK: - 今日进度 + 播放器

    private var progressionSection: some View {
        VStack(spacing: Space.itemGap) {
            todayProgressCard
            playerCard
            sourceNote
        }
    }

    private var todayProgressCard: some View {
        AppCard(background: Theme.Colors.banner, showsBorder: false) {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                    Text(progressHeadline)
                        .font(Typography.titleSmall)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if !todayItems.isEmpty {
                        Text("\(doneInToday) / \(todayItems.count)")
                            .font(Typography.captionEmph)
                            .monospacedDigit()
                            .foregroundStyle(Theme.Colors.primary)
                    }
                }

                ProgressView(value: todayPercent)
                    .tint(Theme.Colors.primary)

                Text("条数跟当天单词量联动：每天背 20 个词就是 6 句。明天会换成新的，不用手动挑。")
                    .appCaption()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var progressHeadline: String {
        if todayItems.isEmpty { return "第 \(dayNumber) 天 · 暂无听力素材" }
        if doneInToday == 0 { return "第 \(dayNumber) 天 · 今天要听 \(todayItems.count) 句" }
        if doneInToday < todayItems.count { return "第 \(dayNumber) 天 · 还剩 \(todayItems.count - doneInToday) 句" }
        return "第 \(dayNumber) 天 · 今天的听力听完了"
    }

    private var playerCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(spacing: Space.sm) {
                    Text(queueTitle)
                        .font(Typography.micro)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer(minLength: 0)
                    if let index = currentIndex {
                        Text("\(index + 1) / \(queue.count)")
                            .font(Typography.micro)
                            .monospacedDigit()
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }

                Text(currentItem?.en ?? "点下面的句子开始")
                    .font(Typography.title)
                    .foregroundStyle(currentItem == nil ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                    .lineSpacing(Typography.captionLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)

                if showChinese, let item = currentItem, !item.cn.isEmpty {
                    Text(item.cn)
                        .appBody(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }

                if let item = currentItem, !item.cn.isEmpty {
                    QuietButton(
                        showChinese ? "隐藏中文" : "显示中文对照",
                        icon: showChinese ? "character.bubble.fill" : "character.bubble"
                    ) {
                        withAnimation(.snappy) { showChinese.toggle() }
                    }
                }

                progressBar

                controls

                HStack {
                    Text("速度")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer(minLength: Space.sm)
                }
                .padding(.top, Space.xs)

                speedPicker

                Toggle(
                    "连续播放",
                    isOn: Binding(
                        get: { audio.continuous },
                        set: { audio.continuous = $0 }
                    )
                )
                .font(Typography.body)
                .tint(Theme.Colors.primary)

                if let notice {
                    Text(notice)
                        .appCaption(Theme.Colors.error)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
        }
    }

    /// 进度条 + 两边的时间。
    ///
    /// 拖动时用本地值、松手才 seek：每帧都 seek 会让声音一顿一顿的。
    private var progressBar: some View {
        VStack(spacing: Space.xs) {
            Slider(
                value: Binding(
                    get: { isDragging ? sliderValue : audio.currentTime },
                    set: { sliderValue = $0 }
                ),
                in: 0...max(audio.duration, 1),
                onEditingChanged: { editing in
                    if editing {
                        sliderValue = audio.currentTime
                        isDragging = true
                    } else {
                        audio.seek(to: sliderValue)
                        isDragging = false
                    }
                }
            )
            .tint(Theme.Colors.primary)
            .disabled(!canScrub)

            HStack {
                Text(Self.clock(isDragging ? sliderValue : audio.currentTime))
                    .font(Typography.micro)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer(minLength: 0)
                Text(Self.clock(audio.duration))
                    .font(Typography.micro)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: Space.md) {
            controlButton("backward.end.fill", filled: false) {
                step(-1)
            }
            .accessibilityLabel("上一句")

            controlButton(audio.isPlaying ? "pause.fill" : "play.fill", filled: true) {
                togglePlay()
            }
            .accessibilityLabel(audio.isPlaying ? "暂停" : "播放")

            controlButton("forward.end.fill", filled: false) {
                step(1)
            }
            .accessibilityLabel("下一句")
        }
        .frame(maxWidth: .infinity)
    }

    private func controlButton(_ icon: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(filled ? Theme.Colors.onPrimary : Theme.Colors.primary)
                .frame(width: Touch.min, height: Touch.min)
                .background(
                    filled ? Theme.Colors.primary : Theme.Colors.surfaceMuted,
                    in: Circle()
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    /// 三选一用系统的分段控件：选中态、动态字号、无障碍语义都由系统负责。
    private var speedPicker: some View {
        Picker(
            "速度",
            selection: Binding(
                get: { nearestSpeed(audio.playbackRate) },
                set: { audio.setRate(Float($0)) }
            )
        ) {
            ForEach(ListenScreen.speeds, id: \.self) { value in
                Text(Self.speedLabel(value)).tag(value)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var sourceNote: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("音源：\(audioSourceText)")
                .font(Typography.micro)
                .foregroundStyle(hasOfflineAudio ? Theme.Colors.primary : Theme.Colors.textSecondary)
            Text("离线包：\(offlinePackText)")
                .font(Typography.micro)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text("音频随 App 打包，不联网也能听。带上耳机，效果比外放好很多。")
                .appCaption()
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.xs)
    }

    private var hasOfflineAudio: Bool {
        guard let item = currentItem else { return false }
        return audio.hasAudio(for: item.en)
    }

    private var offlinePackText: String {
        audio.indexedCount > 0 ? "\(audio.indexedCount) 条" : "未加载"
    }

    private var audioSourceText: String {
        if currentItem == nil { return "随包离线音频（无需网络）" }
        return hasOfflineAudio ? "随包离线音频（无需网络）" : "这条暂无离线音频"
    }

    // MARK: - 今天这几句

    private var sentenceSection: some View {
        VStack(spacing: Space.itemGap) {
            SectionHeader("今天这几句", subtitle: "点一条直接听", trailing: "\(todayItems.count) 句")

            if todayItems.isEmpty {
                ContentUnavailableView(
                    "暂无听力素材",
                    systemImage: "ear",
                    description: Text("内容文件没读到，检查一下 Resources/Content/listening.json。")
                )
            } else {
                LazyVStack(spacing: Space.itemGap) {
                    ForEach(todayItems) { item in
                        sentenceRow(
                            item,
                            leading: "第 \(positionInToday(item)) 句",
                            list: todayItems,
                            listTitle: "今天这几句"
                        )
                    }
                }
            }
        }
    }

    // MARK: - 全部素材

    private var allSection: some View {
        VStack(spacing: Space.itemGap) {
            SecondaryButton(
                showAll ? "收起全部素材" : "展开全部素材（\(content.allListening.count) 句）",
                icon: showAll ? "chevron.up" : "chevron.down"
            ) {
                withAnimation(.snappy) { showAll.toggle() }
            }

            if !showAll {
                Text("想自己挑一段精听时再展开。每天推荐的那几句在上面。")
                    .appCaption()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.xs)
            }

            if showAll {
                Picker("难度", selection: $level) {
                    ForEach(Level.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.top, Space.xs)

                LazyVStack(spacing: Space.itemGap) {
                    ForEach(shownAll) { item in
                        sentenceRow(item, leading: level.title, list: shownAll, listTitle: level.title)
                    }
                }
                .padding(.top, Space.xs)
            }
        }
    }

    // MARK: - 句子行

    private func sentenceRow(
        _ item: ListenItem,
        leading: String,
        list: [ListenItem],
        listTitle: String
    ) -> some View {
        let isCurrent = item.id == audio.nowPlayingId
        let isDone = doneIds.contains(item.id)

        return AppCard(
            padding: Space.lg,
            background: isCurrent ? Theme.Colors.primarySoft : Theme.Colors.surface,
            showsBorder: !isCurrent
        ) {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.sm) {
                    Text(leading)
                        .font(Typography.micro)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer(minLength: 0)
                    if isDone {
                        HStack(spacing: 2) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11, weight: .semibold))
                            Text("已完成")
                                .font(Typography.micro)
                        }
                        .foregroundStyle(Theme.Colors.primary)
                    }
                }

                Text(item.en)
                    .font(isCurrent ? Typography.bodyEmph : Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineSpacing(Typography.captionLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)

                if !item.cn.isEmpty {
                    Text(item.cn)
                        .appCaption()
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: Space.sm) {
                    Button {
                        play(list, title: listTitle, index: list.firstIndex { $0.id == item.id } ?? 0)
                    } label: {
                        HStack(spacing: Space.xs) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 11, weight: .semibold))
                            Text("播放这一句")
                                .font(Typography.micro)
                        }
                        .foregroundStyle(Theme.Colors.primary)
                        .padding(.horizontal, Space.md)
                        .frame(height: 34)
                        .background(Theme.Colors.primarySoft, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)
                }
                .padding(.top, Space.xs)
            }
        }
    }

    private func positionInToday(_ item: ListenItem) -> Int {
        (todayItems.firstIndex { $0.id == item.id } ?? 0) + 1
    }

    // MARK: - 播放指令

    /// 播一份列表里的第 `index` 条。
    ///
    /// **先记下列表再播**：`N / M` 与「当前这一句」都靠 `queue` 反查，
    /// 顺序反了就会出现「点的是第 300 句，卡片显示 300 / 6」。
    private func play(_ list: [ListenItem], title: String, index: Int) {
        guard !list.isEmpty else { return }
        let items = list.map { AudioPlayer.Item(id: $0.id, text: $0.en) }
        queue = list
        queueTitle = title
        let ok = audio.playQueue(items, startAt: min(max(index, 0), list.count - 1))
        notice = ok ? nil : "这条暂无离线音频，换一条试试"
    }

    private func step(_ delta: Int) {
        guard !queue.isEmpty else {
            play(todayItems, title: "今天这几句", index: 0)
            return
        }
        let base = currentIndex ?? 0
        let target = min(max(base + delta, 0), queue.count - 1)
        if target == base, audio.nowPlayingId != nil {
            // 已经是第一句 / 最后一句：重播当前这条，而不是毫无反应
            audio.seek(to: 0)
            if !audio.isPlaying { audio.toggle() }
            return
        }
        play(queue, title: queueTitle, index: target)
    }

    private func togglePlay() {
        guard !queue.isEmpty else {
            play(todayItems, title: "今天这几句", index: 0)
            return
        }
        if audio.isPlaying {
            audio.pause()
        } else if audio.nowPlayingId == nil {
            play(queue, title: queueTitle, index: 0)
        } else {
            audio.toggle()
        }
    }

    /// 切到某一句就算听过。已经记过的就不再记 —— 反复点同一条不该刷高今天的量。
    private func markHeard(_ id: String?) {
        guard let id, !id.isEmpty else { return }
        if doneIds.contains(id) { return }
        store.markListenDone(key: id)
        store.bump("listen")
    }

    // MARK: - 小工具

    private func nearestSpeed(_ rate: Float) -> Double {
        let value = Double(rate)
        var best = ListenScreen.speeds[0]
        var bestGap = abs(value - best)
        for candidate in ListenScreen.speeds {
            let gap = abs(value - candidate)
            if gap < bestGap {
                best = candidate
                bestGap = gap
            }
        }
        return best
    }

    /// 倍速标签。用固定的几个字面值而不是 `String(format: "%.2f")` ——
    /// 后者会把 0.7 显示成「0.70×」，多出来的那个 0 纯属噪音。
    private static func speedLabel(_ value: Double) -> String {
        if value == 0.7 { return "0.7×" }
        if value == 0.85 { return "0.85×" }
        if value == 1.25 { return "1.25×" }
        return "1.0×"
    }

    /// 秒 → mm:ss（负数按 0 处理，避免出现「-1:-3」）
    private static func clock(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded()), 0)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
