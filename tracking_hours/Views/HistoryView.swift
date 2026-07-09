import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: TimeTrackerStore
    @State private var selectedDay: DaySummary.ID?

    let openDay: (Date) -> Void

    private var summaries: [DaySummary] {
        store.historySummaries()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if summaries.isEmpty {
                EmptyStateView(
                    systemImage: "clock.arrow.circlepath",
                    title: "No history yet",
                    message: "Once you add time entries, each day will appear here with its total and balance."
                )
            } else {
                VStack(spacing: 12) {
                    Table(summaries, selection: $selectedDay) {
                        TableColumn("Date") { summary in
                            Text(AppFormatters.shortDateFormatter.string(from: summary.date))
                        }
                        TableColumn("Total") { summary in
                            Text("\(summary.totalHours.hoursText)h")
                                .monospacedDigit()
                        }
                        TableColumn("Balance") { summary in
                            Text(summary.balanceText)
                                .foregroundStyle(balanceColor(for: summary))
                        }
                        TableColumn("Tickets") { summary in
                            Text("\(summary.distinctTicketCount)")
                                .monospacedDigit()
                        }
                    }

                    HStack {
                        Text("\(summaries.count) days with entries")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            if let selectedDay {
                                openDay(selectedDay)
                            }
                        } label: {
                            Label("Open day", systemImage: "arrow.forward.circle")
                        }
                        .disabled(selectedDay == nil)
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("History")
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("History")
                    .font(.title2.weight(.semibold))
                Text("Review previous logged days")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func balanceColor(for summary: DaySummary) -> Color {
        if summary.pendingHours > 0.005 {
            return .orange
        }

        if summary.excessHours > 0.005 {
            return .blue
        }

        return .green
    }
}
