import SwiftUI
import SwiftData
import UIKit

struct EmailInboxView: View {
    let emailID: UUID

    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @State private var isSyncing = false
    @State private var isLoadingDetails = false
    @State private var errorMessage: String?

    private var emailAccount: Emails? {
        profiles.first?.emails.first { $0.id == emailID }
    }

    private var tickets: [EmailContent] {
        (emailAccount?.content ?? []).sorted {
            ($0.departureDate ?? $0.date) > ($1.departureDate ?? $1.date)
        }
    }

    var body: some View {
        Group {
            if let emailAccount {
                Group {
                    if isSyncing && tickets.isEmpty {
                        ProgressView("Syncing emails...")
                    } else if let errorMessage, tickets.isEmpty {
                        ContentUnavailableView(errorMessage, systemImage: "exclamationmark.triangle")
                    } else if tickets.isEmpty {
                        ContentUnavailableView(
                            "No check-in emails",
                            systemImage: "envelope",
                            description: Text("No Trenitalia self-check-in emails were found.")
                        )
                    } else {
                        List {
                            ForEach(tickets) { ticket in
                                NavigationLink {
                                    emailTicketDetail(ticket)
                                } label: {
                                    EmailTicketRow(ticket: ticket)
                                }
                            }
                        }
                        .scrollContentBackground(.hidden)
                        .background(app_background_color)
                    }
                }
                .navigationTitle(emailAccount.email)
                .navigationSubtitle(isSyncing ? "Syncing emails..." : isLoadingDetails ? "Loading ticket details..." : "")
                .fontDesign(.rounded)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button {
                                Task { await syncEmails(for: emailAccount) }
                            } label: {
                                Label("Refresh new emails", systemImage: "arrow.clockwise")
                            }
                            .disabled(isSyncing || isLoadingDetails)

                            Section("Danger zone") {
                                Button(role: .destructive) {
                                    Task { await reloadAllEmails(for: emailAccount) }
                                } label: {
                                    Label("Reload all emails", systemImage: "trash")
                                }
                                .disabled(isSyncing || isLoadingDetails)
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "Email account not found",
                    systemImage: "envelope.badge.exclamationmark"
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(app_background_color)
    }

    @ViewBuilder
    private func emailTicketDetail(_ ticket: EmailContent) -> some View {
        let liveTicket = tickets.first { $0.id == ticket.id } ?? ticket

        List {
            Section("Journey") {
                LabeledContent("Train", value: liveTicket.trainNumber.isEmpty ? "—" : liveTicket.trainNumber)
                LabeledContent("From", value: liveTicket.departureStation.isEmpty ? "—" : liveTicket.departureStation)
                LabeledContent("To", value: liveTicket.arrivalStation.isEmpty ? "—" : liveTicket.arrivalStation)
                LabeledContent("Departure") {
                    Text((liveTicket.departureDate ?? liveTicket.date), format: .dateTime.day().month().year().hour().minute())
                }
                LabeledContent("Email date") {
                    Text(liveTicket.date, format: .dateTime.day().month().year().hour().minute())
                }
            }

            Section("Check-in ID") {
                Text(liveTicket.link)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Passengers") {
                if liveTicket.passengers.isEmpty {
                    Text("No passengers loaded")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(liveTicket.passengers) { passenger in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(passenger.name)
                                .font(.headline)

                            HStack(spacing: 16) {
                                LabeledContent("Carriage", value: passenger.carriage == 0 ? "—" : "\(passenger.carriage)")
                                LabeledContent("Seat", value: passenger.seat.isEmpty ? "—" : passenger.seat)
                            }
                            .font(.subheadline)

                            if let image = qrImage(from: passenger.qrcode) {
                                image
                                    .resizable()
                                    .interpolation(.none)
                                    .scaledToFit()
                                    .frame(maxWidth: 180, maxHeight: 180)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(liveTicket.trainNumber.isEmpty ? "Ticket" : "Train \(liveTicket.trainNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.rounded)
        .background(app_background_color)
    }

    private func qrImage(from data: Data) -> Image? {
        guard !data.isEmpty, let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
    }

    private func syncEmails(for account: Emails) async {
        guard !isSyncing, let profile = profiles.first else { return }
        isSyncing = true
        isLoadingDetails = true
        errorMessage = nil
        defer {
            isSyncing = false
            isLoadingDetails = false
        }

        do {
            try await EmailTicketSyncService.syncAccount(
                accountID: account.id,
                profile: profile,
                modelContext: modelContext
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reloadAllEmails(for account: Emails) async {
        guard !isSyncing, let profile = profiles.first else { return }
        isSyncing = true
        isLoadingDetails = true
        errorMessage = nil
        defer {
            isSyncing = false
            isLoadingDetails = false
        }

        do {
            try await EmailTicketSyncService.syncAccount(
                accountID: account.id,
                profile: profile,
                modelContext: modelContext,
                reloadAll: true
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview("Email Inbox View") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: UserProfile.self, configurations: config)
    let emailAccount = Emails(provider: .apple, email: "francescopara2003@icloud.com", appPassword: "pqmy-ncsd-qzbi-zxte")
    container.mainContext.insert(UserProfile(name: "Francesco", emails: [emailAccount]))

    return NavigationStack {
        EmailInboxView(emailID: emailAccount.id)
            .modelContainer(container)
    }
}
