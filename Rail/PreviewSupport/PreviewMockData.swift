import Foundation
import UIKit

/// Invented mailbox contents for previews and App Store screenshots.
///
/// Nothing here belongs to anyone: the addresses are made up, and the check-in
/// links carry the sample identifiers `EmailContent.isSampleTicket` already knows
/// about, so a sync will never go looking for details behind them. That is the
/// point — a screenshot should show a full app without a real inbox behind it,
/// and without the address from `.env.local` on screen.
///
/// `#Preview` bodies compile into release builds, so this type is not gated.
enum PreviewMockData {
    // MARK: - Mailboxes

    static let appleEmail = "mario.rossi@icloud.com"
    static let googleEmail = "mario.rossi@gmail.com"

    static func appleAccount() -> Emails {
        Emails(
            provider: .apple,
            email: appleEmail,
            appPassword: "abcd-efgh-ijkl-mnop",
            content: appleTickets(),
            passes: applePasses()
        )
    }

    static func googleAccount() -> Emails {
        Emails(
            provider: .google,
            email: googleEmail,
            appPassword: "qrst-uvwx-yzab-cdef",
            content: googleTickets(),
            passes: googlePasses()
        )
    }

    // MARK: - Tickets

    /// Deliberately *not* the identifiers `EmailContent.isSampleTicket` knows:
    /// those are filtered straight out of the import list, which is right for a
    /// real sync and useless for a screenshot. Details are filled in here instead,
    /// so `shouldFetchCheckInDetails` stays false and nothing reaches for a
    /// check-in page that was never there.
    static func appleTickets() -> [EmailContent] {
        [
            EmailContent(
                imapUID: "48211",
                date: day(-2, hour: 18, minute: 12),
                link: CheckInLink.url(for: "k7m2p9q4r8s3t6u1v5w0x2y7"),
                departureDate: day(1, hour: 6, minute: 20),
                arrivalDate: day(1, hour: 8, minute: 46),
                trainNumber: "9904",
                departureStation: "Roma Termini",
                arrivalStation: "Milano Centrale",
                price: "59,90 €",
                passengers: [
                    passenger(name: "Mario Rossi", carriage: 7, seat: "4C"),
                    passenger(name: "Giulia Bianchi", carriage: 7, seat: "4D")
                ],
                detailsFetchedAt: day(-2, hour: 18, minute: 14)
            ),
            EmailContent(
                imapUID: "48355",
                date: day(-1, hour: 9, minute: 40),
                link: CheckInLink.url(for: "b3c8d1e6f9g2h5j0k4l7m1n8"),
                departureDate: day(3, hour: 14, minute: 5),
                arrivalDate: day(3, hour: 17, minute: 35),
                trainNumber: "9612",
                departureStation: "Milano Centrale",
                arrivalStation: "Napoli Centrale",
                price: "84,00 €",
                passengers: [
                    passenger(name: "Mario Rossi", carriage: 3, seat: "11A")
                ],
                detailsFetchedAt: day(-1, hour: 9, minute: 41)
            ),
            EmailContent(
                imapUID: "47980",
                date: day(-6, hour: 21, minute: 5),
                link: CheckInLink.url(for: "p5q0r3s8t2u7v1w6x9y4z3a2"),
                departureDate: day(-4, hour: 7, minute: 55),
                arrivalDate: day(-4, hour: 10, minute: 12),
                trainNumber: "8514",
                departureStation: "Torino Porta Nuova",
                arrivalStation: "Venezia Santa Lucia",
                price: "42,50 €",
                passengers: [
                    passenger(name: "Mario Rossi", carriage: 5, seat: "2B")
                ],
                detailsFetchedAt: day(-6, hour: 21, minute: 6)
            )
        ]
    }

    static func googleTickets() -> [EmailContent] {
        [
            EmailContent(
                imapUID: "10422",
                date: day(-3, hour: 12, minute: 2),
                link: CheckInLink.url(for: "c9d4e7f2g5h8j1k6l3m0n5p8"),
                departureDate: day(6, hour: 18, minute: 40),
                arrivalDate: day(6, hour: 21, minute: 5),
                trainNumber: "9576",
                departureStation: "Firenze Santa Maria Novella",
                arrivalStation: "Torino Porta Susa",
                price: "48,00 €",
                passengers: [
                    passenger(name: "Mario Rossi", carriage: 2, seat: "6D")
                ],
                detailsFetchedAt: day(-3, hour: 12, minute: 3)
            ),
            EmailContent(
                imapUID: "10188",
                date: day(-12, hour: 8, minute: 30),
                link: CheckInLink.url(for: "t2u5v8w1x4y7z0a3b6c9d2e5"),
                departureDate: day(-9, hour: 16, minute: 10),
                arrivalDate: day(-9, hour: 18, minute: 2),
                trainNumber: "9430",
                departureStation: "Bologna Centrale",
                arrivalStation: "Bari Centrale",
                price: "37,90 €",
                passengers: [
                    passenger(name: "Mario Rossi", carriage: 6, seat: "3A")
                ],
                detailsFetchedAt: day(-12, hour: 8, minute: 31)
            )
        ]
    }

    // MARK: - Passes

