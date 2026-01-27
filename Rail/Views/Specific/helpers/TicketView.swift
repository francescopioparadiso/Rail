import SwiftUI
import SwiftData

struct TicketView: View {
    // MARK: - variables
    // environment variables
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) var request_review
    
    // data variables
    let seat: Seat
    
    // MARK: - main content
    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            
            VStack(spacing: 16) {
                // code
                if let imageData = seat.image, let uiImage = UIImage(data: imageData) {
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
                HStack {
                    Text(seat.name)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    if !seat.carriage.isEmpty && !seat.number.isEmpty {
                        Spacer()
                        
                        HStack (spacing: 16) {
                            HStack(spacing: 8) {
                                Image(systemName: "train.side.rear.car")
                                Text(seat.carriage)
                            }
                            
                            HStack(spacing: 8) {
                                Image(systemName: "carseat.left.fill")
                                Text(seat.number)
                            }
                        }
                        .font(.body)
                    }
                }
                .fontDesign(app_font_design)
                .padding(.vertical, 8).padding(.horizontal, 12)
                .foregroundStyle(.secondary)
            }
            .padding(32)
            
            Spacer(minLength: 0)
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            ReviewManager.shared.requestReviewIfAppropriate(action: request_review)
        }
    }
}
