import Foundation
import WebKit

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
class TicketScraper: NSObject, WKNavigationDelegate {
    private var webView: WKWebView!
    private var continuation: CheckedContinuation<[ScrapedJourney], Error>?
    
    override init() {
        super.init()
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        // Optional: add webView to a window if needed, but usually evaluating JS works off-screen
    }
    
    func scrapeTickets(url: String) async throws -> [ScrapedJourney] {
        guard let reqURL = URL(string: url) else { return [] }
        let request = URLRequest(url: reqURL)
        
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            webView.load(request)
            
            // Timeout after 15 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) {
                if let pendingCont = self.continuation {
                    self.continuation = nil
                    self.evaluateJSAndResume(cont: pendingCont)
                }
            }
        }
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Wait an additional 4 seconds for JS rendering, like the python script
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            if let pendingCont = self.continuation {
                self.continuation = nil
                self.evaluateJSAndResume(cont: pendingCont)
            }
        }
    }
    
    private func evaluateJSAndResume(cont: CheckedContinuation<[ScrapedJourney], Error>) {
        let js = """
        (() => {
            let result = [];
            function traverse(node) {
                if (node.nodeType === Node.TEXT_NODE) {
                    let text = node.textContent.trim();
                    if (text) result.push({type: 'text', val: text});
                } else if (node.nodeType === Node.ELEMENT_NODE) {
                    if (node.tagName === 'SCRIPT' || node.tagName === 'STYLE') return;
                    if (node.tagName === 'IMG' && node.src.includes('data:image/')) {
                        result.push({type: 'qr', val: node.src});
                    }
                    for (let child of node.childNodes) traverse(child);
                }
            }
            traverse(document.body);
            return result;
        })();
        """
        
        webView.evaluateJavaScript(js) { result, error in
            if let error = error {
                cont.resume(throwing: error)
                return
            }
            
            guard let nodes = result as? [[String: Any]] else {
                cont.resume(returning: [])
                return
            }
            
            var journeys: [ScrapedJourney] = []
            var current_train: ScrapedJourney?
            var current_passenger: ScrapedPassenger?
            
            var i = 0
            while i < nodes.count {
                let node = nodes[i]
                guard let type = node["type"] as? String, let val = node["val"] as? String else {
                    i += 1; continue
                }
                
                if type == "text" {
                    let lowerVal = val.lowercased()
                    if lowerVal.contains(" numero ") {
                        let parts = val.components(separatedBy: " numero ")
                        let train_num = parts.last?.trimmingCharacters(in: .whitespaces) ?? ""
                        if current_train == nil || current_train?.number != train_num {
                            if let cp = current_passenger {
                                current_train?.passengers.append(cp)
                            }
                            if let ct = current_train {
                                journeys.append(ct)
                            }
                            current_train = ScrapedJourney(number: train_num, date: "Unknown", dep_station: "Unknown", arr_station: "Unknown", passengers: [])
                            current_passenger = nil
                        }
                    } else if lowerVal.hasPrefix("partenza ") {
                        let startIndex = val.index(val.startIndex, offsetBy: 9)
                        current_train?.dep_station = String(val[startIndex...]).trimmingCharacters(in: .whitespaces)
                        if i + 1 < nodes.count, let nType = nodes[i+1]["type"] as? String, let nVal = nodes[i+1]["val"] as? String, nType == "text", nVal.contains(" - ") {
                            current_train?.date = nVal.components(separatedBy: " - ")[0].trimmingCharacters(in: .whitespaces)
                        }
                    } else if lowerVal.hasPrefix("arrivo ") {
                        let startIndex = val.index(val.startIndex, offsetBy: 7)
                        current_train?.arr_station = String(val[startIndex...]).trimmingCharacters(in: .whitespaces)
                    } else if lowerVal.hasPrefix("passenger ") || lowerVal.hasPrefix("passeggero ") {
                        if let cp = current_passenger {
                            current_train?.passengers.append(cp)
                        }
                        current_passenger = ScrapedPassenger(name: "Unknown", coach: "N/A", seat: "N/A", qrData: nil)
                        
                        var offset = 1
                        if i + 1 < nodes.count, let nextVal = nodes[i+1]["val"] as? String, nextVal.count <= 3, nextVal == nextVal.uppercased() {
                            offset = 2
                        }
                        
                        var firstName = ""
                        var lastName = ""
                        if i + offset < nodes.count, nodes[i+offset]["type"] as? String == "text" {
                            firstName = nodes[i+offset]["val"] as? String ?? ""
                        }
                        if i + offset + 1 < nodes.count, nodes[i+offset+1]["type"] as? String == "text" {
                            let nxt = nodes[i+offset+1]["val"] as? String ?? ""
                            if !nxt.hasPrefix("Code:") && !nxt.hasPrefix("Offer") && !nxt.hasPrefix("EXPIRED") {
                                lastName = nxt
                            }
                        }
                        
                        if !firstName.isEmpty {
                            let nameStr = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
                            let lettersOnly = nameStr.components(separatedBy: CharacterSet.letters.union(.whitespaces).inverted).joined()
                            current_passenger?.name = lettersOnly
                        }
                    } else if lowerVal == "coach" || lowerVal == "carrozza" {
                        if current_passenger != nil, i + 1 < nodes.count, nodes[i+1]["type"] as? String == "text" {
                            current_passenger?.coach = nodes[i+1]["val"] as? String ?? ""
                        }
                    } else if lowerVal == "seat" || lowerVal == "posto" {
                        if current_passenger != nil, i + 1 < nodes.count, nodes[i+1]["type"] as? String == "text" {
                            current_passenger?.seat = nodes[i+1]["val"] as? String ?? ""
                        }
                    }
                } else if type == "qr" {
                    if current_passenger != nil {
                        if val.starts(with: "data:image/") {
                            let components = val.components(separatedBy: ",")
                            if components.count > 1, let data = Data(base64Encoded: components[1]) {
                                current_passenger?.qrData = data
                            }
                        }
                    }
                }
                
                i += 1
            }
            
            if let cp = current_passenger {
                current_train?.passengers.append(cp)
            }
            if let ct = current_train {
                journeys.append(ct)
            }
            
            cont.resume(returning: journeys)
        }
    }
}
