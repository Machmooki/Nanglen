import CoreMotion
import SceneKit
import UIKit

/// Full-screen 360° viewer for an equirectangular (2:1) panorama photo.
/// Drag to look around, pinch to zoom, or switch on motion to look around by moving the phone.
/// The photo is mapped onto the inside of a sphere with the camera at its centre.
final class PanoramaViewController: UIViewController {
    private let imageURL: URL
    private let placeName: String

    private let sceneView = SCNView()
    private let cameraNode = SCNNode()
    private let sphereNode = SCNNode()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let closeButton = UIButton(type: .system)
    private let motionButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let hintLabel = UILabel()
    private let errorLabel = UILabel()

    private let motionManager = CMMotionManager()
    private var displayLink: CADisplayLink?
    private var usesMotion = false

    private var yaw: Float = 0
    private var pitch: Float = 0
    private var gestureStart: (yaw: Float, pitch: Float) = (0, 0)
    private var fieldOfViewAtPinchStart: CGFloat = 75
    private var loadTask: Task<Void, Never>?

    private static let defaultFieldOfView: CGFloat = 75
    private static let fieldOfViewRange: ClosedRange<CGFloat> = 35...100
    /// SceneKit textures above this size fail on some devices; larger panoramas are scaled down.
    private nonisolated static let maxTextureWidth: CGFloat = 8_192

