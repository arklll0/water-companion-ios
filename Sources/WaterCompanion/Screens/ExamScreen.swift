import Combine
import Foundation
import SwiftUI

// ════════════════════════════════════════════════════════════════════
//  计时模考
// ════════════════════════════════════════════════════════════════════
//
//  三段式：配置 → 答题 → 出分。
//
//  ## 出题与算分（与网站 startExam / finishExam 一致）
//     · 听力题取「短对话」素材，每题配一个场景题（原文在解析里给）；
//     · 阅读题从题库随机抽；
//     · 折算 710 分制 = min(710, round(710 × 正确率 × 0.7 + 248))。
//  这个公式不是「真实四级赋分」，而是一条**保底线 248、满分 710** 的线性映射：
//  一道题都不做也有 248，全对才 710。它给的是一个能感觉到自己在进步的数，
//  而不是一个精确的成绩预测。
//
//  ## 计时
//
//  每个部分**各自**限时：切到「阅读」时倒计时重置回满格，不是全程共用一个池子。
//  这样「听力做慢了」不会连累阅读 —— 与真实考试的分段收卷一致。
//  倒计时归零直接交卷（不是弹窗问「要不要继续」，考场上不会有人问你）。
//
//  ## 状态丢失
//
//  考试状态在 `@State` 里，切到别的页签会丢 —— 与 Android 版行为一致。
//  所以答题时把板块切换器藏起来（`isSessionActive`），至少要挡住「手滑切到阅读」。

struct ExamScreen: View {

    @Environment(ProgressStore.self) private var store
    @Environment(ContentStore.self) private var content
    @Environment(AudioPlayer.self) private var audio

    /// 是否正在考试。父视图用它决定要不要显示板块切换器。
    @Binding var isSessionActive: Bool

    /// 一道模考题。与 `PaperItem` 分开是因为听力题没有原文段落，
    /// 而是「一段音频 + 一句泛问」—— 用一个专门的类型比给 `PaperItem`
    /// 塞一堆可选字段要清楚。
    private struct ExamItem: Identifiable {

        let id: String
        /// 部分名：听力 / 阅读
        let stage: String
        /// 记账用的题型：listen / read
        let kind: String
        /// 听力题的音频文本（阅读题为空）
        let audio: String
        let passage: [String]
        let q: String
        let o: [String]
        let a: Int
        let ex: String
    }

    private enum Phase: Equatable {
        case config
        case running
        case result
    }

    // MARK: - 状态

    @State private var phase: Phase = .config

    @State private var listenCount = 5
    @State private var readCount = 4
    @State private var limitSeconds = 300

    @State private var items: [ExamItem] = []
    @State private var index = 0
    @State private var correctCount = 0
    @State private var stage = "听力"
    @State private var secondsLeft = 0
    @State private var score = 0
    /// 当前这题作答了没有（决定「下一题」按钮出不出来）
    @State private var answeredCurrent = false

    /// 每秒一跳。放在 `@State` 里是为了让 publisher 只建一次 ——
    /// 写成 `let` 的话每次 body 求值都会新建一个定时器，倒计时会跳帧。
    @State private var ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // MARK: - 视图

    var body: some View {
        Group {
            switch phase {
            case .config:
                configPage
            case .running:
                runningPage
            case .result:
                resultPage
            }
        }
        .onReceive(ticker) { _ in
            tick()
        }
    }

    // ════════════════════════════════════════════════════════════════
    //  MARK: - 配置
    // ════════════════════════════════════════════════════════════════

