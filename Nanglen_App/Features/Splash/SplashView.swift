//
//  SplashView.swift
//  Nanglen_App
//
//  Animated launch splash: the logo writes itself like handwriting, then the splash fades into the app.
//

import UIKit

/// Full-screen splash that SceneDelegate puts on top of the window at launch.
///
/// The finished image is always the exact logo shape (`SplashLogo.fill`, filled with `AppColors.primary`).
/// It is revealed through a mask of four thick, round-capped strokes whose `strokeEnd` animates 0 → 1,
/// so the strokes act like a pen: first the "u", then the three sparks flicking outwards.
///
/// The first frame is plain `AppColors.background`, the same as LaunchScreen.storyboard,
/// so the handoff from the system launch screen is invisible.
final class SplashView: UIView {
    /// On-screen width of the finished logo, in points.
    private static let logoWidth: CGFloat = 120

    /// Logo-sized layer centred in the view; the settle pulse scales it around the logo's centre.
    private let logoContainer = CALayer()
    /// Holds the artwork in its 1024 × 1024 design space, scaled down to `logoWidth`.
    private let artworkLayer = CALayer()
    /// The exact logo shape in the brand colour.
    private let fillLayer = CAShapeLayer()
    /// Mask over `fillLayer`: only what the pen has drawn so far is visible.
    private let penLayer = CALayer()
    private let strokeLayers: [CAShapeLayer]

    override init(frame: CGRect) {
        strokeLayers = SplashLogo.strokes.map { stroke in
            let layer = CAShapeLayer()
            layer.path = stroke.path
            layer.lineWidth = stroke.lineWidth
            layer.lineCap = .round
            layer.lineJoin = .round
            layer.strokeColor = UIColor.white.cgColor
            layer.fillColor = nil
            layer.strokeEnd = 0 // nothing is drawn until the intro starts
            return layer
        }
        super.init(frame: frame)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SplashView is created in code")
    }

    private func setUp() {
        backgroundColor = AppColors.background
        // Blocks taps while the splash covers the app; VoiceOver skips it (it is decoration only).
        accessibilityElementsHidden = true

        let bounds = SplashLogo.bounds
        let scale = Self.logoWidth / bounds.width
        logoContainer.bounds = CGRect(x: 0, y: 0, width: bounds.width * scale, height: bounds.height * scale)

        // Map the logo's bounding box onto the container: artwork point p lands at position + scale * p.
        artworkLayer.bounds = CGRect(x: 0, y: 0, width: SplashLogo.canvasSize, height: SplashLogo.canvasSize)
        artworkLayer.anchorPoint = .zero
        artworkLayer.position = CGPoint(x: -bounds.minX * scale, y: -bounds.minY * scale)
        artworkLayer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))

        fillLayer.frame = artworkLayer.bounds
        fillLayer.path = SplashLogo.fill
        penLayer.frame = artworkLayer.bounds
        strokeLayers.forEach(penLayer.addSublayer)
        fillLayer.mask = penLayer

        artworkLayer.addSublayer(fillLayer)
        logoContainer.addSublayer(artworkLayer)
        layer.addSublayer(logoContainer)

        updateColors()
        registerForTraitChanges(UITraitCollection.systemTraitsAffectingColorAppearance) { (view: SplashView, _: UITraitCollection) in
            view.updateColors()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        logoContainer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    /// CGColors don't follow Light/Dark Mode on their own, so re-resolve them for the current traits.
    private func updateColors() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fillLayer.fillColor = AppColors.primary.resolvedColor(with: traitCollection).cgColor
        CATransaction.commit()
    }

    // MARK: Animation

    /// Plays the intro and returns once the logo is complete and has settled (including the short hold).
    /// With Reduce Motion on, the finished logo is shown at once and held briefly instead.
    func playIntro() async {
        if UIAccessibility.isReduceMotionEnabled {
            showFinishedLogo()
            try? await Task.sleep(for: .seconds(Timing.reducedMotionHold))
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            CATransaction.begin()
            // Fires when every animation added below has finished, including the delayed ones.
            CATransaction.setCompletionBlock { continuation.resume() }
            addIntroAnimations()
            CATransaction.commit()
        }
        try? await Task.sleep(for: .seconds(Timing.hold))
    }

    /// Fades the splash out and removes it from the window.
    func dismiss() async {
        isUserInteractionEnabled = false // let the first taps through to the app while fading
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            UIView.animate(withDuration: Timing.fadeOut, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
                self.alpha = 0
            } completion: { _ in
                continuation.resume()
            }
        }
        removeFromSuperview()
    }

    private func showFinishedLogo() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        strokeLayers.forEach { $0.strokeEnd = 1 }
        CATransaction.commit()
    }

    private func addIntroAnimations() {
        let now = layer.convertTime(CACurrentMediaTime(), from: nil)

        for (strokeLayer, stroke) in zip(strokeLayers, SplashLogo.strokes) {
            let draw = CABasicAnimation(keyPath: "strokeEnd")
            draw.fromValue = 0
            draw.toValue = 1
            draw.beginTime = now + stroke.begin
            draw.duration = stroke.duration
            draw.timingFunction = stroke.timing
            // The model value is already the final one; `.backwards` holds 0 until this stroke begins.
            draw.fillMode = .backwards
            strokeLayer.add(draw, forKey: "draw")
        }

        let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
        pulse.values = [1, Timing.pulseScale, 1]
        pulse.keyTimes = [0, 0.5, 1]
        pulse.timingFunctions = [CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .easeInEaseOut)]
        pulse.beginTime = now + Timing.pulseBegin
        pulse.duration = Timing.pulseDuration
        logoContainer.add(pulse, forKey: "settle")

        // Set the model values last, so the layers never flash back to an unfinished state.
        CATransaction.setDisableActions(true)
        strokeLayers.forEach { $0.strokeEnd = 1 }
    }

    private enum Timing {
        static let pulseBegin: CFTimeInterval = 2.0
        static let pulseDuration: CFTimeInterval = 0.4
        static let pulseScale: CGFloat = 1.035
        static let hold: TimeInterval = 0.2
        static let reducedMotionHold: TimeInterval = 0.4
        static let fadeOut: TimeInterval = 0.35
    }
}

