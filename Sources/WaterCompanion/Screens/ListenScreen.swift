import SwiftUI

// ════════════════════════════════════════════════════════════════════
//  听力页（一屏一句）
// ════════════════════════════════════════════════════════════════════
//
//  一个屏幕只放一句：上面是进度条和句子条，中间是句子卡片，下面是三档自评
//  和播放控制。素材不分档展开 —— 一上来摊开五百多句，人只会关掉它。
//
//  ## 一次「精听」听什么
//
//  队列 = 到期复训的句子 + 今天新排的句子，去重后最多取每日量的两倍。
//  复训排在前面：昨天没听懂的那句，今天第一句就要听见它。
//
//  ## 为什么会话要存进 `@State`
//
//  `Srs.dueListen` 依赖 `progress.listenDue`，而每打一次分都会改这个 map。
//  如果每次 `body` 都重算队列，打分那一刻队列会重排，游标就指到别的句子上，
//  用户会看到「我刚打的这句跑到第三句去了」。所以队列在进页面时定格一次，
//  只有换日、换每日词量、换级别才重建。
//
//  ## 连续播放的判据
//
//  用 `AudioPlayer.onFinish`（只在自然播完时调用），不用 `isPlaying == false`：
//  手动暂停也会把 isPlaying 置假，拿它当结束信号会在用户主动停下时莫名跳句。

struct ListenScreen: View {

    /// 播放器支持的倍速。四档足够，再细的档位在听感上分不出来。
    private static let speeds: [Double] = [0.7, 0.85, 1.0, 1.25]
    /// 连续播放时两句之间的停顿。
    private static let gaps: [Int] = [1000, 2000, 3500]

    @Environment(ProgressStore.self) private var store
    @Environment(ContentStore.self) private var content
    @Environment(AudioPlayer.self) private var audio

    /// 这一次精听的完整队列（进页面时定格，见文件头注释）
    @State private var session: [ListenItem] = []
    /// 队列里哪些是「到期复训」，用于卡片角上的「复训」标签
    @State private var dueSet: Set<String> = []

    @State private var cursor = 0
    @State private var revealed = false
    @State private var autoNext = true
    @State private var gapMs = 2000
    /// 上一句是不是「自己播完」的。播完再按播放要重播本句，不能当成续播。
    @State private var finishedId: String?
    /// 放不出来的提示（离线包没有这一条、网络 TTS 也失败时出现）
    @State private var notice: String?

    // MARK: - 派生状态

    private var progress: Progress { store.progress }
    private var dayNumber: Int { DailyPlan.dayNumber(startDate: progress.startDate) }
    private var cetLevel: CetLevel { CetLevel.fromKey(progress.level) ?? .cet4 }

    /// 当前级别的听力池。
    private var dailyPool: [ListenItem] {
        LevelContent.listening(content.allListening, level: cetLevel)
    }

    /// 今天新排的句子：纯函数推导，同一天里多次打开结果一致。
    private var freshItems: [ListenItem] {
        DailyPlan.slice(
            dailyPool,
            DailyPlan.dayIndex(startDate: progress.startDate),
            DailyPlan.listenCount(progress.dailyWords)
        )
    }

    /// 队列重建的触发条件。刻意不放 `listenDue` —— 它每打一次分就变。
    private var sessionKey: String {
        "\(progress.startDate ?? "")|\(progress.dailyWords)|\(cetLevel.rawValue)|\(dailyPool.count)"
    }

    private var current: ListenItem? {
        session.indices.contains(cursor) ? session[cursor] : nil
    }

    private var speaking: Bool {
        guard let current else { return false }
        return audio.isPlaying && audio.nowPlayingId == current.id
    }

    private var score: Int {
        guard let current else { return 0 }
        return progress.listenRating[current.id] ?? 0
    }

