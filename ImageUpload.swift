import SwiftUI
import Amplify
import AmplifyPlugins
import PhotosUI

class S3BucketManager {
    static let shared = S3BucketManager()
    
    private init() {
        configureBucketStorage()
    }
    
    func configureBucketStorage() {
        let storageConfiguration = AWSS3StoragePluginConfiguration(
            bucket: "your-specific-bucket-name", // Replace with your actual bucket name
            region: .USEast1 // Replace with your bucket's region
        )
        
        let storagePlugin = AWSS3StoragePlugin(configuration: storageConfiguration)
        
        do {
            try Amplify.add(plugin: storagePlugin)
            try Amplify.configure()
            print("Configured with specific bucket: your-specific-bucket-name")
        } catch {
            print("Amplify configuration error: \(error)")
        }
    }
    
    func uploadImage(image: UIImage) async throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            throw URLError(.badURL)
        }
        
        let key = "public/images/\(UUID().uuidString).jpg"
        
        do {
            let result = try await Amplify.Storage.uploadData(
                key: key, 
                data: data
            ).value
            return result.key
        } catch {
            throw error
        }
    }
    
    func downloadImage(key: String) async throws -> UIImage {
        do {
            let data = try await Amplify.Storage.downloadData(key: key).value
            guard let image = UIImage(data: data) else {
                throw URLError(.cannotDecodeContentData)
            }
            return image
        } catch {
            throw error
        }
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            
            guard let provider = results.first?.itemProvider else { return }
            
            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { image, error in
                    DispatchQueue.main.async {
                        self.parent.selectedImage = image as? UIImage
                    }
                }
            }
        }
    }
}

struct ContentView: View {
    @State private var selectedImage: UIImage?
    @State private var uploadedImageKey: String?
    @State private var downloadedImage: UIImage?
    @State private var showImagePicker = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack {
            if let image = downloadedImage ?? selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 300)
            }
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
            }
            
            Button("Select Image") {
                showImagePicker = true
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(selectedImage: $selectedImage)
            }
            
            Button("Upload to S3") {
                Task {
                    guard let image = selectedImage else { return }
                    do {
                        let key = try await S3BucketManager.shared.uploadImage(image: image)
                        uploadedImageKey = key
                        print("Uploaded: \(key)")
                        errorMessage = nil
                    } catch {
                        errorMessage = "Upload failed: \(error.localizedDescription)"
                        print("Upload failed: \(error)")
                    }
                }
            }
            .disabled(selectedImage == nil)
            
            if let key = uploadedImageKey {
                Button("Download Image") {
                    Task {
                        do {
                            let image = try await S3BucketManager.shared.downloadImage(key: key)
                            downloadedImage = image
                            errorMessage = nil
                        } catch {
                            errorMessage = "Download failed: \(error.localizedDescription)"
                            print("Download failed: \(error)")
                        }
                    }
                }
            }
        }
        .padding()
    }
}

@main
struct S3ImageUploadApp: App {
    init() {
        S3BucketManager.shared
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
