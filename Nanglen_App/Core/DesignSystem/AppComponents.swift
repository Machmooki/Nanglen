import UIKit

/// Small factories and helpers shared by components and screens.
enum AppComponents {
    /// Fills a stack view with views, removing what was there before.
    static func replaceArrangedSubviews(of stack: UIStackView, with views: [UIView]) {
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        views.forEach(stack.addArrangedSubview)
    }

    /// Thin divider line that adapts to light/dark mode.
    static func divider() -> UIView {
        let view = UIView()
        view.backgroundColor = .separator
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 1 / max(UITraitCollection.current.displayScale, 1)).isActive = true
        return view
    }

    /// Light haptic used for selections and confirmations.
    static func selectionHaptic() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func successHaptic() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Spring "press" animation for card-like cells.
    static func animatePress(_ view: UIView, pressed: Bool) {
        UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            view.transform = pressed ? CGAffineTransform(scaleX: 0.97, y: 0.97) : .identity
        }
    }

    /// Standard OK alert for recoverable errors.
    static func errorAlert(title: String, message: String) -> UIAlertController {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.Common.ok, style: .default))
        return alert
    }
}
