import AppKit

@MainActor
final class OpacityMenuItemView: NSView {
    private weak var session: PinSession?
    private let valueLabel = NSTextField(labelWithString: "")

    init(session: PinSession) {
        self.session = session
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 34))

        valueLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        let slider = NSSlider(
            value: Double(session.opacity),
            minValue: 0.15,
            maxValue: 1,
            target: self,
            action: #selector(opacityChanged(_:))
        )
        slider.isContinuous = true
        slider.translatesAutoresizingMaskIntoConstraints = false

        addSubview(valueLabel)
        addSubview(slider)
        updateValueLabel(session.opacity)

        NSLayoutConstraint.activate([
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLabel.widthAnchor.constraint(equalToConstant: 38),
            slider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 21),
            slider.trailingAnchor.constraint(equalTo: valueLabel.leadingAnchor, constant: -8),
            slider.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    @objc private func opacityChanged(_ slider: NSSlider) {
        let opacity = CGFloat(slider.doubleValue)
        session?.opacity = opacity
        updateValueLabel(opacity)
    }

    private func updateValueLabel(_ opacity: CGFloat) {
        let percentage = max(15, Int((opacity * 20).rounded()) * 5)
        valueLabel.stringValue = "\(percentage)%"
    }
}
