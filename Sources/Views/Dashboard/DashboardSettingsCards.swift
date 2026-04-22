import SwiftUI

// MARK: - Section Card
/// Custom card container for a named settings section, replacing Form.Section.
/// Renders an amber-tinted section header above a rounded card body.
internal struct SettingsSectionCard<Content: View>: View {
    let title: String
    let icon: String
    let content: () -> Content

    init(
        title: String,
        icon: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header — amber icon + small-caps label
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(DashboardTheme.brand)
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(DashboardTheme.inkMuted)
            }
            .padding(.horizontal, 2)
            .padding(.bottom, DashboardTheme.Spacing.sm)

            // Card body
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DashboardTheme.cardBg)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(DashboardTheme.rule, lineWidth: 0.5)
            )
        }
    }
}

// MARK: - Row Divider
/// Left-indented divider between adjacent rows within a settings card.
internal struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, DashboardTheme.Spacing.md)
    }
}

// MARK: - Toggle Row
internal struct SettingsToggleRow: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: DashboardTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DashboardTheme.ink)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(DashboardTheme.inkMuted)
                }
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .tint(DashboardTheme.brand)
                .labelsHidden()
        }
        .padding(.horizontal, DashboardTheme.Spacing.md)
        .padding(.vertical, 10)
    }
}

// MARK: - Picker Row
internal struct SettingsPickerRow<Selection: Hashable>: View {
    let title: String
    let subtitle: String?
    @Binding var selection: Selection
    let options: [Selection]
    let display: (Selection) -> String

    init(
        title: String,
        subtitle: String? = nil,
        selection: Binding<Selection>,
        options: [Selection],
        display: @escaping (Selection) -> String = { "\($0)" }
    ) {
        self.title = title
        self.subtitle = subtitle
        _selection = selection
        self.options = options
        self.display = display
    }

    var body: some View {
        HStack(alignment: .center, spacing: DashboardTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DashboardTheme.ink)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(DashboardTheme.inkMuted)
                }
            }

            Spacer()

            Picker("", selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(display(option)).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
        .padding(.horizontal, DashboardTheme.Spacing.md)
        .padding(.vertical, 10)
    }
}

// MARK: - Button Row
internal struct SettingsButtonRow: View {
    let title: String
    let subtitle: String?
    let icon: String
    let role: ButtonRole?
    let action: () -> Void

    init(
        title: String,
        subtitle: String? = nil,
        icon: String = "arrow.right",
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            HStack(alignment: .center, spacing: DashboardTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(
                            role == .destructive ? DashboardTheme.destructive : DashboardTheme.ink)

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(DashboardTheme.inkMuted)
                    }
                }

                Spacer()

                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(
                        role == .destructive ? DashboardTheme.destructive : DashboardTheme.inkMuted)
            }
            .padding(.horizontal, DashboardTheme.Spacing.md)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Info Row
internal struct SettingsInfoRow: View {
    let text: String

    var body: some View {
        HStack(spacing: DashboardTheme.Spacing.sm) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(DashboardTheme.inkFaint)

            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(DashboardTheme.inkMuted)
        }
        .padding(.horizontal, DashboardTheme.Spacing.md)
        .padding(.vertical, 10)
    }
}

// MARK: - Label Value Row
/// Read-only key/value display row, used in About sections and metadata displays.
internal struct SettingsLabelValueRow: View {
    let label: String
    let value: String
    var isMono: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: DashboardTheme.Spacing.md) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DashboardTheme.ink)

            Spacer()

            Text(value)
                .font(isMono ? DashboardTheme.Fonts.mono(12) : .system(size: 12))
                .foregroundStyle(DashboardTheme.inkMuted)
                .textSelection(.enabled)
        }
        .padding(.horizontal, DashboardTheme.Spacing.md)
        .padding(.vertical, 10)
    }
}

// MARK: - Text Field Row
internal struct SettingsTextFieldRow: View {
    let title: String
    let subtitle: String?
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DashboardTheme.ink)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(DashboardTheme.inkMuted)
                }
            }

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.roundedBorder)
            .font(DashboardTheme.Fonts.sans(13))
        }
        .padding(.horizontal, DashboardTheme.Spacing.md)
        .padding(.vertical, 10)
    }
}