    init(imageURL: URL, placeName: String) {
        self.imageURL = imageURL
        self.placeName = placeName
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("PanoramaViewController is created in code")
    }

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setUpScene()
        setUpOverlay()
        setUpGestures()
        loadPanorama()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        setMotion(enabled: false)
        loadTask?.cancel()
    }

    // MARK: Scene

    private func setUpScene() {
        let scene = SCNScene()

        let sphere = SCNSphere(radius: 10)
        sphere.segmentCount = 96
        let material = SCNMaterial()
        material.lightingModel = .constant
        // Draw the inside of the sphere, and flip horizontally so the photo isn't mirrored.
        material.cullMode = .front
        material.diffuse.contents = UIColor.black
        material.diffuse.wrapS = .repeat
        material.diffuse.contentsTransform = SCNMatrix4MakeScale(-1, 1, 1)
        sphere.firstMaterial = material
        sphereNode.geometry = sphere
        scene.rootNode.addChildNode(sphereNode)

        let camera = SCNCamera()
        camera.fieldOfView = Self.defaultFieldOfView
        camera.zNear = 0.1
        camera.zFar = 50
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 0)
        scene.rootNode.addChildNode(cameraNode)

        sceneView.scene = scene
        sceneView.pointOfView = cameraNode
        sceneView.backgroundColor = .black
        sceneView.antialiasingMode = .multisampling4X
        sceneView.allowsCameraControl = false
        sceneView.isAccessibilityElement = true
        sceneView.accessibilityLabel = "\(placeName), \(L10n.Detail.view360)"
        sceneView.accessibilityHint = L10n.Detail.panoramaHint
        sceneView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sceneView)
        NSLayoutConstraint.activate([
            sceneView.topAnchor.constraint(equalTo: view.topAnchor),
            sceneView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sceneView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        applyLook()
    }

    private func applyLook() {
        cameraNode.eulerAngles = SCNVector3(pitch, yaw, 0)
    }

    // MARK: Overlay

    private func setUpOverlay() {
        var close = UIButton.Configuration.glass()
        close.image = UIImage(systemName: "xmark")
        close.cornerStyle = .capsule
        close.baseForegroundColor = .white
        closeButton.configuration = close
        closeButton.accessibilityLabel = L10n.Common.close
        closeButton.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .primaryActionTriggered)

        var motion = UIButton.Configuration.glass()
        motion.image = UIImage(systemName: "gyroscope")
        motion.cornerStyle = .capsule
        motion.baseForegroundColor = .white
        motionButton.configuration = motion
        motionButton.accessibilityLabel = L10n.Detail.panoramaMotion
        motionButton.isHidden = !motionManager.isDeviceMotionAvailable
        motionButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            AppComponents.selectionHaptic()
            setMotion(enabled: !usesMotion)
        }, for: .primaryActionTriggered)

        titleLabel.apply(AppTypography.headline, color: .white)
        titleLabel.text = placeName
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        titleLabel.layer.shadowColor = UIColor.black.cgColor
        titleLabel.layer.shadowOpacity = 0.5
        titleLabel.layer.shadowRadius = 6
        titleLabel.layer.shadowOffset = .zero

        let badge = OverlayChipView(style: .dark)
        badge.configure(symbol: "rotate.3d", text: L10n.Detail.view360)

        hintLabel.apply(AppTypography.footnote, color: .white)
        hintLabel.text = L10n.Detail.panoramaHint
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0
        hintLabel.layer.shadowColor = UIColor.black.cgColor
        hintLabel.layer.shadowOpacity = 0.6
        hintLabel.layer.shadowRadius = 6
        hintLabel.layer.shadowOffset = .zero
        hintLabel.alpha = 0

        errorLabel.apply(AppTypography.body, color: .white)
        errorLabel.text = L10n.Detail.panoramaFailed
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true

        spinner.color = .white
        spinner.hidesWhenStopped = true

        let titleStack = UIStackView(arrangedSubviews: [titleLabel, badge])
        titleStack.axis = .vertical
        titleStack.alignment = .center
        titleStack.spacing = AppSpacing.xs

        [closeButton, motionButton, titleStack, hintLabel, errorLabel, spinner].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: guide.topAnchor, constant: AppSpacing.s),
            closeButton.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: AppSpacing.l),
            closeButton.widthAnchor.constraint(equalToConstant: 48),
            closeButton.heightAnchor.constraint(equalToConstant: 48),
            motionButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            motionButton.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -AppSpacing.l),
            motionButton.widthAnchor.constraint(equalToConstant: 48),
            motionButton.heightAnchor.constraint(equalToConstant: 48),
            titleStack.topAnchor.constraint(equalTo: guide.topAnchor, constant: AppSpacing.s),
            titleStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleStack.leadingAnchor.constraint(greaterThanOrEqualTo: closeButton.trailingAnchor, constant: AppSpacing.s),
            titleStack.trailingAnchor.constraint(lessThanOrEqualTo: motionButton.leadingAnchor, constant: -AppSpacing.s),
            hintLabel.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -AppSpacing.xxl),
            hintLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: AppSpacing.xl),
            hintLabel.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -AppSpacing.xl),
            errorLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: AppSpacing.xxl),
            errorLabel.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -AppSpacing.xxl),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func showHint(_ text: String) {
        hintLabel.text = text
        UIView.animate(withDuration: 0.3) { self.hintLabel.alpha = 1 } completion: { _ in
            UIView.animate(withDuration: 0.6, delay: 2.5, options: [.allowUserInteraction]) { self.hintLabel.alpha = 0 }
        }
    }

    // MARK: Gestures

    private func setUpGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        sceneView.addGestureRecognizer(pan)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        sceneView.addGestureRecognizer(pinch)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        sceneView.addGestureRecognizer(doubleTap)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard !usesMotion else { return }
        if gesture.state == .began { gestureStart = (yaw, pitch) }
        let translation = gesture.translation(in: sceneView)
        // Scale drag speed with zoom so the photo moves roughly under the finger.
        let fieldOfView = Float(cameraNode.camera?.fieldOfView ?? Self.defaultFieldOfView)
        let radiansPerPoint = (fieldOfView * .pi / 180) / Float(max(sceneView.bounds.height, 1))
        yaw = gestureStart.yaw + Float(translation.x) * radiansPerPoint
        let limit = Float.pi / 2 - 0.05
        pitch = min(max(gestureStart.pitch + Float(translation.y) * radiansPerPoint, -limit), limit)
        applyLook()
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let camera = cameraNode.camera else { return }
        if gesture.state == .began { fieldOfViewAtPinchStart = camera.fieldOfView }
        let target = fieldOfViewAtPinchStart / max(gesture.scale, 0.01)
        camera.fieldOfView = min(max(target, Self.fieldOfViewRange.lowerBound), Self.fieldOfViewRange.upperBound)
    }

    @objc private func handleDoubleTap() {
        guard let camera = cameraNode.camera else { return }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.3
        camera.fieldOfView = camera.fieldOfView < Self.defaultFieldOfView - 1 ? Self.defaultFieldOfView : 50
        SCNTransaction.commit()
    }

    // MARK: Motion

    private func setMotion(enabled: Bool) {
        guard enabled != usesMotion, motionManager.isDeviceMotionAvailable || !enabled else { return }
        usesMotion = enabled
        if enabled {
            motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
            motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical)
            let link = CADisplayLink(target: self, selector: #selector(motionTick))
            link.add(to: .main, forMode: .common)
            displayLink = link
            showHint(L10n.Detail.panoramaMotionOn)
        } else {
            displayLink?.invalidate()
            displayLink = nil
            motionManager.stopDeviceMotionUpdates()
            // Continue dragging from where the phone was pointing.
            yaw = cameraNode.eulerAngles.y
            pitch = min(max(cameraNode.eulerAngles.x, -Float.pi / 2 + 0.05), Float.pi / 2 - 0.05)
            applyLook()
        }
        var config = motionButton.configuration
        config?.baseForegroundColor = enabled ? AppColors.primary : .white
        motionButton.configuration = config
        motionButton.isSelected = enabled
        motionButton.accessibilityTraits = enabled ? [.button, .selected] : .button
    }

    /// Reads the latest attitude on the main thread each frame (no background callbacks to synchronise).
    @objc private func motionTick() {
        guard let attitude = motionManager.deviceMotion?.attitude.quaternion else { return }
        let device = simd_quatf(ix: Float(attitude.x), iy: Float(attitude.y), iz: Float(attitude.z), r: Float(attitude.w))
        // CoreMotion's "zero" is the phone lying flat; rotate so holding it upright looks at the horizon.
        let upright = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))
        cameraNode.simdOrientation = upright * device
    }

    // MARK: Loading

    private func loadPanorama() {
        spinner.startAnimating()
        let url = imageURL
        loadTask = Task { [weak self] in
            let image = await Self.panoramaImage(at: url)
            guard !Task.isCancelled, let self else { return }
            spinner.stopAnimating()
            guard let image else {
                errorLabel.isHidden = false
                return
            }
            sphereNode.geometry?.firstMaterial?.diffuse.contents = image
            showHint(L10n.Detail.panoramaHint)
        }
    }

    /// Downloads and decodes off the main actor; large panoramas are scaled to a size SceneKit can use.
    @concurrent
    private nonisolated static func panoramaImage(at url: URL) async -> UIImage? {
        let data: Data?
        if url.isFileURL {
            data = try? Data(contentsOf: url)
        } else {
            data = try? await URLSession.shared.data(from: url).0
        }
        guard let data, let image = UIImage(data: data) else { return nil }
        let pixelWidth = image.size.width * image.scale
        if pixelWidth > maxTextureWidth {
            let ratio = maxTextureWidth / pixelWidth
            let size = CGSize(width: maxTextureWidth, height: (image.size.height * image.scale * ratio).rounded())
            if let scaled = await image.byPreparingThumbnail(ofSize: size) { return scaled }
        }
        return await image.byPreparingForDisplay() ?? image
    }
}
