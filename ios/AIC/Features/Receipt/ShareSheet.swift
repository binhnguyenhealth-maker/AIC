import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let artifact: ReceiptArtifact
    let onComplete: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [artifact.fileURL], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            try? FileManager.default.removeItem(at: artifact.fileURL)
            DispatchQueue.main.async { onComplete() }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
