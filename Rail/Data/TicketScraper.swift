import Foundation
import WebKit
import UIKit

struct ScrapedJourney {
    var number: String
    var date: String
    var dep_station: String
    var arr_station: String
    var passengers: [ScrapedPassenger]
}

struct ScrapedPassenger {
    var name: String
    var coach: String
    var seat: String
    var qrData: Data?
}

@MainActor
final class TicketScraper: NSObject, WKNavigationDelegate {
    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    private var webView: WKWebView!
    private var hostWindow: UIWindow?
    private var navigationContinuation: CheckedContinuation<Void, Error>?

    override init() {
        super.init()
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        webView.customUserAgent = Self.userAgent
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .white
        webView.alpha = 0.01
    }

    func scrapeTickets(checkInID: String) async throws -> [ScrapedJourney] {
        attachToWindow()
        defer {
            webView.removeFromSuperview()
            hostWindow?.isHidden = true
            hostWindow = nil
        }

        let urls = [
            CheckInLink.url(for: checkInID),
            "https://www.lefrecce.it/Channels.Website.WEB/#/self-check-in?id=\(CheckInLink.normalizeID(checkInID))"
        ]

        for urlString in urls {
            guard let url = URL(string: urlString) else { continue }

            do {
                try await load(url)
                try await Task.sleep(for: .seconds(2))

                let deadline = Date().addingTimeInterval(15)
                while Date() < deadline {
                    if try await pageShowsLogin() {
                        throw TicketScrapeError.loginPageShown
                    }

                    let journeys = await extractJourneys()
                    if !journeys.isEmpty { return journeys }

                    try await Task.sleep(for: .milliseconds(400))
                }
            } catch TicketScrapeError.loginPageShown {
                throw TicketScrapeError.loginPageShown
            } catch {
                continue
            }
        }

        throw TicketScrapeError.noJourneyFound
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationContinuation?.resume()
        navigationContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
    }

