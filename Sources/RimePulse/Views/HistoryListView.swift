import SwiftUI

struct HistoryListView: View {
    let history: [TypingStats]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("最近 7 天")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.bottom, 3)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(history) { day in
                    HistoryRowView(stats: day)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
        }
    }
}
