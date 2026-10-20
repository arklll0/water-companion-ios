import SwiftUI
import UIKit

// ════════════════════════════════════════════════════════════════════
//  颜色：全 App 唯一的取色出口
// ════════════════════════════════════════════════════════════════════
//
//  页面代码里**不允许**出现 `Color(red:…)` 或 `Color.white` 这类裸色值，
//  一律走 `Theme.Colors.xxx`。换色时只改这一个文件。
//
//  深浅两套值用 `UIColor(dynamicProvider:)` 承载：系统切换外观时 UIKit 会
//  重新求值，SwiftUI 拿到新的 resolved color，**不需要重启、不需要手动监听**。
//  这比在视图里读 `@Environment(\.colorScheme)` 再分支要可靠 ——
//  分支写法一旦漏掉某个叶子节点，就会出现「深色模式下有一块是白的」。
//
//  色值来源：Android 版 `ui/theme/Theme.kt`（墨绿 #0E5F4B 锚点），
//  深色模式下主色提亮成 #5FC7A0 —— 同一个色相在互换角色，不是第二个品牌色。

// MARK: - 十六进制

extension UIColor {
    /// 用 0xRRGGBB 构造不透明色。
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}

extension Color {
    /// 固定色（不随明暗变化），只用于品牌色阶这类「绝对色板」。
    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }

    /// 随系统外观自动翻转的语义色。
    /// - Parameters:
    ///   - light: 浅色模式取值（0xRRGGBB）
    ///   - dark: 深色模式取值（0xRRGGBB）
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

// MARK: - 主题

/// 设计 token。所有颜色 / 字体 / 间距的唯一出口。
enum Theme {

    /// 品牌色阶（绝对色板，不随明暗翻转）。
    /// 色相锁死 165°、只动亮度，所以任意两档摆在一起都天然是一家人。
    enum Brand {
        static let t50 = Color(hex: 0xE8F2EF)
        static let t100 = Color(hex: 0xCFE5DE)
        static let t200 = Color(hex: 0xA6CFC4)
        static let t300 = Color(hex: 0x6FB3A0)
        static let t400 = Color(hex: 0x35937B)
        static let t500 = Color(hex: 0x0E5F4B)
        static let t600 = Color(hex: 0x0B4E3D)
        static let t700 = Color(hex: 0x09402F)
        static let t800 = Color(hex: 0x073324)
        static let t900 = Color(hex: 0x05271B)
    }

    /// 语义槽位（随明暗模式翻转）。
    enum Colors {
        /// 品牌主色：浅色墨绿 / 深色提亮墨绿
        static let primary = Color(light: 0x0E5F4B, dark: 0x5FC7A0)
        /// 压在主色上的文字（按钮标题、完成徽标的勾）
        static let onPrimary = Color(light: 0xFFFFFF, dark: 0x052018)
        /// 主色的低饱和容器（浅底强调块）
        static let primarySoft = Color(light: 0xCFE5DE, dark: 0x143D31)
        /// 页面底色
        static let background = Color(light: 0xF6F7F8, dark: 0x101316)
        /// 卡片 / 内容面
        static let surface = Color(light: 0xFFFFFF, dark: 0x181B1F)
        /// 比 surface 再低一档的容器（列表行、分段底槽）
        static let surfaceMuted = Color(light: 0xF2F3F4, dark: 0x1E2226)
        /// 主文字
        static let textPrimary = Color(light: 0x16191D, dark: 0xE8EAEC)
        /// 次文字 / 说明
        static let textSecondary = Color(light: 0x5B636B, dark: 0x9BA3AB)
        /// 分隔线 / 卡片描边（装饰性，不承担信息）
        static let separator = Color(light: 0xE3E6E9, dark: 0x2A3138)
        /// 完成态卡片底色
        static let doneCard = Color(light: 0xE4EFEA, dark: 0x14352B)
        /// 完成态卡片上的文字
        static let doneText = Color(light: 0x09402F, dark: 0xA9DCC4)
        /// 完成态卡片描边
        static let doneEdge = Color(light: 0xA6CFC4, dark: 0x23513F)
        /// 进度环底槽
        static let ringTrack = Color(light: 0xCFE5DE, dark: 0x223028)
        /// 横幅 / 提示条底色
        static let banner = Color(light: 0xE8F2EF, dark: 0x16332A)
        /// 错误色
        static let error = Color(light: 0xA3312A, dark: 0xE8837B)
        /// 功能性描边（空心圈、未选中控件）
        static let outline = Color(light: 0x767D85, dark: 0x6A727C)
        /// 未选中图标
        static let idle = Color(light: 0x8A929A, dark: 0x7E868E)
    }

    /// 主题模式（与存档 `theme` 字段取值一一对应）
    enum Mode: String, CaseIterable, Identifiable {
        case auto
        case light
        case dark

        var id: String { rawValue }

        var label: String {
            switch self {
            case .auto: return "跟随系统"
            case .light: return "浅色"
            case .dark: return "深色"
            }
        }

        /// 存档里可能是旧值 / 网站导出的任意字符串，认不出的按「跟随系统」处理
        static func fromKey(_ key: String?) -> Mode {
            guard let key, let m = Mode(rawValue: key) else { return .auto }
            return m
        }

        /// 交给 `.preferredColorScheme`：auto 返回 nil 表示跟随系统
        var colorScheme: ColorScheme? {
            switch self {
            case .auto: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }
}
