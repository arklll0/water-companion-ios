import SwiftUI

// MARK: - 讲义正文
//
// 长文页面有两条硬要求：
//   ① 正文必须用 LazyVStack。最长一篇 16 651 字、197 个块，
//      VStack 会在进入页面时一次性 measure 全部子视图，肉眼可见地卡住。
//   ② 「返回目录」固定在顶部，不跟着正文滚走。读到第 8000 字想换一篇时，
//      不用先滑回最上面。
//
// 字号与行距全部走 Typography：`.appBody()` 已经带了 +6 的行距，
// 中文长段落靠这个才不「挤成一饼」。

struct LessonScreen: View {

    let lesson: LectureLesson
    let onBack: () -> Void

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                topBar

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Space.lg) {
                        header

                        if lesson.blocks.isEmpty {
                            Text("这一篇还没有内容。")
                                .appCaption()
                        } else {
                            ForEach(lesson.blocks.indices, id: \.self) { index in
                                blockView(lesson.blocks[index])
                            }
                        }
                    }
                    .padding(.horizontal, Space.pageEdge)
                    .padding(.top, Space.md)
                    .padding(.bottom, Space.xxl)
                }
            }
        }
    }

    // MARK: - 固定顶栏

    private var topBar: some View {
        HStack(spacing: Space.sm) {
            QuietButton("返回目录", icon: "chevron.left", action: onBack)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.pageEdge)
        .padding(.vertical, Space.xs)
        // 顶栏要有不透明底色：正文从它下面滚过时不能透出来。
        .background(Theme.Colors.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.Colors.separator)
                .frame(height: 1)
        }
    }

    // MARK: - 篇名

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(lesson.title)
                .font(Typography.title)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(lesson.minutes) 分钟 · 约 \(lesson.charCount) 字")
                .font(Typography.micro)
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    // MARK: - 块

    @ViewBuilder
    private func blockView(_ block: LectureBlock) -> some View {
        switch block.k {
        case "h":
            // 小标题靠额外的上间距和正文拉开层次。LazyVStack 本身已有
            // Space.lg 的块间距，这里再加一档，读起来才知道「换节了」。
            Text(block.s)
                .font(Typography.title)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.lg)

        case "p":
            if !block.s.isEmpty {
                Text(block.s)
                    .appBody()
                    // 不锁宽度的话，长段落会被压成一行再截断。
                    .fixedSize(horizontal: false, vertical: true)
            }

        case "l":
            if !block.items.isEmpty {
                VStack(alignment: .leading, spacing: Space.sm) {
                    ForEach(block.items.indices, id: \.self) { index in
                        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                            // 用实心圆点而不是连字符：连字符和正文里的减号长得一样，
                            // 视觉上分不出「这是列表」。
                            Text("•")
                                .font(Typography.body)
                                .foregroundStyle(Theme.Colors.primary)
                            Text(block.items[index])
                                .appBody()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

        case "t":
            if !block.rows.isEmpty {
                tableView(block.rows)
            }

        default:
            EmptyView()
        }
    }

    // MARK: - 表格

    private func tableView(_ rows: [[String]]) -> some View {
        // 行可能长短不一，列数取最长的一行；缺的格子按空串补，
        // 这样每一列的宽度在各行之间仍然是对齐的。
        let columnCount = rows.map(\.count).max() ?? 0

        return AppCard(padding: Space.md) {
            VStack(spacing: 0) {
                ForEach(rows.indices, id: \.self) { rowIndex in
                    HStack(alignment: .top, spacing: Space.sm) {
                        ForEach(Array(0..<columnCount), id: \.self) { columnIndex in
                            cell(
                                rows[rowIndex],
                                column: columnIndex,
                                isHeader: rowIndex == 0
                            )
                        }
                    }
                    .padding(.vertical, Space.sm)

                    if rowIndex < rows.count - 1 {
                        Rectangle()
                            .fill(Theme.Colors.separator)
                            .frame(height: 1)
                    }
                }
            }
        }
    }

    private func cell(_ row: [String], column: Int, isHeader: Bool) -> some View {
        // maxWidth: .infinity 让各列等分；纵向 fixedSize 允许长单元格折行。
        Text(row.indices.contains(column) ? row[column] : "")
            .font(isHeader ? Typography.captionEmph : Typography.micro)
            .foregroundStyle(isHeader ? Theme.Colors.primary : Theme.Colors.textPrimary)
            .lineSpacing(Typography.captionLineSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
