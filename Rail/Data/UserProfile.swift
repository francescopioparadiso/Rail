import Foundation
import Combine

class UserProfile: ObservableObject {
    static let shared = UserProfile()
    
    @Published var firstName: String {
        didSet { NSUbiquitousKeyValueStore.default.set(firstName, forKey: "profile_firstName") }
    }
    
    @Published var lastName: String {
        didSet { NSUbiquitousKeyValueStore.default.set(lastName, forKey: "profile_lastName") }
    }
    
    @Published var imageData: Data? {
        didSet { NSUbiquitousKeyValueStore.default.set(imageData, forKey: "profile_imageData") }
    }
    
    @Published var calendarTitleFormat: String {
        didSet { NSUbiquitousKeyValueStore.default.set(calendarTitleFormat, forKey: "profile_calendarTitleFormat") }
    }
    
    @Published var selectedCalendarIdentifier: String {
        didSet { NSUbiquitousKeyValueStore.default.set(selectedCalendarIdentifier, forKey: "profile_selectedCalendarIdentifier") }
    }
    
    @Published var autoSyncToCalendar: Bool {
        didSet { NSUbiquitousKeyValueStore.default.set(autoSyncToCalendar, forKey: "profile_autoSyncToCalendar") }
    }
    
    @Published var calendarTravelTime: Double {
        didSet { NSUbiquitousKeyValueStore.default.set(calendarTravelTime, forKey: "profile_calendarTravelTime") }
    }
    
    init() {
        let store = NSUbiquitousKeyValueStore.default
        self.firstName = store.string(forKey: "profile_firstName") ?? ""
        self.lastName = store.string(forKey: "profile_lastName") ?? ""
        self.imageData = store.data(forKey: "profile_imageData")
        self.calendarTitleFormat = store.string(forKey: "profile_calendarTitleFormat") ?? "Train {number}"
        self.selectedCalendarIdentifier = store.string(forKey: "profile_selectedCalendarIdentifier") ?? ""
        if let autoSync = store.object(forKey: "profile_autoSyncToCalendar") as? Bool {
            self.autoSyncToCalendar = autoSync
        } else {
            self.autoSyncToCalendar = true
        }
        self.calendarTravelTime = store.double(forKey: "profile_calendarTravelTime")
        
        NotificationCenter.default.addObserver(self, selector: #selector(storeDidChange), name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: store)
        store.synchronize()
    }
    
    @objc private func storeDidChange(notification: Notification) {
        DispatchQueue.main.async {
            let store = NSUbiquitousKeyValueStore.default
            self.firstName = store.string(forKey: "profile_firstName") ?? ""
            self.lastName = store.string(forKey: "profile_lastName") ?? ""
            self.imageData = store.data(forKey: "profile_imageData")
            self.calendarTitleFormat = store.string(forKey: "profile_calendarTitleFormat") ?? "Train {number}"
            self.selectedCalendarIdentifier = store.string(forKey: "profile_selectedCalendarIdentifier") ?? ""
            if let autoSync = store.object(forKey: "profile_autoSyncToCalendar") as? Bool {
                self.autoSyncToCalendar = autoSync
            } else {
                self.autoSyncToCalendar = true
            }
            self.calendarTravelTime = store.double(forKey: "profile_calendarTravelTime")
        }
    }
}