// MARK: - Artwork

/// The logo artwork in its 1024 × 1024 design space (y grows downwards, like UIKit).
private enum SplashLogo {
    static let canvasSize: CGFloat = 1024

    /// One pen stroke of the reveal mask, drawn in array order.
    struct Stroke {
        let path: CGPath
        let lineWidth: CGFloat
        /// Seconds from the start of the intro.
        let begin: CFTimeInterval
        let duration: CFTimeInterval
        let timing: CAMediaTimingFunction
    }

    /// The exact logo shape: the "u" plus three sparks.
    static let fill = SVGPathParser.path(from: """
        M647.8,868.4C673.6,863.2 695.3,842.4 702.7,816.0C704.4,809.8 704.5,798.3 704.5,579.0L704.5,348.5L702.2,340.5\
        C682.4,272.3 588.1,270.2 565.2,337.5L562.5,345.5L561.9,504.0C561.5,622.0 561.1,663.8 560.2,667.4\
        C556.8,681.6 546.0,697.0 532.6,707.2C512.7,722.3 488.8,729.5 459.0,729.5C414.4,729.5 393.4,712.5 383.0,668.0\
        C379.2,651.4 379.0,645.2 379.0,496.8C379.0,342.9 379.1,345.9 374.0,333.0C366.3,313.6 349.8,298.1 329.5,291.3\
        C317.5,287.2 297.1,287.3 285.5,291.3C259.9,300.2 242.1,320.9 237.4,346.9C235.4,358.5 235.4,659.4 237.5,679.7\
        C240.7,711.1 247.2,739.0 255.7,758.0C266.9,782.9 277.0,798.2 291.9,812.7C298.8,819.5 310.4,828.7 316.0,831.7\
        C317.9,832.8 321.5,834.8 324.0,836.2C333.5,841.5 351.0,847.5 365.8,850.6C373.9,852.3 393.5,854.0 404.8,854.0\
        C463.1,854.0 505.4,833.9 535.2,792.0C540.9,783.9 551.2,765.0 554.3,757.0L562.0,737.0L562.0,782.0\
        C562.6,812.1 562.6,812.6 565.3,820.5C577.6,855.7 611.9,875.7 647.8,868.4Z\
        M813.7,377.5C853.8,365.9 857.5,364.4 863.9,357.5C877.4,342.9 876.6,321.2 862.1,307.7\
        C855.3,301.3 849.3,298.8 840.0,298.2C832.9,297.8 830.7,298.3 795.0,308.5C774.4,314.4 755.3,320.3 752.7,321.7\
        C733.8,331.2 728.0,357.1 741.0,374.7C747.6,383.7 760.3,389.4 771.3,388.5C774.6,388.2 793.6,383.3 813.7,377.5Z\
        M750.0,283.0C754.7,281.0 759.8,276.4 784.8,251.6C816.1,220.6 817.9,218.4 820.6,209.4\
        C828.1,183.7 804.0,158.8 778.0,165.4C768.3,167.9 764.0,171.4 734.3,201.2C709.8,225.9 706.8,229.2 703.9,235.5\
        C690.1,264.8 720.0,295.6 750.0,283.0Z\
        M649.6,257.1C657.3,253.5 663.4,247.5 666.9,240.1C669.4,234.7 669.5,233.8 669.8,213.5\
        C669.9,201.9 669.7,181.7 669.3,168.4C668.4,144.7 668.4,144.3 665.5,138.5C662.0,131.2 655.7,125.0 648.2,121.3\
        C643.2,118.9 641.4,118.5 633.5,118.5C618.8,118.5 608.0,125.1 601.8,137.8L598.5,144.5L598.7,186.9\
        C598.9,222.1 599.2,230.3 600.5,234.8C606.7,256.0 629.6,266.4 649.6,257.1Z
        """)

