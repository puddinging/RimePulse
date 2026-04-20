import SwiftUI

// MARK: - Period segmented (⌘[ / ⌘])

struct PeriodSegmented: View {
    @Binding var selected: TimeRange
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(TimeRange.allCases) { range in
                    segmentButton(for: range)
                }
            }
            .padding(2)
            .background(Capsule().fill(.quaternary.opacity(0.4)))
        }
        .animation(.snappy(duration: 0.22), value: selected)
        .background {
            // 不可见快捷键
            VStack(spacing: 0) {
                Button("") { shift(-1) }
                    .keyboardShortcut("[", modifiers: .command)
                Button("") { shift(1) }
                    .keyboardShortcut("]", modifiers: .command)
            }
            .opacity(0)
            .allowsHitTesting(false)
        }
    }

    private func shift(_ delta: Int) {
        let all = TimeRange.allCases
        guard let idx = all.firstIndex(of: selected) else { return }
        let next = (idx + delta + all.count) % all.count
        selected = all[next]
    }

    private func segmentButton(for range: TimeRange) -> some View {
        let isOn = selected == range
        return Button {
            selected = range
        } label: {
            Text(range.label)
                .font(.system(size: 9.5, weight: isOn ? .semibold : .regular))
                .tracking(0.5)
                .foregroundStyle(isOn ? .primary : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(
            isOn ? Glass.regular.interactive() : Glass.identity,
            in: Capsule()
        )
        .glassEffectID(range, in: glass)
    }
}

// MARK: - Metric tab pill (⌘1–⌘5)

struct MetricTabButton: View {
    let title: String
    let isOn: Bool
    let tint: Color
    let shortcut: KeyEquivalent
    let glassID: TrendMetric
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: isOn ? .semibold : .regular))
                .tracking(0.2)
                .foregroundStyle(isOn ? tint : .secondary)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcut, modifiers: .command)
        .help("切换到\(title) (⌘\(String(shortcut.character)))")
        .glassEffect(
            isOn
                ? Glass.regular.tint(tint.opacity(0.28)).interactive()
                : Glass.identity,
            in: Capsule()
        )
        .glassEffectID(glassID, in: namespace)
    }
}

// MARK: - Totals cell

struct TotalCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.system(size: 8.5))
                .tracking(0.6)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .contentTransition(.numericText(countsDown: false))
                .animation(.snappy(duration: 0.25), value: value)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
