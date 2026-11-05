import SwiftUI

// MARK: - 单词卡背面的详细资料
//
// 资料来自词典，单条最长能到 20 多条。卡片本身只有一屏高，
// 所以每一段都必须限条数：不限的话，翻个面要滑三屏才到底，
// 用户会以为卡片「坏掉了」。限条数后信息仍然够用，也保住了卡片的形状。
//
// 每段的标题用 captionEmph + 次要色：它是分隔符，不是内容，
// 视觉上要往后退一档，让英文和释义站在前面。

struct WordDetailSection: View {

    let detail: WordDetail

    // 没有资料时给一句话，而不是留一片空白：空白看起来像加载失败。
    private var hasRoot: Bool {
        guard let rel = detail.rel else { return false }
        return !rel.root.isEmpty || !rel.rels.isEmpty
    }

    private var isEmpty: Bool {
        detail.t.isEmpty
            && detail.s.isEmpty
            && detail.ph.isEmpty
            && detail.sy.isEmpty
            && !hasRoot
            && detail.et.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            if isEmpty {
                Text("这个词还没有更多资料。")
                    .appCaption()
            } else {
                if !detail.t.isEmpty { senses }
                if !detail.s.isEmpty { examples }
                if !detail.ph.isEmpty { phrases }
                if !detail.sy.isEmpty { synonyms }
                if hasRoot { rootFamily }
                if !detail.et.isEmpty { etymology }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 1. 释义分项

    private var senses: some View {
        segment("释义分项") {
            VStack(alignment: .leading, spacing: Space.sm) {
                ForEach(0..<min(detail.t.count, 4), id: \.self) { index in
                    let sense = detail.t[index]
                    HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                        Text(sense.pos)
                            .font(Typography.captionEmph)
                            .foregroundStyle(Theme.Colors.primary)
                        Text(sense.cn)
                            .appBody()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - 2. 更多例句

    private var examples: some View {
        segment("更多例句") {
            VStack(alignment: .leading, spacing: Space.md) {
                ForEach(0..<min(detail.s.count, 3), id: \.self) { index in
                    let term = detail.s[index]
                    VStack(alignment: .leading, spacing: 2) {
                        Text(term.c)
                            .font(Typography.micro)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(term.cn)
                            .font(Typography.micro)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - 3. 短语

    private var phrases: some View {
        segment("短语") {
            VStack(alignment: .leading, spacing: Space.sm) {
                ForEach(0..<min(detail.ph.count, 6), id: \.self) { index in
                    let term = detail.ph[index]
                    HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                        Text(term.c)
                            .font(Typography.captionEmph)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(term.cn)
                            .font(Typography.micro)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    // MARK: - 4. 同义

    private var synonyms: some View {
        segment("同义") {
            VStack(alignment: .leading, spacing: Space.md) {
                ForEach(0..<min(detail.sy.count, 4), id: \.self) { index in
                    let item = detail.sy[index]
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.cn)
                            .font(Typography.caption)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(item.ws.joined(separator: " / "))
                            .font(Typography.micro)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - 5. 词根词族

    @ViewBuilder
    private var rootFamily: some View {
        if let rel = detail.rel {
            segment("词根词族") {
                VStack(alignment: .leading, spacing: Space.sm) {
                    if !rel.root.isEmpty {
                        Text(rel.root)
                            .font(Typography.bodyEmph)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ForEach(0..<rel.rels.count, id: \.self) { index in
                        let item = rel.rels[index]
                        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                            Text(item.pos)
                                .font(Typography.captionEmph)
                                .foregroundStyle(Theme.Colors.primary)
                            // 词族里一串同根词，8 个足够看出构词方向；
                            // 再多会把这一段变成长列表，反而没有重点。
                            Text(item.words.prefix(8).map(\.c).joined(separator: " / "))
                                .font(Typography.micro)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 6. 词源

    private var etymology: some View {
        segment("词源") {
            VStack(alignment: .leading, spacing: Space.md) {
                ForEach(0..<min(detail.et.count, 2), id: \.self) { index in
                    let item = detail.et[index]
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(item.t)
                            .font(Typography.bodyEmph)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        // 词源常是一大段，必须允许纵向展开，否则会被截成一行。
                        ReadingPassage(text: item.d)
                    }
                }
            }
        }
    }

    // MARK: - 段落外壳

    private func segment<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(title)
                .font(Typography.captionEmph)
                .foregroundStyle(Theme.Colors.textSecondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