    static func applePasses() -> [EmailPassContent] {
        [
            monthlyPass(name: "Abbonamento Mensile", monthOffset: 0, price: "62,00 €", uid: "2001", mailedDaysAgo: 8),
            EmailPassContent(
                imapUID: "2002",
                date: day(-2, hour: 8, minute: 5),
                name: "Settimanale",
                startDate: startOfDay(offset: -1),
                endDate: startOfDay(offset: 5),
                price: "19,50 €",
                qrcode: qrCode
            )
        ]
    }

    static func googlePasses() -> [EmailPassContent] {
        [
            monthlyPass(name: "Abbonamento Mensile", monthOffset: 1, price: "62,00 €", uid: "3001", mailedDaysAgo: 1),
            EmailPassContent(
                imapUID: "3002",
                date: day(-10, hour: 7, minute: 45),
                name: "Settimanale Studenti",
                startDate: startOfDay(offset: -9),
                endDate: startOfDay(offset: -3),
                price: "12,00 €",
                qrcode: qrCode
            )
        ]
    }

    private static func monthlyPass(name: String, monthOffset: Int, price: String, uid: String, mailedDaysAgo: Int) -> EmailPassContent {
        let calendar = Calendar.current
        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        let start = calendar.date(byAdding: .month, value: monthOffset, to: thisMonth) ?? thisMonth
        let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? start
        return EmailPassContent(
            imapUID: uid,
            date: day(-mailedDaysAgo, hour: 7, minute: 30),
            name: name,
            startDate: start,
            endDate: end,
            price: price,
            qrcode: qrCode
        )
    }

    // MARK: - Images

    static var qrCode: Data {
        UIImage(named: "sample_code")?.pngData() ?? Data()
    }

    /// A drawn landscape rather than a photograph of anybody: the profile screen
    /// pulls its accent colour out of this, so it wants real colour in it.
    static func profilePhoto(size: CGFloat = 512) -> Data? {
        let bounds = CGRect(x: 0, y: 0, width: size, height: size)
        let renderer = UIGraphicsImageRenderer(size: bounds.size)

        return renderer.image { context in
            let cg = context.cgContext

            let sky = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor(red: 0.16, green: 0.36, blue: 0.66, alpha: 1).cgColor,
                    UIColor(red: 0.46, green: 0.60, blue: 0.82, alpha: 1).cgColor,
                    UIColor(red: 0.98, green: 0.76, blue: 0.51, alpha: 1).cgColor
                ] as CFArray,
                locations: [0, 0.55, 1]
            )!
            cg.drawLinearGradient(
                sky,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: 0, y: size * 0.68),
                options: []
            )

            UIColor(red: 1, green: 0.90, blue: 0.62, alpha: 1).setFill()
            cg.fillEllipse(in: CGRect(x: size * 0.62, y: size * 0.20, width: size * 0.16, height: size * 0.16))

            func ridge(peaks: [CGPoint], base: CGFloat, color: UIColor) {
                let path = UIBezierPath()
                path.move(to: CGPoint(x: 0, y: base))
                peaks.forEach { path.addLine(to: $0) }
                path.addLine(to: CGPoint(x: size, y: base))
                path.addLine(to: CGPoint(x: size, y: size))
                path.addLine(to: CGPoint(x: 0, y: size))
                path.close()
                color.setFill()
                path.fill()
            }

            ridge(
                peaks: [
                    CGPoint(x: size * 0.18, y: size * 0.46),
                    CGPoint(x: size * 0.34, y: size * 0.62),
                    CGPoint(x: size * 0.55, y: size * 0.40),
                    CGPoint(x: size * 0.78, y: size * 0.61)
                ],
                base: size * 0.70,
                color: UIColor(red: 0.30, green: 0.38, blue: 0.52, alpha: 1)
            )

            ridge(
                peaks: [
                    CGPoint(x: size * 0.12, y: size * 0.70),
                    CGPoint(x: size * 0.40, y: size * 0.56),
                    CGPoint(x: size * 0.66, y: size * 0.74),
                    CGPoint(x: size * 0.88, y: size * 0.62)
                ],
                base: size * 0.82,
                color: UIColor(red: 0.20, green: 0.44, blue: 0.40, alpha: 1)
            )

            UIColor(red: 0.36, green: 0.58, blue: 0.36, alpha: 1).setFill()
            let field = UIBezierPath()
            field.move(to: CGPoint(x: 0, y: size * 0.84))
            field.addQuadCurve(
                to: CGPoint(x: size, y: size * 0.80),
                controlPoint: CGPoint(x: size * 0.5, y: size * 0.92)
            )
            field.addLine(to: CGPoint(x: size, y: size))
            field.addLine(to: CGPoint(x: 0, y: size))
            field.close()
            field.fill()
        }.pngData()
    }

    // MARK: - Helpers

    private static func passenger(name: String, carriage: Int, seat: String) -> EmailContentPassenger {
        EmailContentPassenger(name: name, carriage: carriage, seat: seat, qrcode: qrCode)
    }

    private static func startOfDay(offset: Int) -> Date {
        let calendar = Calendar.current
        let base = calendar.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        return calendar.startOfDay(for: base)
    }

    private static func day(_ offset: Int, hour: Int, minute: Int) -> Date {
        let calendar = Calendar.current
        let base = calendar.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
    }
}
