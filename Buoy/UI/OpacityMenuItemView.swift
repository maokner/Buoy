import AppKit

@MainActor
final class OpacityMenuItemView: NSView {
    private weak var session: PinSession?
    private let valueLabel = NSTextField(labelWithString: "")

    init(session: PinSession) {
        self.session = session
        super.init(frame: NSRect(x: 0, y: 0, width: 244, height: 52))

        let titleLabel = NSTextField(labelWithString: "Opacity")
        titleLabel.font = .menuFont(ofSize: 0)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

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

        addSubview(titleLabel)
        addSubview(valueLabel)
        addSubview(slider)
        updateValueLabel(session.opacity)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            valueLabel.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),
            slider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            slider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            slider.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
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
        valueLabel.stringValue = "\(Int((opacity * 100).rounded()))%"
    }
}

