import AppKit
import MouseHelperCore
import SwiftUI

private enum PopoverTab: String, CaseIterable {
    case scroll = "中键滚动"
    case gestures = "右键手势"
}

struct PopoverView: View {
    @ObservedObject var store: SettingsStore
    let onRequestPermission: () -> Void
    let onQuit: () -> Void

    @State private var selectedTab: PopoverTab = .scroll

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection

            if !store.hasAccessibilityPermission {
                permissionBanner
            }

            Picker("功能分区", selection: $selectedTab) {
                ForEach(PopoverTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                switch selectedTab {
                case .scroll:
                    scrollTabContent
                case .gestures:
                    gesturesTabContent
                }
            }

            Divider()

            footerSection
        }
        .padding(16)
        .frame(width: 360)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 10) {
            if let appIcon = NSApplication.shared.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 40, height: 40)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(statusAccentColor.opacity(0.16))
                        .frame(width: 36, height: 36)
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(statusAccentColor)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("鼠标助手")
                    .font(.headline)
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusAccentColor)
                        .frame(width: 7, height: 7)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Toggle("", isOn: $store.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    private var statusAccentColor: Color {
        if !store.hasAccessibilityPermission {
            return .orange
        }
        if store.isEnabled && store.isTapRunning {
            return .green
        }
        return .secondary
    }

    private var statusText: String {
        if !store.hasAccessibilityPermission {
            return "需要「辅助功能」权限"
        }
        if !store.isEnabled {
            return "已暂停"
        }
        return store.isTapRunning ? "运行中 · 中键横滚 / 右键手势" : "正在启动监听…"
    }

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 14))
                VStack(alignment: .leading, spacing: 3) {
                    Text("尚未获得辅助功能权限")
                        .font(.subheadline.weight(.semibold))
                    Text("请在「系统设置 → 隐私与安全性 → 辅助功能」中允许 MouseHelper，开启后将自动生效。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button(action: onRequestPermission) {
                Label("打开辅助功能设置", systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.small)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.30), lineWidth: 1)
                )
        )
    }

    // MARK: - Tab 1: Middle-Button Scroll

    private var scrollTabContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            directionSection
            slidersSection
            Divider()
            scrollTogglesSection
            Divider()
            testStripSection
        }
    }

    private var directionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("横向滑动方向")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Picker("滑动方向", selection: $store.directionMode) {
                Text("视口跟随").tag(ScrollDirectionMode.viewportFollowsMouse)
                Text("页面跟随").tag(ScrollDirectionMode.contentFollowsMouse)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(directionDescription)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var directionDescription: String {
        switch store.directionMode {
        case .viewportFollowsMouse:
            return "按住中键向右滑 → 查看右侧内容（类似向右拨动横向滚轮）"
        case .contentFollowsMouse:
            return "按住中键向右滑 → 将页面向右拖动（类似触控板自然滚动）"
        }
    }

    private var slidersSection: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("滚动灵敏度")
                        .font(.subheadline)
                    Spacer()
                    Text(String(format: "%.1fx", store.sensitivity))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $store.sensitivity, in: 0.3...5.0, step: 0.1)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("中键防误触阈值")
                        .font(.subheadline)
                    Spacer()
                    Text("\(Int(store.dragThreshold)) px")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $store.dragThreshold, in: 2...16, step: 1)
                Text("移动距离小于阈值时松开，正常触发中键点击（如新标签页打开链接）")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var scrollTogglesSection: some View {
        VStack(spacing: 8) {
            toggleRow(
                title: "滑动时锁定光标位置",
                subtitle: "默认开启：按住中键滑动时光标固定不动，防止滑出窗口",
                isOn: $store.lockCursor
            )
            toggleRow(
                title: "普通鼠标滚轮反向滚动",
                subtitle: "仅反转普通鼠标滚轮，不影响系统设置、触控板与 Magic Mouse",
                isOn: $store.reverseMouseWheel
            )
            toggleRow(
                title: "平滑像素滚动",
                subtitle: "关闭后切换为传统步进滚轮模式",
                isOn: $store.smoothScrolling
            )
            toggleRow(
                title: "同时支持上下滑动",
                subtitle: "开启后按住中键也可进行纵向滚动",
                isOn: $store.enableVerticalScroll
            )
            toggleRow(
                title: "开机自动启动",
                subtitle: "登录 macOS 后在菜单栏静默运行",
                isOn: $store.launchAtLogin
            )
        }
    }

    private var testStripSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("实时测试区")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("在此按住中键左右滑动")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 8) {
                    ForEach(1...24, id: \.self) { index in
                        VStack(spacing: 2) {
                            Text("#\(index)")
                                .font(.caption.weight(.semibold).monospacedDigit())
                            Text(index % 2 == 0 ? "→" : "←")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 48, height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.accentColor.opacity(index % 2 == 0 ? 0.14 : 0.08))
                        )
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
            }
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Tab 2: Right-Click Gestures

    private var gesturesTabContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 8) {
                toggleRow(
                    title: "启用右键手势",
                    subtitle: "按住右键滑动触发动作，轻点右键仍正常弹出菜单",
                    isOn: $store.gesturesEnabled
                )

                toggleRow(
                    title: "右键手势炫酷拖影",
                    subtitle: "仅右键画手势时显示霓虹光轨与星火，松手渐隐消失",
                    isOn: $store.enableTrail
                )
                .disabled(!store.gesturesEnabled)
                .opacity(store.gesturesEnabled ? 1.0 : 0.5)

                if store.enableTrail && store.gesturesEnabled {
                    trailStylePicker
                }

                toggleRow(
                    title: "实时手势提示胶囊",
                    subtitle: "绘制手势时在屏幕下方提示当前动作（多划一笔可取消）",
                    isOn: $store.showGestureHUD
                )
                .disabled(!store.gesturesEnabled)
                .opacity(store.gesturesEnabled ? 1.0 : 0.5)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("手势动作列表")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("可逐项开关或切换动作")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                VStack(spacing: 5) {
                    ForEach(GesturePattern.allCases) { pattern in
                        gestureBindingRow(pattern: pattern)
                    }
                }
                .disabled(!store.gesturesEnabled)
                .opacity(store.gesturesEnabled ? 1.0 : 0.5)
            }
        }
    }

    private func gestureBindingRow(pattern: GesturePattern) -> some View {
        let binding = store.binding(for: pattern)

        return HStack(spacing: 8) {
            Text(pattern.symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(binding.isEnabled ? Color.accentColor : Color.secondary)
                .frame(width: 40, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(binding.isEnabled ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05))
                )

            Menu {
                ForEach(GestureActionType.allCases) { action in
                    Button {
                        store.setGestureAction(action, for: pattern)
                    } label: {
                        HStack {
                            Text("\(action.displayName)  (\(action.shortcutLabel))")
                            if binding.action == action {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(binding.action.displayName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(binding.isEnabled ? .primary : .secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(binding.action.shortcutLabel)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                )
            }
            .menuStyle(.borderlessButton)
            .disabled(!binding.isEnabled)

            Toggle("", isOn: Binding(
                get: { store.binding(for: pattern).isEnabled },
                set: { store.setGestureEnabled($0, for: pattern) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
        }
    }

    private var trailStylePicker: some View {
        HStack(spacing: 6) {
            ForEach(TrailStyle.allCases, id: \.self) { style in
                let isSelected = store.trailStyle == style
                Button {
                    store.trailStyle = style
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(trailStyleGradient(style))
                            .frame(width: 9, height: 9)
                        Text(style.displayName)
                            .font(.caption2.weight(isSelected ? .semibold : .regular))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(
                                        isSelected ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.08),
                                        lineWidth: 1
                                    )
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func trailStyleGradient(_ style: TrailStyle) -> LinearGradient {
        let colors: [Color]
        switch style {
        case .neonCyan:
            colors = [Color(red: 0.22, green: 0.86, blue: 0.98), Color(red: 0.42, green: 0.36, blue: 0.98)]
        case .cyberMagenta:
            colors = [Color(red: 0.96, green: 0.24, blue: 0.62), Color(red: 0.20, green: 0.90, blue: 0.98)]
        case .aurora:
            colors = [Color(red: 0.16, green: 0.90, blue: 0.62), Color(red: 0.25, green: 0.56, blue: 1.0), Color(red: 0.78, green: 0.34, blue: 0.96)]
        case .solarGold:
            colors = [Color(red: 1.0, green: 0.86, blue: 0.28), Color(red: 0.94, green: 0.26, blue: 0.22)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - Shared Helpers

    private func toggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private var footerSection: some View {
        HStack {
            Button("恢复默认") {
                store.resetToDefaults()
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()

            Button("退出鼠标助手", action: onQuit)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}
