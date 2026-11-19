import UIKit

/// Keyboard behaviour for form screens (Add Place, review composer):
/// - the scroll view is inset by the keyboard and the focused field is scrolled into view,
/// - scrolling dismisses the keyboard, so does tapping empty space (without swallowing taps on maps or buttons),
/// - every field gets a "Done" bar above the keyboard (number pads and text views have no return key),
/// - Return in a text field moves to the next field; the last one closes the keyboard.
/// Keep a strong reference for the screen's lifetime.
final class FormKeyboardHandler: NSObject, UIGestureRecognizerDelegate {
    private weak var scrollView: UIScrollView?
    private weak var rootView: UIView?
    private var baseBottomInset: CGFloat = 0

    init(scrollView: UIScrollView, rootView: UIView) {
        self.scrollView = scrollView
        self.rootView = rootView
        super.init()
        scrollView.keyboardDismissMode = .onDrag
        baseBottomInset = scrollView.contentInset.bottom

        let tap = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        rootView.addGestureRecognizer(tap)

        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChange(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)),
                                               name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    /// Adds the "Done" bar to every input, and Next/Done return keys to text fields in the given order.
    func manage(_ inputs: [UIView]) {
        let fields = inputs.compactMap { $0 as? UITextField }
        for input in inputs {
            if let field = input as? UITextField {
                field.inputAccessoryView = makeDoneBar()
                let isLast = field === fields.last
                field.returnKeyType = isLast ? .done : .next
                field.addAction(UIAction { [weak self, weak field] _ in
                    guard let field else { return }
                    self?.focus(after: field, in: inputs)
                }, for: .editingDidEndOnExit)
            } else if let textView = input as? UITextView {
                textView.inputAccessoryView = makeDoneBar()
            }
        }
    }

    private func focus(after field: UIView, in inputs: [UIView]) {
        guard let index = inputs.firstIndex(where: { $0 === field }) else { return }
        let next = inputs[(index + 1)...].first { !$0.isHidden && $0.isUserInteractionEnabled && $0.window != nil }
        if let next, next is UITextField || next is UITextView {
            next.becomeFirstResponder()
        } else {
            rootView?.endEditing(true)
        }
    }

    private func makeDoneBar() -> UIToolbar {
        let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        let done = UIBarButtonItem(title: L10n.Common.done, style: .prominent, target: self, action: #selector(doneTapped))
        bar.items = [UIBarButtonItem(systemItem: .flexibleSpace), done]
        bar.sizeToFit()
        return bar
    }

    @objc private func doneTapped() { rootView?.endEditing(true) }

    @objc private func backgroundTapped() { rootView?.endEditing(true) }

    // Taps on fields and controls keep their normal behaviour (no flicker when moving between fields).
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let current = view {
            if current is UITextField || current is UITextView || current is UIControl { return false }
            view = current.superview
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    // MARK: Insets

    @objc private func keyboardWillChange(_ notification: Notification) {
        guard let scrollView, let window = scrollView.window,
              let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let scrollFrame = scrollView.convert(scrollView.bounds, to: window)
        let overlap = max(0, scrollFrame.maxY - frame.minY)
        // The safe area is already part of the adjusted inset.
        let inset = max(0, overlap - scrollView.safeAreaInsets.bottom)
        setBottomInset(baseBottomInset + inset, notification: notification)
        if overlap > 0 { revealFirstResponder() }
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        setBottomInset(baseBottomInset, notification: notification)
    }

    private func setBottomInset(_ inset: CGFloat, notification: Notification) {
        guard let scrollView, scrollView.contentInset.bottom != inset else { return }
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        UIView.animate(withDuration: duration) {
            scrollView.contentInset.bottom = inset
            scrollView.verticalScrollIndicatorInsets.bottom = inset
        }
    }

    private func revealFirstResponder() {
        guard let scrollView, let responder = Self.firstResponder(in: scrollView) else { return }
        var rect = responder.convert(responder.bounds, to: scrollView)
        if let textView = responder as? UITextView, let range = textView.selectedTextRange {
            // Long text views: keep the caret visible rather than the whole view.
            let caret = textView.caretRect(for: range.end)
            rect = textView.convert(caret, to: scrollView).insetBy(dx: 0, dy: -AppSpacing.xl)
        } else {
            rect = rect.insetBy(dx: 0, dy: -AppSpacing.l)
        }
        DispatchQueue.main.async { scrollView.scrollRectToVisible(rect, animated: true) }
    }

    private static func firstResponder(in view: UIView) -> UIView? {
        if view.isFirstResponder { return view }
        for subview in view.subviews {
            if let found = firstResponder(in: subview) { return found }
        }
        return nil
    }
}