    // MARK: - 视图

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: Space.md) {
                headerRow
                strip

                ScrollView {
                    VStack(spacing: Space.md) {
                        if let current {
                            sentenceCard(current)
                        } else {
                            emptyState
                        }
                    }
                    .padding(.vertical, Space.xs)
                }
                .scrollIndicators(.hidden)
                // 底部操作板贴着安全区浮起来，句子卡从它下面滚过去 ——
                // 玻璃背后必须有东西，底下要是纯色，那就只是加了层灰。
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    bottomPanel
                }
            }
            .padding(.horizontal, Space.pageEdge)
            .padding(.top, Space.sm)
            .padding(.bottom, Space.sm)
        }
        .navigationTitle("听力")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: sessionKey) { rebuildSession() }
        .onAppear {
            // 自己接管连播（要留一段静默间隔），别让播放器也自动接下一句。
            audio.continuous = false
            audio.onFinish = { item in handleFinish(item) }
        }
        .onDisappear {
            audio.onFinish = nil
            // 离开页面还留着系统 TTS 在念，用户会以为是别的地方在说话。
            SpeechFallback.shared.stop()
        }
    }

    // MARK: - 顶部

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("第 \(dayNumber) 天")
                    .font(Typography.captionEmph)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("一屏一句，先听再看")
                    .font(Typography.micro)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: Space.sm)
            if !session.isEmpty {
                Text("\(cursor + 1) / \(session.count)")
                    .font(Typography.captionEmph)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.primary)
            }
        }
    }

    /// 句子进度条：一条一句，点哪条跳哪条。
    private var strip: some View {
        HStack(spacing: 4) {
            ForEach(session.indices, id: \.self) { index in
                let isCurrent = index == cursor
                Capsule()
                    .fill(stripColor(index, isCurrent: isCurrent))
                    .frame(maxWidth: .infinity)
                    .frame(height: isCurrent ? 10 : 6)
                    .contentShape(Rectangle())
                    .onTapGesture { play(at: index) }
            }
        }
        .frame(height: 12)
    }

    private func stripColor(_ index: Int, isCurrent: Bool) -> Color {
        if isCurrent { return Theme.Colors.primary }
        if progress.listenDone.contains(session[index].id) {
            return Theme.Colors.primary.opacity(0.45)
        }
        return Theme.Colors.ringTrack
    }

    // MARK: - 句子卡片

    private func sentenceCard(_ item: ListenItem) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(alignment: .top, spacing: Space.sm) {
                    Text(dueSet.contains(item.id) ? "复训" : "盲听")
                        .font(Typography.micro)
                        .foregroundStyle(
                            dueSet.contains(item.id) ? Theme.Colors.primary : Theme.Colors.textSecondary
                        )
                    Spacer(minLength: 0)
                    if progress.companion {
                        // 她在卡片右上角一起听，播放中轻轻点头
                        MascotListening(playing: speaking, height: 56)
                    } else {
                        Text("第 \(cursor + 1) 句")
                            .font(Typography.micro)
                            .monospacedDigit()
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }

                if revealed {
                    // 播放中还允许点词的话，手指一碰就把正在听的句子打断；
                    // 所以出声时只画文字，停下后才换成可点的版本。
                    if speaking {
                        Text(item.en)
                            .appArticleBody(Theme.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        WordTapText(text: item.en, font: Typography.titleSmall)
                    }
                    if !item.cn.isEmpty {
                        Text(item.cn)
                            .appBody(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    blindBox
                }

                HStack(spacing: Space.sm) {
                    Button {
                        withAnimation(.snappy) { revealed.toggle() }
                    } label: {
                        HStack(spacing: Space.xs) {
                            Image(systemName: revealed ? "eye.slash" : "eye")
                                .font(.system(size: 11, weight: .semibold))
                            Text(revealed ? "收起原文" : "看原文")
                                .font(Typography.micro)
                        }
                        .foregroundStyle(Theme.Colors.primary)
                        .padding(.horizontal, Space.md)
                        .frame(height: 34)
                        .background(Theme.Colors.primarySoft, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    if revealed && !speaking {
                        Text("点句子里的词看意思")
                            .font(Typography.micro)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer(minLength: 0)
                }

                if speaking, audio.duration > 0 {
                    ProgressView(value: min(max(audio.currentTime, 0), audio.duration), total: audio.duration)
                        .tint(Theme.Colors.primary)
                }

                if let notice {
                    Text(notice)
                        .appCaption(Theme.Colors.error)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var blindBox: some View {
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("盲听中")
                    .font(Typography.titleSmall)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text("先听两遍，再决定要不要看原文")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)

            // 她闭着眼戴耳机，正好是这一格要的状态
            if progress.companion {
                MascotFigure(.headphone, height: 115)
            }
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
        .background(Theme.Colors.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.field))
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "今天的听力听完了",
            systemImage: "ear",
            description: Text("明天会换新的。没听懂和模糊的句子可以到错题集里回去重听。")
        )
        .padding(.top, Space.xxl)
    }

    // MARK: - 底部操作板（一块玻璃）

    /// 自评 + 播放控制 + 连播设置，装在**同一块**玻璃里。
    ///
    /// 为什么不是「底栏一块玻璃、操作板再来一块」：两块玻璃上下贴在一起时，
    /// 各自的湿边会在缝里对撞出一条脏线，HIG 说的「不要玻璃叠玻璃」就是这个意思。
    /// 装进一块之后，句子卡从它下面滚过去，玻璃里才有东西在动。
    @ViewBuilder
    private var bottomPanel: some View {
        // 今天的句子听完了就别留一块按不动的控制板：三个按钮全灰，
        // 用户会以为是自己弄坏了，而不是「已经做完了」。
        if !session.isEmpty {
            GlassPanel(radius: Radius.card, horizontal: Space.md, vertical: Space.sm) {
                VStack(spacing: Space.sm) {
                    rateRow
                    controls
                    footer
                }
            }
            // 面板顶端留一条空气：句子卡滚到底时可以露一截在玻璃上沿之外，
            // 贴死了会像被切开。
            .padding(.top, Space.sm)
        }
    }

    // MARK: - 三档自评

    private var rateRow: some View {
        VStack(spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                gradeChip("没听懂", 1)
                gradeChip("模糊", 2)
                gradeChip("听懂了", 3)
            }

            HStack(spacing: Space.sm) {
                // 只有两档给表情：没听懂要给台阶，听懂了一起高兴；
                // 「模糊」不表态，免得像在评判。
                if let face = rateFace {
                    MascotFace(face, height: 36)
                }
                Text(rateHint)
                    .font(Typography.micro)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer(minLength: 0)
            }
        }
    }

    private var rateFace: MascotEmotion? {
        guard progress.companion else { return nil }
        switch score {
        case 1: return .kind
        case 3: return .joy
        default: return nil
        }
    }

    private var rateHint: String {
        switch score {
        case 1: return "没关系，明天再放一遍"
        case 2: return "有点印象，三天后再来"
        case 3: return "这句过了，十天后再兜一次"
        default: return "这句听懂了吗？没听懂和模糊都会进错题集"
        }
    }

    private func gradeChip(_ title: String, _ value: Int) -> some View {
        let selected = score == value
        return Button {
            guard let current else { return }
            store.rateListen(id: current.id, rating: value)
        } label: {
            Text(title)
                .font(Typography.captionEmph)
                .foregroundStyle(selected ? Theme.Colors.onPrimary : Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: Touch.min)
                .background(
                    selected ? Theme.Colors.primary : Theme.Colors.surfaceMuted,
                    in: RoundedRectangle(cornerRadius: Radius.field)
                )
                .contentShape(RoundedRectangle(cornerRadius: Radius.field))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 播放控制

    private var controls: some View {
        HStack(spacing: Space.xl) {
            controlButton("backward.end.fill", filled: false, size: 40) {
                if cursor > 0 { play(at: cursor - 1) }
            }
            .disabled(cursor <= 0)
            .opacity(cursor <= 0 ? 0.35 : 1)
            .accessibilityLabel("上一句")

            controlButton(speaking ? "pause.fill" : "play.fill", filled: true, size: 56) {
                togglePlay()
            }
            .accessibilityLabel(speaking ? "暂停" : "播放")

            controlButton("forward.end.fill", filled: false, size: 40) {
                if cursor < session.count - 1 { play(at: cursor + 1) }
            }
            .disabled(cursor >= session.count - 1)
            .opacity(cursor >= session.count - 1 ? 0.35 : 1)
            .accessibilityLabel("下一句")
        }
        .frame(maxWidth: .infinity)
    }

    private func controlButton(
        _ icon: String,
        filled: Bool,
        size: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: filled ? 20 : 15, weight: .semibold))
                .foregroundStyle(filled ? Theme.Colors.onPrimary : Theme.Colors.primary)
                .frame(width: size, height: size)
                .background(
                    filled ? Theme.Colors.primary : Theme.Colors.surfaceMuted,
                    in: Circle()
                )
                .contentShape(Circle())
        }
        // 播放控制是这一页唯一的"物理"受力点，按下去缩一点、提亮一点，
        // 手感才配得上它浮在玻璃上。
        .buttonStyle(LiquidPressStyle())
    }

    // MARK: - 底部：连播 / 间隔 / 速度

    private var footer: some View {
        HStack(spacing: Space.sm) {
            Text("连续播放")
                .font(Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)

            Toggle("", isOn: $autoNext)
                .labelsHidden()
                .tint(Theme.Colors.primary)
                .scaleEffect(0.82)
                .frame(width: 44)

            Spacer(minLength: 0)

            Menu {
                ForEach(ListenScreen.gaps, id: \.self) { value in
                    Button(Self.gapLabel(value)) { gapMs = value }
                }
            } label: {
                footerPill(Self.gapLabel(gapMs), dimmed: !autoNext)
            }
            .disabled(!autoNext)

            Menu {
                ForEach(ListenScreen.speeds, id: \.self) { value in
                    Button(Self.speedLabel(value)) { audio.setRate(Float(value)) }
                }
            } label: {
                footerPill(Self.speedLabel(Double(audio.playbackRate)), dimmed: false)
            }
        }
    }

    private func footerPill(_ title: String, dimmed: Bool) -> some View {
        Text(title)
            .font(Typography.micro)
            .foregroundStyle(dimmed ? Theme.Colors.idle : Theme.Colors.textSecondary)
            .padding(.horizontal, Space.md)
            .frame(height: 32)
            .background(Theme.Colors.surfaceMuted, in: Capsule())
            .contentShape(Capsule())
    }

    // MARK: - 会话

    private func rebuildSession() {
        let pool = dailyPool
        var byId: [String: ListenItem] = [:]
        for item in pool { byId[item.id] = item }

        let dueIds = Srs.dueListen(progress.listenDue)
        let cap = max(DailyPlan.listenCount(progress.dailyWords) * 2, 1)

        var seen = Set<String>()
        var merged: [ListenItem] = []
        for item in dueIds.compactMap({ byId[$0] }) + freshItems {
            guard seen.insert(item.id).inserted else { continue }
            merged.append(item)
            if merged.count >= cap { break }
        }

        session = merged
        dueSet = Set(dueIds).intersection(Set(pool.map(\.id)))

        // 队列换了一份就把游标收回合法范围；第一次进来直接停在第一句上
        // （不自动播，但句子已经选中，上一句/下一句立刻可用）。
        if merged.isEmpty {
            cursor = 0
        } else if cursor > merged.count - 1 {
            cursor = merged.count - 1
        }
    }

    // MARK: - 播放指令

    private func play(at index: Int) {
        guard session.indices.contains(index) else { return }
        let item = session[index]

        cursor = index
        revealed = false
        finishedId = nil
        notice = nil
        markHeard(item.id)

        // 换一句先把上一句的兜底朗读掐掉，否则网络 TTS 会和新音频叠在一起。
        SpeechFallback.shared.stop()
        audio.continuous = false

        let items = session.map { AudioPlayer.Item(id: $0.id, text: $0.en) }
        if audio.playQueue(items, startAt: index) { return }

        // 离线包没有这一条：先走网络 TTS，再退系统 TTS。
        SpeechFallback.shared.play(text: item.en) { played in
            notice = played ? nil : "这条暂时放不出来，换一条试试"
        }
    }

    private func togglePlay() {
        guard let current else {
            play(at: 0)
            return
        }
        if audio.isPlaying {
            audio.pause()
            return
        }
        // 播完再按、或者这条根本还没开始 → 重播本句（从头）；
        // 中途暂停过 → 续播，别让人重听已经听过的一半。
        if finishedId == current.id || audio.nowPlayingId != current.id {
            play(at: cursor)
        } else {
            audio.toggle()
        }
    }

    /// 自然播完的回调（来自播放器的轮询，不在主线程）。
    private func handleFinish(_ item: AudioPlayer.Item) {
        Task { @MainActor in
            finishedId = item.id

            guard autoNext else { return }
            guard let at = session.firstIndex(where: { $0.id == item.id }) else { return }
            guard at == cursor, at < session.count - 1 else { return }

            try? await Task.sleep(nanoseconds: UInt64(gapMs) * 1_000_000)

            // 这几秒里用户自己切了句、或关掉了连续播放，就别抢。
            guard autoNext, cursor == at else { return }
            play(at: at + 1)
        }
    }

    /// 切到某一句就算听过。已经记过的就不再记，反复点同一条不该刷高今天的量。
    private func markHeard(_ id: String) {
        guard !id.isEmpty else { return }
        if progress.listenDone.contains(id) { return }
        store.markListenDone(key: id)
        store.bump("listen")
    }

    // MARK: - 小工具

    private static func gapLabel(_ ms: Int) -> String {
        switch ms {
        case 1000: return "间隔 1.0 秒"
        case 3500: return "间隔 3.5 秒"
        default: return "间隔 2.0 秒"
        }
    }

    /// 倍速标签。用固定的几个字面值而不是 `String(format: "%.2f")`：
    /// 后者会把 0.7 显示成「0.70×」，多出来的那个 0 纯属噪音。
    private static func speedLabel(_ value: Double) -> String {
        if abs(value - 0.7) < 0.01 { return "0.7×" }
        if abs(value - 0.85) < 0.01 { return "0.85×" }
        if abs(value - 1.25) < 0.01 { return "1.25×" }
        return "1.0×"
    }
}
