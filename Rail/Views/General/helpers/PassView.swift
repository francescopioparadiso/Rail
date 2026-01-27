import SwiftUI
import SwiftData

struct PassView: View {
    // MARK: - variables
    // environment variables
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) var requestReview
    
    // data variables
    let pass: Pass
    
    // MARK: - main content
    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            
            VStack(spacing: 16) {
                // code
                if let imageData = pass.image, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .padding()
                        .background(Color.white)
                        .cornerRadius(24)
                        
                } else {
                    ContentUnavailableView("No Code", systemImage: "qrcode.viewfinder")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                
                // info
                VStack(spacing: 8) {
                    Text(pass.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                        
                        Text(pass.expiry_date, format: .dateTime.day().month().year())
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.vertical, 8).padding(.horizontal, 12)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(16)
                }
                .fontDesign(app_font_design)
                .foregroundStyle(Color.secondary)
            }
            .padding(32)
            
            Spacer(minLength: 0)
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - previews
#Preview {
    // memory containers
    let schema = Schema([Pass.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: config)
    
    // mock data
    let mockPass = Pass(
        id: UUID(),
        name: "Abbonamento Mensile",
        expiry_date: Calendar.current.date(byAdding: .day, value: 15, to: Date())!,
        is_principal: true,
        image: UIImage(named: "sample_code")?.pngData()
    )
    
    container.mainContext.insert(mockPass)
    
    // view
    return PassView(pass: mockPass)
        .modelContainer(container)
}
