import CoreGraphics

// ════════════════════════════════════════════════════════════════════
//  间距 / 圆角 / 触控目标：全应用唯一出口
// ════════════════════════════════════════════════════════════════════
//
//  两条纪律：
//    ① 间距**只有 6 档**（4 / 8 / 12 / 16 / 24 / 32）。想用 10 就用 8 或 12，
//       不要新造数值 —— 一旦有了中间值，网格就散了。
//    ② 语义别名优先于裸数值。写 `Space.section` 而不是 `24`，
//       以后统一调密度时改一处就够。

enum Space {
    /// 4 —— 图标与文字之间、芯片横向内边距
    static let xs: CGFloat = 4
    /// 8 —— 紧密相关的两个元素（标题与副标题）
    static let sm: CGFloat = 8
    /// 12 —— 列表项内部上下留白、输入块与提示语之间
    static let md: CGFloat = 12
    /// 16 —— 页面左右边距、卡片内边距（最常用的一档）
    static let lg: CGFloat = 16
    /// 24 —— 区块与区块之间
    static let xl: CGFloat = 24
    /// 32 —— 页面级大分区，一屏只用一两次
    static let xxl: CGFloat = 32

    /// 页面左右边距
    static let pageEdge: CGFloat = lg
    /// 区块之间的垂直间距
    static let section: CGFloat = xl
    /// 卡片内边距
    static let cardPadding: CGFloat = lg
    /// 列表项之间的间距
    static let itemGap: CGFloat = md
}

enum Radius {
    /// 面板档：卡片 / 弹窗 / 输入块。
    /// 唯一取值，想分层次请用底色与描边，不要引入第二个圆角。
    static let card: CGFloat = 14
    /// 紧凑面板（列表行里的小块）
    static let field: CGFloat = 12
    /// 控件档：胶囊（按钮 / 芯片 / 标签）
    static let pill: CGFloat = 999
}

enum Touch {
    /// 最小触控目标。低于这个值手指点不准 —— 视觉尺寸可以小，热区不能小。
    static let min: CGFloat = 44
}