    private var configPage: some View {
        ScrollView {
            VStack(spacing: Space.section) {
                VStack(spacing: Space.itemGap) {
                    SectionHeader("计时模考", subtitle: "按真实流程走一遍，中间不要停")

                    AppCard {
                        VStack(alignment: .leading, spacing: Space.lg) {
                            configRow("听力部分") {
                                Picker("听力题数", selection: $listenCount) {
                                    Text("5 题").tag(5)
                                    Text("10 题").tag(10)
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                            }

                            configRow("阅读部分") {
                                Picker("阅读题数", selection: $readCount) {
                                    Text("4 题").tag(4)
                                    Text("8 题").tag(8)
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                            }

                            configRow("每部分限时") {
                                Picker("每部分限时", selection: $limitSeconds) {
                                    Text("5 分钟").tag(300)
                                    Text("8 分钟").tag(480)
                                    Text("10 分钟").tag(600)
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                            }
                        }
                    }

                    Text("听力题取对话素材，阅读题从题库随机抽。全部做完才出分；某一部分时间用完就整卷交掉。")
                        .appCaption()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Space.xs)

                    PrimaryButton(
                        content.readings.isEmpty ? "题库没读到，暂时无法模考" : "开始模考",
                        icon: "timer",
                        enabled: !content.readings.isEmpty
                    ) {
                        start()
                    }
                    .padding(.top, Space.xs)
                }

                historySection
            }
            .padding(.horizontal, Space.pageEdge)
            .padding(.top, Space.md)
            .padding(.bottom, Space.xxl)
        }
    }

    /// 一组「标题 + 选项」。标题与选项之间固定 12pt ——
    /// 再紧一点标题会像选项的一部分，再松一点又像两个不相干的区块。
    private func configRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text(title)
                .font(Typography.captionEmph)
                .foregroundStyle(Theme.Colors.textSecondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ════════════════════════════════════════════════════════════════
    //  MARK: - 答题
    // ════════════════════════════════════════════════════════════════

    private var currentItem: ExamItem? {
        items.indices.contains(index) ? items[index] : nil
    }

    private var runningPage: some View {
        ScrollView {
            VStack(spacing: Space.itemGap) {
                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                    Text(stage)
                        .font(Typography.titleSmall)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer(minLength: 0)
                    Text(clock)
                        .font(Typography.bodyEmph)
                        .monospacedDigit()
                        .foregroundStyle(secondsLeft <= 60 ? Theme.Colors.error : Theme.Colors.primary)
                    Text("\(index + 1) / \(items.count)")
                        .font(Typography.micro)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                if let item = currentItem {
                    if item.kind == "listen" {
                        audioCard(item)
                    }

                    QuizView(
                        question: item.q,
                        options: item.o,
                        correctIndex: item.a,
                        explanation: item.ex,
                        passage: item.passage,
                        readAloud: nil
                    ) { chosen in
                        answeredCurrent = true
                        submit(chosen, for: item)
                    }
                    .id(item.id)
                }

                if answeredCurrent {
                    PrimaryButton(index + 1 < items.count ? "下一题" : "交卷", icon: "arrow.right") {
                        advance()
                    }
                    .padding(.top, Space.xs)
                }
            }
            .padding(.horizontal, Space.pageEdge)
            .padding(.top, Space.md)
            .padding(.bottom, Space.xxl)
        }
    }

    private func audioCard(_ item: ExamItem) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("先听录音，再作答")
                    .appCaption()

                HStack(spacing: Space.sm) {
                    Button {
                        _ = audio.togglePlay(text: item.audio)
                    } label: {
                        HStack(spacing: Space.xs) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 13, weight: .semibold))
                            Text("播放录音")
                                .font(Typography.captionEmph)
                        }
                        .foregroundStyle(Theme.Colors.onPrimary)
                        .padding(.horizontal, Space.lg)
                        .frame(height: Touch.min)
                        .background(Theme.Colors.primary, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)
                }

                // 只露个开头：模考时给全文等于直接给答案
                Text("（原文：\(String(item.audio.prefix(40)))…）")
                    .font(Typography.micro)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // ════════════════════════════════════════════════════════════════
    //  MARK: - 出分
    // ════════════════════════════════════════════════════════════════

    private var resultPage: some View {
        ScrollView {
            VStack(spacing: Space.section) {
                AppCard {
                    VStack(spacing: Space.md) {
                        VStack(spacing: Space.xs) {
                            Text("\(score)")
                                .font(Typography.display)
                                .monospacedDigit()
                                .foregroundStyle(Theme.Colors.primary)
                            Text(scoreCaption)
                                .appCaption()
                                .multilineTextAlignment(.center)
                        }

                        HStack(spacing: Space.sm) {
                            StatBox("\(correctCount)", "答对")
                            StatBox("\(items.count)", "总题")
                            StatBox("\(accuracyPercent)%", "正确率")
                        }

                        HStack(spacing: Space.sm) {
                            PrimaryButton("再考一次", icon: "arrow.clockwise") {
                                start()
                            }
                            SecondaryButton("回配置") {
                                phase = .config
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                historySection
            }
            .padding(.horizontal, Space.pageEdge)
            .padding(.top, Space.md)
            .padding(.bottom, Space.xxl)
        }
    }

    private var accuracyPercent: Int {
        guard !items.isEmpty else { return 0 }
        return correctCount * 100 / items.count
    }

    /// 425 是四级的传统「过线」分数。只说这一句判断，不预测真实成绩。
    private var scoreCaption: String {
        score >= 425 ? "估算得分 / 710 · 已经过线了" : "估算得分 / 710 · 继续加油"
    }

    // ════════════════════════════════════════════════════════════════
    //  MARK: - 历史成绩
    // ════════════════════════════════════════════════════════════════

    /// 最新的在最上面
    private var recentExams: [ExamRecord] {
        Array(store.progress.examHistory.reversed())
    }

    private var historySection: some View {
        VStack(spacing: Space.itemGap) {
            SectionHeader("历史成绩", subtitle: "最近的在上面", trailing: "\(recentExams.count) 次")

            if recentExams.isEmpty {
                ContentUnavailableView(
                    "还没有模考记录",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("考一次就知道现在大概在什么位置。")
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(recentExams.indices, id: \.self) { i in
                        historyRow(recentExams[i], isLast: i == recentExams.count - 1)
                    }
                }
                .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(Theme.Colors.separator, lineWidth: 1)
                }
            }
        }
    }

    private func historyRow(_ record: ExamRecord, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: Space.sm) {
                Text(record.date)
                    .font(Typography.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textSecondary)

                Spacer(minLength: Space.sm)

                Text("\(record.correct)/\(record.total)")
                    .font(Typography.micro)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textSecondary)

                Text("\(record.acc)%")
                    .font(Typography.micro)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(minWidth: 40, alignment: .trailing)

                Text("\(record.score)")
                    .font(Typography.captionEmph)
                    .monospacedDigit()
                    .foregroundStyle(record.score >= 425 ? Theme.Colors.primary : Theme.Colors.textPrimary)
                    .frame(minWidth: 44, alignment: .trailing)
            }
            .padding(.horizontal, Space.lg)
            .frame(minHeight: Touch.min)

            if !isLast {
                Divider().padding(.leading, Space.lg)
            }
        }
    }

    // ════════════════════════════════════════════════════════════════
    //  MARK: - 流程
    // ════════════════════════════════════════════════════════════════

    private func start() {
        let next = makeItems()
        guard !next.isEmpty else { return }

        items = next
        index = 0
        correctCount = 0
        answeredCurrent = false
        score = 0
        secondsLeft = limitSeconds
        stage = next[0].stage
        phase = .running
        isSessionActive = true
    }

    private func makeItems() -> [ExamItem] {
        var out: [ExamItem] = []

        // 听力题优先取「短对话」：场景题问的是「这段对话可能发生在哪」，
        // 用入门短句（单句、无场景）根本问不出来。
        let pool = content.listeningDialog.isEmpty ? content.allListening : content.listeningDialog
        let listenTexts = Array(pool.prefix(max(listenCount, 0)))
        for (offset, item) in listenTexts.enumerated() {
            out.append(
                ExamItem(
                    id: "e-l-\(offset)",
                    stage: "听力",
                    kind: "listen",
                    audio: item.en,
                    passage: [],
                    q: "这段对话最可能发生在什么场景？请先听录音，再选一个最符合的选项。",
                    o: ["工作或学习相关的日常交流", "正式的法庭审判", "体育运动解说", "天气预报播报"],
                    a: 0,
                    ex: "四级听力以校园、办公、生活场景的日常对话为主。原文：\(item.cn)"
                )
            )
        }

        let readPool = content.readings.shuffled().prefix(max(readCount, 0))
        for (offset, reading) in Array(readPool).enumerated() {
            out.append(
                ExamItem(
                    id: "e-r-\(offset)",
                    stage: "阅读",
                    kind: "read",
                    audio: "",
                    passage: reading.p,
                    q: reading.q,
                    o: reading.o,
                    a: reading.a,
                    ex: reading.ex
                )
            )
        }

        return out
    }

    /// 交一道题的答案。答对也要记账 —— 正确率的分母全靠 attempts。
    private func submit(_ chosen: Int, for item: ExamItem) {
        let ok = chosen == item.a
        if ok {
            correctCount += 1
        }
        store.recordAnswer(
            kind: item.kind,
            ok: ok,
            wrong: ok ? nil : WrongItem(
                q: item.q,
                chosen: chosen,
                right: item.a,
                from: "模考·\(item.stage)",
                type: "exam"
            )
        )
    }

    private func advance() {
        guard phase == .running else { return }
        if index + 1 < items.count {
            let next = items[index + 1]
            if next.stage != stage {
                // 换部分 → 倒计时重置回满格（分段收卷，不共用一个池子）
                stage = next.stage
                secondsLeft = limitSeconds
            }
            index += 1
            answeredCurrent = false
            audio.stop()
        } else {
            finish()
        }
    }

    private func finish() {
        guard phase == .running else { return }

        let total = items.count
        let accuracy = total == 0 ? 0.0 : Double(correctCount) / Double(total)
        let scaled = Int((710.0 * accuracy * 0.7 + 248.0).rounded())
        score = min(710, scaled)
        phase = .result
        isSessionActive = false
        audio.stop()

        store.addExam(
            ExamRecord(
                date: Srs.today(),
                correct: correctCount,
                total: total,
                acc: total == 0 ? 0 : correctCount * 100 / total,
                score: score
            )
        )
        store.bump("exam")
    }

    private func tick() {
        guard phase == .running else { return }
        if secondsLeft <= 1 {
            secondsLeft = 0
            finish()
        } else {
            secondsLeft -= 1
        }
    }

    private var clock: String {
        let total = max(secondsLeft, 0)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
