import SwiftUI
import SwiftData

struct PreloadedEmailTicketItem: Identifiable {
    let id: UUID
    let ticket: EmailContent
    let accountEmail: String
    var state: PreloadState
}

struct EmailTrainImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    @Binding var preloadedTickets: [PreloadedEmailTicketItem]
    let preparedTrains: [UUID: PreparedEmailTrain]
    var onTrainAdded: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            Group {
                if linkedAccounts.isEmpty {
                    ContentUnavailableView {
                        Label("No email linked", systemImage: "envelope.badge.exclamationmark")
                    } description: {
                        Text("Add an email account in Profile → Email to import Trenitalia check-in tickets.")
                    }
                    .fontDesign(app_font_design)
                } else if preloadedTickets.isEmpty {
                    ContentUnavailableView(
                        "No upcoming tickets",
                        systemImage: "envelope",
                        description: Text("No Trenitalia self-check-in emails were found for your linked accounts.")
                    )
                    .fontDesign(app_font_design)
                } else {
                    List {
                        Section {
                            ForEach(preloadedTickets) { item in
                                ticketRow(item)
                            }
                        } header: {
                            Text("\(preloadedTickets.count) \(preloadedTickets.count == 1 ? "ticket" : "tickets")")
                        } footer: {
                            Text("Tap a ticket to add it to Today.")
                        }
                        .fontDesign(app_font_design)
                    }
                    .listSectionSpacing(32)
                    .scrollIndicators(.hidden)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("From Email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
        .background(app_background_color.ignoresSafeArea())
    }

    private var linkedAccounts: [Emails] {
        profiles.first?.emails ?? []
    }

    @ViewBuilder
    private func ticketRow(_ item: PreloadedEmailTicketItem) -> some View {
        Button {
            addTicket(item)
        } label: {
            EmailTicketRow(ticket: item.ticket)
                .overlay(alignment: .trailing) {
                    switch item.state {
                    case .loading:
                        ProgressView()
                            .padding(.trailing, 16)
                    case .unavailable:
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .padding(.trailing, 16)
                    case .ready:
                        EmptyView()
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(item.state != .ready)
        .opacity(item.state == .unavailable ? 0.55 : 1)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func addTicket(_ item: PreloadedEmailTicketItem) {
        guard item.state == .ready,
              let prepared = preparedTrains[item.id] else { return }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        EmailTrainService.savePreparedTrain(
            prepared,
            modelContext: modelContext,
            profile: profiles.first
        )
        onTrainAdded?()
        dismiss()
    }
}

struct EmailTicketRow: View {
    let ticket: EmailContent

    private var displayDate: Date {
        ticket.departureDate ?? ticket.date
    }

    private var title: String {
        let destination = stationCity(ticket.arrivalStation)
        if destination.isEmpty {
            return ticket.trainNumber.isEmpty ? String(localized: "Ticket") : "Train \(ticket.trainNumber)"
        }
        return destination
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            DepartureCalendarBadge(date: displayDate)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .fontDesign(app_font_design)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        let weekday = displayDate.formatted(.dateTime.weekday(.abbreviated))
        let time = displayDate.formatted(date: .omitted, time: .shortened)

        if ticket.departureStation.isEmpty {
            return "\(weekday) · \(time)"
        }

        return "\(ticket.departureStation) · \(weekday) · \(time)"
    }

    private func stationCity(_ station: String) -> String {
        station.split(separator: " ").first.map(String.init) ?? station
    }
}

struct DepartureCalendarBadge: View {
    let date: Date

    var body: some View {
        VStack(spacing: 0) {
            Text(date.formatted(.dateTime.month(.abbreviated)).uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.red)

            Text(date.formatted(.dateTime.day()))
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
        }
        .frame(width: 44, height: 48)
        .background(Color(.gray), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.35), lineWidth: 0.5)
        }
    }
}
