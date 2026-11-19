import AVFoundation
import PhotosUI
import UIKit

/// "Take Photo" / "Choose from Library" in one place, shared by Add Place, the review composer and the profile photo.
/// The camera option is hidden when there is no camera (Simulator); the library allows several photos at once.
/// Keep a strong reference (a property on the presenting view controller) while it is on screen.
final class PhotoSourcePicker: NSObject {
    private weak var presenter: UIViewController?
    private var onPick: (([UIImage]) -> Void)?
    private var limit = 1

    static var isCameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    /// - Parameters:
    ///   - limit: how many photos may still be added (the library picker allows up to this many at once).
    ///   - sourceView: anchor for the action sheet on iPad.
    func present(from presenter: UIViewController, sourceView: UIView?, limit: Int, onPick: @escaping ([UIImage]) -> Void) {
        guard limit > 0 else { return }
        self.presenter = presenter
        self.onPick = onPick
        self.limit = limit
        guard Self.isCameraAvailable else {
            presentLibrary()
            return
        }
        let sheet = UIAlertController(title: L10n.PhotoSource.title, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: L10n.PhotoSource.camera, style: .default) { [weak self] _ in self?.presentCamera() })
        sheet.addAction(UIAlertAction(title: L10n.PhotoSource.library, style: .default) { [weak self] _ in self?.presentLibrary() })
        sheet.addAction(UIAlertAction(title: L10n.Common.cancel, style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = sourceView ?? presenter.view
            popover.sourceRect = sourceView?.bounds ?? CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
        }
        presenter.present(sheet, animated: true)
    }

    // MARK: Camera

    private func presentCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted:
            showCameraDenied()
        default:
            // .notDetermined: UIImagePickerController asks for permission itself.
            let camera = UIImagePickerController()
            camera.sourceType = .camera
            camera.cameraCaptureMode = .photo
            camera.delegate = self
            presenter?.present(camera, animated: true)
        }
    }

    private func showCameraDenied() {
        let alert = UIAlertController(title: nil, message: L10n.PhotoSource.cameraDenied, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.Common.cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.Common.openSettings, style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        })
        presenter?.present(alert, animated: true)
    }

    // MARK: Library

    private func presentLibrary() {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = limit
        configuration.selection = limit > 1 ? .ordered : .default
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        presenter?.present(picker, animated: true)
    }

    private func deliver(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        onPick?(Array(images.prefix(limit)))
    }

    /// Loads one picked item as an image (decoding runs on the provider's queue).
    private static func loadImage(_ provider: NSItemProvider) async -> UIImage? {
        guard provider.canLoadObject(ofClass: UIImage.self) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                continuation.resume(returning: object as? UIImage)
            }
        }
    }
}

extension PhotoSourcePicker: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        let providers = results.map(\.itemProvider)
        guard !providers.isEmpty else { return }
        Task { [weak self] in
            var images: [UIImage] = []
            for provider in providers {
                if let image = await Self.loadImage(provider) { images.append(image) }
            }
            self?.deliver(images)
        }
    }
}

extension PhotoSourcePicker: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage
        picker.dismiss(animated: true)
        if let image { deliver([image]) }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}
