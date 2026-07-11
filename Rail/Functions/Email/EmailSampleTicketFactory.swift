import CoreImage
import Foundation
import UIKit

enum EmailSampleTicketFactory {
    static func make(imapUID: String = "sample-9999") -> EmailContent {
        EmailContent(
            imapUID: imapUID,
            date: Date(),
            link: CheckInLink.url(for: "abc123def456ghi789jkl012"),
            departureDate: departure(daysFromNow: 3, hour: 9, minute: 15),
            trainNumber: "9808",
            departureStation: "Roma Termini",
            arrivalStation: "Milano Centrale",
            passengers: [
                EmailContentPassenger(
                    name: "Francesco",
                    carriage: 7,
                    seat: "12A",
                    qrcode: sampleQRCodeData
                )
            ],
            detailsFetchedAt: .now
        )
    }

    static var sampleQRCodeData: Data {
        if let assetData = UIImage(resource: .sampleCode).pngData(), !assetData.isEmpty {
            return assetData
        }
        if let assetData = UIImage(named: "sample_code")?.pngData(), !assetData.isEmpty {
            return assetData
        }
        return generatedQRCodePNG(payload: "RAIL-SAMPLE-TICKET") ?? Data()
    }

    static func passengersWithSampleQRIfNeeded(_ passengers: [EmailContentPassenger]) -> [EmailContentPassenger] {
        guard !sampleQRCodeData.isEmpty else { return passengers }
        return passengers.map { passenger in
            guard passenger.qrcode.isEmpty else { return passenger }
            var updated = passenger
            updated.qrcode = sampleQRCodeData
            return updated
        }
    }

    private static func departure(daysFromNow: Int, hour: Int, minute: Int) -> Date {
        let day = Calendar.current.date(byAdding: .day, value: daysFromNow, to: Date()) ?? Date()
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    private static func generatedQRCodePNG(payload: String) -> Data? {
        guard let message = payload.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }

        filter.setValue(message, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }

        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage).pngData()
    }
}
