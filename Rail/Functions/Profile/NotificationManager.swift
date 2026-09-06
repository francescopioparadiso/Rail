import Foundation
import UserNotifications

/// Schedules the journey alerts entirely on device. Every pass rebuilds the whole
/// set from the times currently in the store, so a delay that moved a departure
/// moves its alert with it and a deleted train takes its alert down with it.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    // MARK: - Properties

    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()

    /// Only requests carrying one of these prefixes are ours to replace or remove.
    private static let trainPrefix = "train-alert-"
    private static let passPrefix = "pass-alert-"
    private static let ownedPrefixes = [trainPrefix, passPrefix]

    /// iOS keeps the 64 soonest pending requests and silently drops the rest,
    /// so stay under that and never plan for a journey further out than a week.
    private static let requestLimit = 60
    private static let horizon: TimeInterval = 7 * 24 * 3600

    /// A pass running out is a day's news, not a minute's, so it is announced in
    /// the morning rather than at whatever hour the pass happens to lapse.
    private static let passAlertHour = 8 + 1

    /// A weekly pass never exists early enough to warn about a fortnight ahead, so
    /// past this much notice it falls back to a warning it can actually carry.
    private static let weeklyPassFallbackDays = 2

    // MARK: - Types

    private enum AlertKind: String {
        case departure
        case arrival
    }

    private struct PlannedAlert: Sendable {
        let identifier: String
        let title: String
        let body: String
        let trainID: UUID
        let fireDate: Date
    }

    // MARK: - Methods

    /// Claims the delegate so a tapped alert can be routed. Must run before the app
    /// finishes launching, or a notification tapped from a cold start is lost.
    func registerDelegate() {
        center.delegate = self
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func isAuthorized() async -> Bool {
        switch await authorizationStatus() {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    func requestAccess() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            print("Error requesting notification access: \(error)")
            return false
        }
    }

    /// Trains and passes are planned together on purpose: every pass clears out the
    /// alerts it did not ask for, so syncing one kind alone would take the other down.
    @MainActor
    func syncAlerts(trains: [Train], stops: [Stop], passes: [Pass], settings: NotificationSettings) async {
        guard settings.isEnabled, settings.hasAnyLead else {
            await removeAllAlerts()
            return
        }
        guard await isAuthorized() else { return }

        let planned = plannedTrainAlerts(trains: trains, stops: stops, settings: settings)
            + plannedPassAlerts(passes: passes, settings: settings)
        await apply(Array(planned.sorted { $0.fireDate < $1.fireDate }.prefix(Self.requestLimit)))
    }

    func removeAllAlerts() async {
        let identifiers = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { identifier in Self.ownedPrefixes.contains(where: identifier.hasPrefix) }
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    // MARK: - Planning

    @MainActor
    private func plannedTrainAlerts(trains: [Train], stops: [Stop], settings: NotificationSettings) -> [PlannedAlert] {
        let now = Date()
        let cutoff = now.addingTimeInterval(Self.horizon)
        let stopsByTrain = Dictionary(grouping: stops, by: \.id)
        var alerts: [PlannedAlert] = []

        for train in trains {
            guard let trainStops = stopsByTrain[train.id], !trainStops.isEmpty else { continue }
            let summary = StopSummary.calculate(in: trainStops)

            if settings.departureLead > 0 {
                let stop = summary.first
                if let alert = plannedAlert(
                    kind: .departure,
                    train: train,
                    station: stop.name,
                    eventDate: stop.dep_time_eff,
                    delay: stop.dep_delay,
                    lead: settings.departureLead,
                    now: now,
                    cutoff: cutoff
                ) {
                    alerts.append(alert)
                }
            }

            if settings.arrivalLead > 0 {
                let stop = summary.last
                if let alert = plannedAlert(
                    kind: .arrival,
                    train: train,
                    station: stop.name,
                    eventDate: stop.arr_time_eff,
                    delay: stop.arr_delay,
                    lead: settings.arrivalLead,
                    now: now,
                    cutoff: cutoff
                ) {
                    alerts.append(alert)
                }
            }
        }

        return alerts
    }

    /// A pass warning, one per pass that is still good.
    ///
    /// The chosen notice applies as written, with one exception: a warning of more
    /// than a week cannot be given about a pass that only lasts a week, so those
    /// fall back to two days. Anything up to a week is given as asked, whatever
    /// kind of pass it is.
    @MainActor
    private func plannedPassAlerts(passes: [Pass], settings: NotificationSettings) -> [PlannedAlert] {
        let leadDays = settings.passLeadDays
        guard leadDays > 0 else { return [] }

        let calendar = Calendar.current
        let now = Date()
        var alerts: [PlannedAlert] = []

        for pass in passes {
            let expiry = pass.expiry_date
            guard expiry > now else { continue }

            let isWeekly = PassValidityPeriod.isWeekly(
                name: pass.name,
                start: calendar.startOfDay(for: pass.start_date),
                end: calendar.startOfDay(for: expiry)
            )
            let effectiveLead = (leadDays > 7 && isWeekly) ? Self.weeklyPassFallbackDays : leadDays

            guard let day = calendar.date(byAdding: .day, value: -effectiveLead, to: expiry),
                  let fireDate = calendar.date(
                      bySettingHour: Self.passAlertHour, minute: 0, second: 0,
                      of: calendar.startOfDay(for: day)
                  ),
                  fireDate > now else { continue }

            let name = pass.name.isEmpty ? String(localized: "Pass") : pass.name
            let remaining = max(1, (calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: fireDate),
                to: calendar.startOfDay(for: expiry)
            ).day ?? effectiveLead))

            alerts.append(
                PlannedAlert(
                    identifier: "\(Self.passPrefix)\(pass.id.uuidString)",
                    title: String(format: NSLocalizedString("%@ expires in %lld days", comment: ""), name, remaining),
                    body: String(
                        format: NSLocalizedString("Valid until %@", comment: ""),
                        expiry.formatted(Date.FormatStyle.dateTime.day().month(.wide))
                    ),
                    trainID: pass.id,
                    fireDate: fireDate
                )
            )
        }

        return alerts
    }

    private func plannedAlert(
        kind: AlertKind,
        train: Train,
        station: String,
        eventDate: Date,
        delay: Int,
        lead: Double,
        now: Date,
        cutoff: Date
    ) -> PlannedAlert? {
        guard eventDate > now, eventDate < cutoff else { return nil }

        // A lead window that has already opened is one the traveller is living
        // through, so there is nothing left to warn about.
        let fireDate = eventDate.addingTimeInterval(-lead)
        guard fireDate > now else { return nil }

        let leadText = NotificationSettings.leadDescription(lead)
        let title: String
        switch kind {
        case .departure:
            title = String(format: NSLocalizedString("Departing in %@", comment: ""), leadText)
        case .arrival:
            title = String(format: NSLocalizedString("Arriving in %@", comment: ""), leadText)
        }

        let name = train.number.isEmpty ? train.logo : "\(train.logo) \(train.number)"
        let time = eventDate.formatted(Date.FormatStyle.dateTime.hour().minute())
        var body = "\(name.trimmingCharacters(in: .whitespaces)) · \(station) · \(time)"
        if delay > 0 {
            body += " · " + String(format: NSLocalizedString("%lld min delay", comment: ""), delay)
        }

        return PlannedAlert(
            identifier: "\(Self.trainPrefix)\(train.id.uuidString)-\(kind.rawValue)",
            title: title,
            body: body,
            trainID: train.id,
            fireDate: fireDate
        )
    }

    // MARK: - Delivery

    private func apply(_ alerts: [PlannedAlert]) async {
        let planned = Set(alerts.map(\.identifier))
        let stale = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { identifier in
                Self.ownedPrefixes.contains(where: identifier.hasPrefix) && !planned.contains(identifier)
            }
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }

        for alert in alerts {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            content.sound = .default
            content.userInfo = alert.identifier.hasPrefix(Self.passPrefix)
                ? ["passID": alert.trainID.uuidString]
                : ["trainID": alert.trainID.uuidString]

            // Anchored to wall-clock components so the alert survives a change of
            // time zone on the way to the station.
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: alert.fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

            // Re-adding a known identifier replaces the pending request, which is
            // what turns a fresh delay into a moved alert.
            let request = UNNotificationRequest(identifier: alert.identifier, content: content, trigger: trigger)
            do {
                try await center.add(request)
            } catch {
                print("Error scheduling notification: \(error)")
            }
        }
    }
}

// MARK: - Delegate

extension NotificationManager {
    /// Show the alert even with the app open: it is the same warning whether or not
    /// the traveller happens to be looking at Rail when it comes due.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    /// A tap opens the journey the alert was about.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let raw = response.notification.request.content.userInfo["trainID"] as? String,
              let trainID = UUID(uuidString: raw) else { return }
        DeepLinkRouter.shared.open(trainID: trainID)
    }
}
