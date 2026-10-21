import Foundation
import SwiftUI

// ════════════════════════════════════════════════════════════════════
//  翻译工具
// ════════════════════════════════════════════════════════════════════
//
//  三块，从上到下：
//    ① 中英文互译 —— 联网调免费的 MyMemory 接口；
//    ② 翻译练习 —— 汉译英，先自己译再看参考译文与要点；
//    ③ 常考翻译词组 —— 点开看中文，带朗读。
//
//  ## 为什么翻译是唯一需要联网的功能
//
//  单词、听力、阅读、真题、模考全部离线（音频都在包里）。只有「随手中英互译」
//  这件事没有本地数据可查 —— 要么接一个在线接口，要么不做。所以这里只让它
//  联网，并且**失败也不影响任何其它功能**：网络断了，这一块显示一行提示，
//  下面两块（离线题库）照常可用。
//
//  ## 为什么用 `URLComponents` 而不是手拼字符串
//
//  手拼 `"?q=" + 文本` 在遇到 `&`、`#`、`+` 或换行时会直接拼出错误请求
//  （甚至被中间的 `&` 截成两个参数）。`URLComponents` 会替我们做转义，
//  包括中文字符和 `langpair` 里那个 `|`。

struct TranslateScreen: View {

    @Environment(ProgressStore.self) private var store
    @Environment(ContentStore.self) private var content
    @Environment(AudioPlayer.self) private var audio

    private enum Direction: String, CaseIterable, Identifiable {
        case enToZh
        case zhToEn

        var id: String { rawValue }

        var title: String {
            switch self {
            case .enToZh: return "英 → 中"
            case .zhToEn: return "中 → 英"
            }
        }

        /// MyMemory 的 langpair 参数格式
        var langPair: String {
            switch self {
            case .enToZh: return "en|zh-CN"
            case .zhToEn: return "zh-CN|en"
            }
        }

        var caption: String {
            switch self {
            case .enToZh: return "英→中"
            case .zhToEn: return "中→英"
            }
        }

        var placeholder: String {
            switch self {
            case .enToZh: return "粘贴或输入英文，比如 The exam is next month."
            case .zhToEn: return "粘贴或输入中文，比如 这次考试在下个月。"
            }
        }
    }

    @State private var direction: Direction = .enToZh
    @State private var input = ""
    @State private var output = ""
    @State private var status = ""
    @State private var isError = false
    @State private var isLoading = false

    /// 展开的练习 / 词组（用 id 而不是布尔数组：列表顺序变了也不会错位）
    @State private var openedPractices: Set<String> = []
    @State private var openedPhrases: Set<String> = []