    private func load(_ url: URL) async throws {
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            navigationContinuation = done
            webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
        }
    }

    private func attachToWindow() {
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: { $0.isKeyWindow }) {
            window.insertSubview(webView, at: 0)
            return
        }

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.windowLevel = .normal
        window.alpha = 0.01
        let controller = UIViewController()
        controller.view.backgroundColor = .white
        controller.view.addSubview(webView)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        hostWindow = window
    }

    private func pageShowsLogin() async throws -> Bool {
        let js = """
        (() => {
            const text = (document.body && document.body.innerText) ? document.body.innerText.toLowerCase() : '';
            return text.includes('username') && text.includes('password') && text.includes('login');
        })();
        """

        return await withCheckedContinuation { done in
            webView.evaluateJavaScript(js) { result, _ in
                done.resume(returning: (result as? Bool) ?? false)
            }
        }
    }

    private func extractJourneys() async -> [ScrapedJourney] {
        let js = """
        (() => {
            let result = [];
            function traverse(node) {
                if (!node) return;
                if (node.nodeType === Node.TEXT_NODE) {
                    let text = node.textContent.trim();
                    if (text) result.push({type: 'text', val: text});
                } else if (node.nodeType === Node.ELEMENT_NODE) {
                    if (node.tagName === 'SCRIPT' || node.tagName === 'STYLE') return;
                    if (node.tagName === 'IMG' && node.src && node.src.includes('data:image/')) {
                        result.push({type: 'qr', val: node.src});
                    }
                    for (let child of node.childNodes) traverse(child);
                }
            }
            traverse(document.body);
            return result;
        })();
        """

        return await withCheckedContinuation { done in
            webView.evaluateJavaScript(js) { result, _ in
                guard let nodes = result as? [[String: Any]] else {
                    done.resume(returning: [])
                    return
                }
                done.resume(returning: Self.parse(nodes: nodes))
            }
        }
    }

    // Mirrors Sketch/Scripts/fetch_checkin_qr.py extract_all_tickets
    private static func parse(nodes: [[String: Any]]) -> [ScrapedJourney] {
        var journeys: [ScrapedJourney] = []
        var currentTrainIndex: Int?
        var currentPassengerIndex: Int?

        var index = 0
        while index < nodes.count {
            let node = nodes[index]
            guard let type = node["type"] as? String, let value = node["val"] as? String else {
                index += 1
                continue
            }

            if type == "text" {
                let lower = value.lowercased()

                if lower.contains(" numero ") {
                    let trainNumber = value.components(separatedBy: " numero ").last?.trimmingCharacters(in: .whitespaces) ?? ""
                    if currentTrainIndex == nil || journeys[currentTrainIndex!].number != trainNumber {
                        journeys.append(
                            ScrapedJourney(number: trainNumber, date: "Unknown", dep_station: "Unknown", arr_station: "Unknown", passengers: [])
                        )
                        currentTrainIndex = journeys.count - 1
                        currentPassengerIndex = nil
                    }
                } else if lower.hasPrefix("partenza ") {
                    if let trainIndex = currentTrainIndex {
                        journeys[trainIndex].dep_station = String(value.dropFirst(9)).trimmingCharacters(in: .whitespaces)
                        if index + 1 < nodes.count,
                           nodes[index + 1]["type"] as? String == "text",
                           let nextValue = nodes[index + 1]["val"] as? String,
                           nextValue.contains(" - ") {
                            journeys[trainIndex].date = nextValue.components(separatedBy: " - ").first?.trimmingCharacters(in: .whitespaces) ?? "Unknown"
                        }
                    }
                } else if lower.hasPrefix("arrivo ") {
                    if let trainIndex = currentTrainIndex {
                        journeys[trainIndex].arr_station = String(value.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                    }
                } else if lower.hasPrefix("passenger ") || lower.hasPrefix("passeggero ") {
                    if let trainIndex = currentTrainIndex {
                        journeys[trainIndex].passengers.append(
                            ScrapedPassenger(name: "Unknown", coach: "N/A", seat: "N/A", qrData: nil)
                        )
                        currentPassengerIndex = journeys[trainIndex].passengers.count - 1

                        var offset = 1
                        if index + 1 < nodes.count,
                           let nextValue = nodes[index + 1]["val"] as? String,
                           nextValue.count <= 3,
                           nextValue == nextValue.uppercased() {
                            offset = 2
                        }

                        var firstName = ""
                        var lastName = ""
                        if index + offset < nodes.count, nodes[index + offset]["type"] as? String == "text" {
                            firstName = nodes[index + offset]["val"] as? String ?? ""
                        }
                        if index + offset + 1 < nodes.count, nodes[index + offset + 1]["type"] as? String == "text" {
                            let next = nodes[index + offset + 1]["val"] as? String ?? ""
                            if !next.hasPrefix("Code:") && !next.hasPrefix("Offer") && !next.hasPrefix("EXPIRED") {
                                lastName = next
                            }
                        }

                        if !firstName.isEmpty, let passengerIndex = currentPassengerIndex {
                            let name = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
                            journeys[trainIndex].passengers[passengerIndex].name = name.filter { $0.isLetter || $0.isWhitespace }
                        }
                    }
                } else if lower == "coach" || lower == "carrozza" {
                    if let trainIndex = currentTrainIndex,
                       let passengerIndex = currentPassengerIndex,
                       index + 1 < nodes.count,
                       nodes[index + 1]["type"] as? String == "text" {
                        journeys[trainIndex].passengers[passengerIndex].coach = nodes[index + 1]["val"] as? String ?? ""
                    }
                } else if lower == "seat" || lower == "posto" {
                    if let trainIndex = currentTrainIndex,
                       let passengerIndex = currentPassengerIndex,
                       index + 1 < nodes.count,
                       nodes[index + 1]["type"] as? String == "text" {
                        journeys[trainIndex].passengers[passengerIndex].seat = nodes[index + 1]["val"] as? String ?? ""
                    }
                }
            } else if type == "qr",
                      let trainIndex = currentTrainIndex,
                      let passengerIndex = currentPassengerIndex,
                      value.hasPrefix("data:image/") {
                let parts = value.components(separatedBy: ",")
                if parts.count > 1, let data = Data(base64Encoded: parts[1]) {
                    journeys[trainIndex].passengers[passengerIndex].qrData = data
                }
            }

            index += 1
        }

        return journeys
    }
}

@MainActor
func fetchTicketDetails(checkInID: String) async throws -> EmailContent {
    let scraper = TicketScraper()
    let journeys = try await scraper.scrapeTickets(checkInID: checkInID)
    guard let journey = journeys.first else {
        throw TicketScrapeError.noJourneyFound
    }

    let passengers = journey.passengers.map { passenger in
        EmailContentPassenger(
            name: passenger.name,
            carriage: Int(passenger.coach.filter(\.isNumber)) ?? 0,
            seat: passenger.seat,
            qrcode: passenger.qrData ?? Data()
        )
    }

    return EmailContent(
        imapUID: "",
        date: .now,
        link: checkInID,
        trainNumber: journey.number,
        departureStation: journey.dep_station,
        arrivalStation: journey.arr_station,
        passengers: passengers
    )
}

enum TicketScrapeError: LocalizedError {
    case noJourneyFound
    case loginPageShown

    var errorDescription: String? {
        switch self {
        case .noJourneyFound:
            return "Could not read ticket details from the check-in page."
        case .loginPageShown:
            return "The check-in page did not load correctly."
        }
    }
}
