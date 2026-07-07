import SwiftUI
import PhotosUI

struct AccountSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var profile = UserProfile.shared
    @State private var selectedItem: PhotosPickerItem? = nil
    
    var body: some View {
        Form {
            HStack {
                Spacer()
                PhotosPicker(selection: $selectedItem, matching: .images, photoLibrary: .shared()) {
                    if let data = profile.imageData, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 100, height: 100)
                            .foregroundColor(.accentColor)
                    }
                }
                .onChange(of: selectedItem) { _, newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self),
                           let preparedData = UserProfile.preparedProfileImageData(from: data) {
                            await MainActor.run {
                                profile.imageData = preparedData
                            }
                        }
                    }
                }
                Spacer()
            }
            .padding(.vertical)
            .listRowBackground(Color.clear)
            
            TextField("First Name", text: $profile.firstName)
            TextField("Last Name", text: $profile.lastName)
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.primary)
                        .padding(10)
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                }
            }
        }
        .onDisappear {
            profile.saveAll()
        }
    }
}