    // MARK: - 视图

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: Space.section) {
                    translatorSection
                    practiceSection
                    phraseSection
                }
                .padding(.horizontal, Space.pageEdge)
                .padding(.top, Space.md)
                .padding(.bottom, Space.xxl)
            }
        }
        .navigationTitle("翻译工具")
        .navigationBarTitleDisplayMode(.inline)
    }

    // ════════════════════════════════════════════════════════════════
    //  MARK: - 中英文互译
    // ════════════════════════════════════════════════════════════════

    private var translatorSection: some View {
        VStack(spacing: Space.itemGap) {
            SectionHeader(
                "中英文互译",
                subtitle: "联网即用；断网时只是这一项不能翻"
            )

            AppCard {
                VStack(alignment: .leading, spacing: Space.md) {
                    Picker("方向", selection: $direction) {
                        ForEach(Direction.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $input)
                            .font(Typography.body)
                            .frame(height: 110)
                            .scrollContentBackground(.hidden)
                            .padding(Space.sm)
                            .background(
                                Theme.Colors.surfaceMuted,
                                in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                            )

                        if input.isEmpty {
                            Text(direction.placeholder)
                                .font(Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .padding(.horizontal, Space.lg)
                                .padding(.vertical, Space.md)
                                .allowsHitTesting(false)
                        }
                    }

                    Button {
                        translate()
                    } label: {
                        HStack(spacing: Space.xs) {
                            if isLoading {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.left.arrow.right")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            Text(isLoading ? "翻译中…" : "翻译")
                                .font(Typography.captionEmph)
                        }
                        .foregroundStyle(Theme.Colors.onPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: Touch.min)
                        .background(
                            Theme.Colors.primary.opacity(isLoading ? 0.5 : 1),
                            in: Capsule()
                        )
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading)

                    if !output.isEmpty {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Divider()
                            Text(output)
                                .appBody()
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, Space.sm)
                        }
                        .transition(.opacity)
                    }

                    if !status.isEmpty {
                        Text(status)
                            .appCaption(isError ? Theme.Colors.error : Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // ════════════════════════════════════════════════════════════════
    //  MARK: - 翻译练习
    // ════════════════════════════════════════════════════════════════

    private var practiceSection: some View {
        VStack(spacing: Space.itemGap) {
            SectionHeader(
                "翻译练习",
                subtitle: "汉译英：先自己译，再看参考",
                trailing: "\(content.transPractices.count) 段"
            )

            if content.transPractices.isEmpty {
                ContentUnavailableView(
                    "暂无翻译练习",
                    systemImage: "text.book.closed",
                    description: Text("检查一下 Resources/Content/trans_practice.json。")
                )
            } else {
                ForEach(content.transPractices) { item in
                    practiceCard(item)
                }
            }
        }
    }

    private func practiceCard(_ item: TransPractice) -> some View {
        let opened = openedPractices.contains(item.id)

        return AppCard {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text(item.cn)
                    .font(Typography.bodyEmph)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if opened {
                    Divider()
                        .padding(.vertical, Space.xs)

                    Text(item.ref)
                        .appBody()
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(item.tips.indices, id: \.self) { index in
                        Text("· \(item.tips[index])")
                            .appCaption()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // 这里**不放**朗读按钮：参考译文是一整段中文腔调的英文，
                    // 离线包里没有对应音频，点了只会毫无反应 ——
                    // 一个点了没动静的按钮比没有这个按钮更糟。
                }

                HStack(spacing: Space.sm) {
                    pillButton(
                        opened ? "收起参考" : "看参考译文",
                        icon: opened ? "chevron.up" : "chevron.down",
                        filled: false
                    ) {
                        withAnimation(.snappy) { togglePractice(item) }
                    }

                    pillButton("没记住", icon: "bookmark", filled: false) {
                        remember(item)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.top, Space.xs)
            }
        }
    }

    // ════════════════════════════════════════════════════════════════
    //  MARK: - 常考翻译词组
    // ════════════════════════════════════════════════════════════════

    private var phraseSection: some View {
        VStack(spacing: Space.itemGap) {
            SectionHeader(
                "常考翻译词组",
                subtitle: "点开看中文释义",
                trailing: "\(content.phrases.count) 条"
            )

            if content.phrases.isEmpty {
                ContentUnavailableView(
                    "暂无词组",
                    systemImage: "textformat",
                    description: Text("检查一下 Resources/Content/phrases.json。")
                )
            } else {
                ForEach(content.phrases) { phrase in
                    phraseCard(phrase)
                }
            }
        }
    }

    private func phraseCard(_ phrase: Phrase) -> some View {
        let opened = openedPhrases.contains(phrase.id)

        return AppCard(padding: Space.lg) {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(spacing: Space.sm) {
                    // 整行只有文字区可点：把发音按钮也包进同一颗按钮里，
                    // 点喇叭会连带把卡片展开，两个动作互相打架。
                    Button {
                        withAnimation(.snappy) { togglePhrase(phrase) }
                    } label: {
                        Text(phrase.en)
                            .font(Typography.bodyEmph)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    SoundChip("读") {
                        _ = audio.togglePlay(text: phrase.en)
                    }
                }

                if opened {
                    Text(phrase.cn)
                        .appBody(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    pillButton("没记住", icon: "bookmark", filled: false) {
                        rememberPhrase(phrase)
                    }
                }
            }
        }
    }

    // ════════════════════════════════════════════════════════════════
    //  MARK: - 动作
    // ════════════════════════════════════════════════════════════════

    private func translate() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            isError = true
            status = "先输入要翻译的内容。"
            return
        }

        var components = URLComponents(string: "https://api.mymemory.translated.net/get")
        components?.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "langpair", value: direction.langPair)
        ]
        guard let url = components?.url else {
            isError = true
            status = "翻译失败：请求地址拼不出来。"
            return
        }

        isLoading = true
        isError = false
        status = ""
        output = ""

        Task { @MainActor in
            defer { isLoading = false }

            do {
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.timeoutInterval = 12

                let (data, _) = try await URLSession.shared.data(for: request)
                guard
                    let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let payload = root["responseData"] as? [String: Any],
                    let translated = payload["translatedText"] as? String,
                    !translated.isEmpty
                else {
                    isError = true
                    status = "翻译失败：接口没有返回内容。"
                    return
                }

                output = translated
                status = "来源：MyMemory 免费接口 · \(direction.caption)"
            } catch {
                isError = true
                status = "翻译失败：\(error.localizedDescription)（离线时只有这一项用不了，其它功能不受影响）"
            }
        }
    }

    private func togglePractice(_ item: TransPractice) {
        if openedPractices.contains(item.id) {
            openedPractices.remove(item.id)
        } else {
            openedPractices.insert(item.id)
        }
    }

    private func togglePhrase(_ phrase: Phrase) {
        if openedPhrases.contains(phrase.id) {
            openedPhrases.remove(phrase.id)
        } else {
            openedPhrases.insert(phrase.id)
        }
    }

    /// 翻译练习没有选项，所以 `chosen` 记 -1（表示「没作答」），`right` 记 0。
    /// `ref` 存参考译文：错题集里只显示题干，靠这条能找回原文。
    private func remember(_ item: TransPractice) {
        store.addWrong(
            WrongItem(
                q: item.cn,
                chosen: -1,
                right: 0,
                from: "翻译练习",
                type: "translate",
                ref: item.ref
            )
        )
    }

    /// 词组把中英都存进去：错题集里一行就能看全，不用再回头查。
    private func rememberPhrase(_ phrase: Phrase) {
        store.addWrong(
            WrongItem(
                q: phrase.en,
                chosen: -1,
                right: 0,
                from: "翻译词组",
                type: "phrase",
                en: phrase.en,
                cn: phrase.cn
            )
        )
    }

    // MARK: - 小部件

    /// 卡片里的小胶囊按钮。`filled = true` 是主色实心，否则是浅底描边感。
    private func pillButton(
        _ title: String,
        icon: String,
        filled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(Typography.micro)
            }
            .foregroundStyle(filled ? Theme.Colors.onPrimary : Theme.Colors.primary)
            .padding(.horizontal, Space.md)
            .frame(height: 32)
            .background(
                filled ? Theme.Colors.primary : Theme.Colors.primarySoft,
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
