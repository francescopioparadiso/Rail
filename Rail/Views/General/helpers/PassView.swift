import SwiftUI
import SwiftData
import StoreKit

struct PassView: View {
    // MARK: - variables
    // environment variables
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) var requestReview
    
    // data variables
    let pass: Pass
    @State private var qrImage: UIImage?
    
    // MARK: - main content
    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            
            VStack(spacing: 16) {
                // code
                if let qrImage {
                    Image(uiImage: qrImage)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .padding()
                        .background(Color.white)
                        .cornerRadius(24)
                        
                } else if pass.image != nil {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(app_background_color)
        .presentationDetents([.medium, .large])
        .task(id: pass.id) {
            guard let data = pass.image else {
                qrImage = nil
                return
            }
            qrImage = await Task.detached(priority: .userInitiated) {
                UIImage(data: data)
            }.value
        }
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
