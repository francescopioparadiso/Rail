import SwiftUI

struct EmailTicketRow: View {
    // MARK: - Properties

    let ticket: EmailContent
    var isLoading: Bool = false

    // MARK: - Computed

    private var displayDate: Date {
        ticket.departureDate ?? ticket.date
    }

    private var fallbackTitle: String {
        ticket.trainNumber.isEmpty ? String(localized: "Ticket") : "Train \(ticket.trainNumber)"
    }

    /// "Departure station → Arrival station", each with only its first word capitalized
    /// (email-parsed station names often arrive in ALL CAPS or oddly mixed case).
    private var stationsLine: String {
        let depFirstWord = String(ticket.departureStation.split(separator: " ").first ?? "")
        let dep = sentenceCased(depFirstWord)
        
        guard !ticket.arrivalStation.isEmpty else { return dep }
        
        let arrFirstWord = String(ticket.arrivalStation.split(separator: " ").first ?? "")
        let arr = sentenceCased(arrFirstWord)
        return "\(dep) → \(arr)"
    }

    /// "HH:mm → HH:mm", falling back to just the departure time (or nil) when the arrival
    /// time isn't known yet.
    private var timesLine: String? {
        switch (ticket.departureDate, ticket.arrivalDate) {
        case let (dep?, arr?):
            return "\(timeString(dep)) → \(timeString(arr))"
        case let (dep?, nil):
            return timeString(dep)
        default:
            return nil
        }
    }

    private var displayPrice: String? {
        let price = ticket.price.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !price.isEmpty, price != "Unknown" else { return nil }
        return price
    }

    // MARK: - Body

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // the padding here is what sets the row height: the badge stands taller
            // than the stations and times lines beside it
            DepartureCalendarBadge(date: displayDate, fillsHeight: true, verticalPadding: 18)

            if !ticket.departureStation.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stationsLine)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.5)

                        Text(timesLine ?? "")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    if isLoading {
                        ProgressView()
                    } else {
                        Text(displayPrice ?? "")
                            .font(.callout).fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                }
                .fontDesign(appFontDesign)
            } else {
                Text(fallbackTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .fontDesign(appFontDesign)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    /// Lowercases the whole string, then capitalizes only its first character — i.e. only
    /// the first word gets a capital letter, unlike `.capitalized` which title-cases every word.
    private func sentenceCased(_ name: String) -> String {
        let lower = name.lowercased()
        guard let first = lower.first else { return lower }
        return first.uppercased() + lower.dropFirst()
    }

    private func timeString(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