    /// Tight bounding box of `fill` (control points excluded), used to size and centre the logo.
    static let bounds = fill.boundingBoxOfPath

    /// The pen. Together the strokes cover every point of `fill`, so the end result is the exact logo.
    static let strokes: [Stroke] = {
        let writing = CAMediaTimingFunction(controlPoints: 0.65, 0, 0.35, 1)
        let flick = CAMediaTimingFunction(controlPoints: 0.33, 1, 0.68, 1)
        return [
            // The "u": down the left stem, round the bowl, up to the top of the right stem,
            // then back down to the tail, like writing a u by hand.
            Stroke(path: SVGPathParser.path(from: """
                M307,358 L307,675 C307,752 360,792 440,792 C492,792 528,774 553,742 \
                C578,710 633,700 633,620 L633,358 L633,798
                """), lineWidth: 170, begin: 0.15, duration: 1.30, timing: writing),
            // Sparks, each drawn from its inner end outwards so it flicks out.
            Stroke(path: SVGPathParser.path(from: "M634,226 L633,152"), lineWidth: 96, begin: 1.50, duration: 0.26, timing: flick),
            Stroke(path: SVGPathParser.path(from: "M735,251 L787,199"), lineWidth: 96, begin: 1.62, duration: 0.26, timing: flick),
            Stroke(path: SVGPathParser.path(from: "M770,353 L838,334"), lineWidth: 96, begin: 1.74, duration: 0.26, timing: flick),
        ]
    }()
}

/// Minimal SVG path-data parser for the absolute `M`, `L`, `C` and `Z` commands the logo artwork uses.
private enum SVGPathParser {
    private enum Token {
        case command(Character)
        case number(CGFloat)
    }

    static func path(from data: String) -> CGPath {
        let tokens = tokenize(data)
        let path = CGMutablePath()
        var index = 0
        var command: Character = "M"

        func nextPoint() -> CGPoint {
            guard index + 1 < tokens.count,
                  case let .number(x) = tokens[index],
                  case let .number(y) = tokens[index + 1] else {
                assertionFailure("Malformed SVG path data")
                index = tokens.count
                return .zero
            }
            index += 2
            return CGPoint(x: x, y: y)
        }

        while index < tokens.count {
            if case let .command(next) = tokens[index] {
                command = next
                index += 1
            }
            switch command {
            case "M":
                path.move(to: nextPoint())
                command = "L" // further coordinate pairs after M are implicit line-tos
            case "L":
                path.addLine(to: nextPoint())
            case "C":
                let control1 = nextPoint(), control2 = nextPoint(), end = nextPoint()
                path.addCurve(to: end, control1: control1, control2: control2)
            case "Z":
                path.closeSubpath()
                if index < tokens.count, case .number = tokens[index] {
                    assertionFailure("Numbers after Z in SVG path data")
                    return path
                }
            default:
                assertionFailure("Unsupported SVG path command \(command)")
                return path
            }
        }
        return path
    }

    private static func tokenize(_ data: String) -> [Token] {
        var tokens: [Token] = []
        var number = ""
        func flushNumber() {
            if let value = Double(number) { tokens.append(.number(CGFloat(value))) }
            number = ""
        }
        for character in data {
            switch character {
            case "0"..."9", ".":
                number.append(character)
            case "-":
                flushNumber()
                number.append(character)
            case "M", "L", "C", "Z":
                flushNumber()
                tokens.append(.command(character))
            default: // separators: commas and whitespace
                flushNumber()
            }
        }
        flushNumber()
        return tokens
    }
}
