import SwiftUI
import SwiftData

struct EmailInboxView: View {
    let linkedEmail: LinkedEmail
    
    @State private var emails: [IMAPClient.EmailResult] = []
    @State private var isLoading = true
    @State private var errorMsg: String?
    
    @Query private var trains: [Train]
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView("Connecting to \(linkedEmail.provider)...")
                        .padding()
                    Spacer()
                }
            } else if let errorMsg = errorMsg {
                Text(errorMsg)
                    .foregroundColor(.red)
            } else if emails.isEmpty {
                Text("No Trenitalia check-in emails found.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(emails) { email in
                    EmailRowView(emailResult: email, isAlreadySaved: isTrainSaved(email), scraper: TicketScraper())
                }
            }
        }
        .navigationTitle(linkedEmail.email)
        .fontDesign(.rounded)
        .onAppear {
            Task {
                await fetchEmails()
            }
        }
    }
    
    private func fetchEmails() async {
        let client = IMAPClient()
        do {
            let fetched = try await client.fetchTrenitaliaEmails(provider: linkedEmail.provider, email: linkedEmail.email, appPassword: linkedEmail.appPassword)
            await MainActor.run {
                self.emails = fetched
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMsg = "Failed to fetch emails: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
    
    private func isTrainSaved(_ email: IMAPClient.EmailResult) -> Bool {
        guard let tNum = email.trainNumber else { return false }
        // Simple check by train number, optionally date
        return trains.contains { $0.number.contains(tNum) }
    }
}

struct EmailRowView: View {
    let emailResult: IMAPClient.EmailResult
    let isAlreadySaved: Bool
    let scraper: TicketScraper
    
    @State private var isScraping = false
    @State private var showError = false
    @Environment(\.modelContext) private var modelContext
    
    private var isFuture: Bool {
        guard let dStr = emailResult.depDate else { return true }
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        if let d = formatter.date(from: dStr) {
            return d > Date()
        }
        return true
    }
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(emailResult.dateString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let tNum = emailResult.trainNumber {
                    Text("Train \(tNum)")
                        .font(.headline)
                } else {
                    Text("Train Ticket")
                        .font(.headline)
                }
                
                if let dep = emailResult.depStation, let arr = emailResult.arrStation {
                    Text("\(dep) -> \(arr)")
                        .font(.subheadline)
                }
            }
            
            Spacer()
            
            if isAlreadySaved {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)
            } else if !isFuture {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.title2)
            } else {
                if isScraping {
                    ProgressView()
                } else {
                    Button {
                        Task { await addTrain() }
                    } label: {
                        Text("Add")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
        .alert("Scraping Failed", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        }
    }
    
    private func addTrain() async {
        isScraping = true
        defer { isScraping = false }
        
        guard let url = emailResult.urls.first else { return }
        do {
            let journeys = try await scraper.scrapeTickets(url: url)
            
            for journey in journeys {
                // Save logic here
                let newTrain = Train(id: UUID(), logo: "trenitalia", number: journey.number, identifier: "\(journey.number)-\(journey.date)", provider: "Trenitalia", last_update_time: Date(), delay: 0, direction: journey.arr_station, issue: "")
                modelContext.insert(newTrain)
                
                let stop1 = Stop(id: newTrain.id, name: journey.dep_station, platform: "", weather: "", is_selected: true, status: 0, is_completed: false, is_in_station: false, dep_delay: 0, arr_delay: 0, dep_time_id: Date(), arr_time_id: Date(), dep_time_eff: Date(), arr_time_eff: Date(), ref_time: Date())
                modelContext.insert(stop1)
                
                let stop2 = Stop(id: newTrain.id, name: journey.arr_station, platform: "", weather: "", is_selected: true, status: 0, is_completed: false, is_in_station: false, dep_delay: 0, arr_delay: 0, dep_time_id: Date().addingTimeInterval(3600), arr_time_id: Date().addingTimeInterval(3600), dep_time_eff: Date().addingTimeInterval(3600), arr_time_eff: Date().addingTimeInterval(3600), ref_time: Date())
                modelContext.insert(stop2)
                
                for pass in journey.passengers {
                    let newSeat = Seat(id: UUID(), trainID: newTrain.id, name: pass.name, carriage: pass.coach, number: pass.seat, image: pass.qrData)
                    modelContext.insert(newSeat)
                }
            }
            try? modelContext.save()
        } catch {
            showError = true
        }
    }
}
