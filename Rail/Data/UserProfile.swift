import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

struct LinkedEmail: Codable, Identifiable {
    var id: UUID = UUID()
    var provider: String // "Google" or "iCloud"
    var email: String
    var appPassword: String
}

class UserProfile: ObservableObject {
    static let shared = UserProfile()
    private static let cloudStore = NSUbiquitousKeyValueStore.default
    private static let localStore = UserDefaults.standard
    private static let maxCloudImageBytes = 700_000
    
    private enum Key {
        static let firstName = "profile_firstName"
        static let lastName = "profile_lastName"
        static let imageData = "profile_imageData"
        static let calendarTitleFormat = "profile_calendarTitleFormat"
        static let selectedCalendarIdentifier = "profile_selectedCalendarIdentifier"
        static let autoSyncToCalendar = "profile_autoSyncToCalendar"
        static let calendarTravelTime = "profile_calendarTravelTime"
        static let linkedEmails = "profile_linkedEmails"
    }
    
    @Published var firstName: String {
        didSet { save(firstName, forKey: Key.firstName) }
    }
    
    @Published var lastName: String {
        didSet { save(lastName, forKey: Key.lastName) }
    }
    
    @Published var imageData: Data? {
        didSet { save(imageData, forKey: Key.imageData) }
    }
    
    @Published var calendarTitleFormat: String {
        didSet { save(calendarTitleFormat, forKey: Key.calendarTitleFormat) }
    }
    
    @Published var selectedCalendarIdentifier: String {
        didSet { save(selectedCalendarIdentifier, forKey: Key.selectedCalendarIdentifier) }
    }
    
    @Published var autoSyncToCalendar: Bool {
        didSet { save(autoSyncToCalendar, forKey: Key.autoSyncToCalendar) }
    }
    
    @Published var calendarTravelTime: Double {
        didSet { save(calendarTravelTime, forKey: Key.calendarTravelTime) }
    }
    
    @Published var linkedEmails: [LinkedEmail] {
        didSet {
            if let data = try? JSONEncoder().encode(linkedEmails) {
                save(data, forKey: Key.linkedEmails)
            } else {
                save(nil, forKey: Key.linkedEmails)
            }
        }
    }
    
    init() {
        let store = Self.cloudStore
        store.synchronize()
        
        self.firstName = Self.string(forKey: Key.firstName) ?? ""
        self.lastName = Self.string(forKey: Key.lastName) ?? ""
        self.imageData = Self.data(forKey: Key.imageData)
        self.calendarTitleFormat = Self.string(forKey: Key.calendarTitleFormat) ?? "Train {number}"
        self.selectedCalendarIdentifier = Self.string(forKey: Key.selectedCalendarIdentifier) ?? ""
        self.autoSyncToCalendar = Self.bool(forKey: Key.autoSyncToCalendar) ?? true
        self.calendarTravelTime = Self.double(forKey: Key.calendarTravelTime) ?? 0
        
        if let data = Self.data(forKey: Key.linkedEmails), let decoded = try? JSONDecoder().decode([LinkedEmail].self, from: data) {
            self.linkedEmails = decoded
        } else {
            self.linkedEmails = []
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(storeDidChange), name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: store)
        saveAll()
    }
    
    @objc private func storeDidChange(notification: Notification) {
        DispatchQueue.main.async {
            self.firstName = Self.string(forKey: Key.firstName) ?? ""
            self.lastName = Self.string(forKey: Key.lastName) ?? ""
            self.imageData = Self.data(forKey: Key.imageData)
            self.calendarTitleFormat = Self.string(forKey: Key.calendarTitleFormat) ?? "Train {number}"
            self.selectedCalendarIdentifier = Self.string(forKey: Key.selectedCalendarIdentifier) ?? ""
            self.autoSyncToCalendar = Self.bool(forKey: Key.autoSyncToCalendar) ?? true
            self.calendarTravelTime = Self.double(forKey: Key.calendarTravelTime) ?? 0
            
            if let data = Self.data(forKey: Key.linkedEmails), let decoded = try? JSONDecoder().decode([LinkedEmail].self, from: data) {
                self.linkedEmails = decoded
            } else {
                self.linkedEmails = []
            }
        }
    }
    
    func saveAll() {
        save(firstName, forKey: Key.firstName)
        save(lastName, forKey: Key.lastName)
        save(imageData, forKey: Key.imageData)
        save(calendarTitleFormat, forKey: Key.calendarTitleFormat)
        save(selectedCalendarIdentifier, forKey: Key.selectedCalendarIdentifier)
        save(autoSyncToCalendar, forKey: Key.autoSyncToCalendar)
        save(calendarTravelTime, forKey: Key.calendarTravelTime)
        if let data = try? JSONEncoder().encode(linkedEmails) {
            save(data, forKey: Key.linkedEmails)
        }
    }
    
    static func preparedProfileImageData(from data: Data) -> Data? {
#if canImport(UIKit)
        guard let image = UIImage(data: data) else {
            return data.count <= maxCloudImageBytes ? data : nil
        }
        
        return preparedProfileImageData(from: image)
#else
        return data.count <= maxCloudImageBytes ? data : nil
#endif
    }
    
#if canImport(UIKit)
    static func preparedProfileImageData(from image: UIImage) -> Data? {
        let maxDimension: CGFloat = 512
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }
        
        let ratio = min(1, maxDimension / max(sourceSize.width, sourceSize.height))
        let targetSize = CGSize(width: sourceSize.width * ratio, height: sourceSize.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let normalizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        
        var quality: CGFloat = 0.85
        var data = normalizedImage.jpegData(compressionQuality: quality)
        
        while let currentData = data, currentData.count > maxCloudImageBytes, quality > 0.25 {
            quality -= 0.15
            data = normalizedImage.jpegData(compressionQuality: quality)
        }
        
        return data
    }
#endif
    
    private func save(_ value: Any?, forKey key: String) {
        if let value {
            Self.localStore.set(value, forKey: key)
            Self.cloudStore.set(value, forKey: key)
        } else {
            Self.localStore.removeObject(forKey: key)
            Self.cloudStore.removeObject(forKey: key)
        }
        
        Self.localStore.synchronize()
        Self.cloudStore.synchronize()
    }
    
    private static func string(forKey key: String) -> String? {
        cloudStore.string(forKey: key) ?? localStore.string(forKey: key)
    }
    
    private static func data(forKey key: String) -> Data? {
        cloudStore.data(forKey: key) ?? localStore.data(forKey: key)
    }
    
    private static func bool(forKey key: String) -> Bool? {
        if let value = cloudStore.object(forKey: key) as? Bool {
            return value
        }
        if let value = cloudStore.object(forKey: key) as? NSNumber {
            return value.boolValue
        }
        if localStore.object(forKey: key) != nil {
            return localStore.bool(forKey: key)
        }
        return nil
    }
    
    private static func double(forKey key: String) -> Double? {
        if cloudStore.object(forKey: key) != nil {
            return cloudStore.double(forKey: key)
        }
        if localStore.object(forKey: key) != nil {
            return localStore.double(forKey: key)
        }
        return nil
    }
}
