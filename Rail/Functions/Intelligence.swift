import Foundation
import FoundationModels

@MainActor
class IntelligenceService {
    static let shared = IntelligenceService()
    
    private init() {}
    
    func generateConnectionSuggestion(duration: String, station: String, weather: String?, index: Int = 1, total: Int = 1, language: String) async -> String? {
        // Check if Apple Intelligence is available
        guard SystemLanguageModel.default.availability == .available else { 
            return nil 
        }
        
        let prompt = """
        You are a smart travel assistant for a rail app. A traveler has a connection at \(station) station.

        Connection details:
        - Duration: \(duration)
        - Local time: \(Date())
        - Current weather: \(weather ?? "unknown")
        - Connection number: \(index) out of \(total) connections today.
        - Language: Respond strictly in \(language).

        Your task: Suggest EXACTLY one very short, catchy sentence describing what the traveler should do.

        OUTPUT RULES:
        - Exactly one sentence in \(language).
        - No quotation marks, brackets, or parentheses.
        - Concise, natural, and realistic.
        - Include 1 or 2 relevant emojis (not more).

        PRIORITY:
        - The traveler must catch the next train.
        - Never suggest anything that risks missing it.

        TIME-BASED BEHAVIOR (STRICT):

        1) Duration < 20m (URGENT/RED):
        - High risk. Only suggest going directly to the platform.
        - No distractions, no food, no coffee.
        - Emojis: movement or urgency only (e.g., 🏃‍♂️ 🚆 ⏱️).

        2) Duration 20–40m (TIGHT/ORANGE):
        - Stay alert and near the platform.
        - Suggest checking boards or positioning.
        - No food or shops.
        - Emojis: neutral/travel (e.g., 🚆 👀).

        3) Duration 40–60m (MODERATE/YELLOW):
        - Moderate flexibility.
        - Allow quick activities: stretch, fast snack, or checking news.
        - Keep it close to the station.
        - Emojis: light activity (e.g., 🚶‍♂️ ☕ 🥪).

        4) Duration > 60m (RELAXED/GREEN):
        - Relaxed and productive.
        - Suggest meaningful activities like: eating properly, light work, or resting.
        - Emojis: relaxed/productive (e.g., 💻 📖 🍽️).

        MEAL-AWARE LOGIC:

        Meal windows:
        - Lunch: 12:00–14:30
        - Dinner: 19:00–21:30

        If local time is within a meal window AND duration ≥ 40m:
        - You may suggest getting food.

        Food constraints:
        - Never suggest food if duration < 40m.
        - If 40–60m: suggest quick, efficient options only.
        - If > 60m: allow a relaxed meal.

        LOCATION RULES:
        - Prefer options inside or immediately near the station.
        - Refer naturally to the place, e.g., here at \(station).
        - Do NOT invent or mention specific restaurant names.

        WEATHER ADAPTATION:
        - Bad weather: prefer indoor actions.
        - Good weather: allow brief outdoor suggestions if time permits.

        ANTI-REPETITION:
        - Avoid repeating the same suggestion across connections.
        - Vary between movement, food, planning, relaxation, productivity.

        REALISM CONSTRAINTS:
        - Never suggest coffee, food, or shopping when time is tight (<20m).
        - Never suggest risky or time-uncertain activities.
        - Always match the tone to the available time:
        - urgent, alert, relaxed.

        DURATION FORMAT RULE:
        - If you mention time, use exactly "\(duration)" format (e.g., 1h 5m).
        - Never convert to minutes.

        GOAL:
        Produce a realistic, context-aware, time-appropriate suggestion that feels natural, helpful, and lively thanks to subtle emoji use.
        """
        
        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            
            // Sanitize output: remove quotes, parentheses, and brackets
            let sanitized = response.content
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
                .replacingOccurrences(of: "[", with: "")
                .replacingOccurrences(of: "]", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            return sanitized
        } catch {
            print("Error generating AI suggestion: \(error)")
            return nil
        }
    }
}
