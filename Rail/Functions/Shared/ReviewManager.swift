import StoreKit
import SwiftUI

@MainActor
class ReviewManager {
    static let shared = ReviewManager()

    private init() {}

    func requestReviewIfAppropriate(action: RequestReviewAction) {
        let currentCount = UserDefaults.standard.integer(forKey: "appLaunchCount")
        let newCount = currentCount + 1
        UserDefaults.standard.set(newCount, forKey: "appLaunchCount")

        let significantInteractions = [5, 10, 20, 30, 50, 75, 100, 200, 300, 500, 1000]

        if significantInteractions.contains(newCount) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                action()
            }
        }
    }
}
