//
//  GameShaderParameterCell.swift
//  RetroGo
//
//  Created by haharsw on 2026/10/19.
//  Copyright © 2026 haharsw. All rights reserved.
//
//  ---------------------------------------------------------------------------------
//  This file is part of RetroGo.
//  ---------------------------------------------------------------------------------
//
//  RetroGo is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  RetroGo is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import UIKit

/// Keep only the latest quantized value; returning to the submitted value cancels a pending update.
struct GameShaderSliderUpdates {
    private var submitted: Double
    private var pending: Double?

    init(value: Double) { submitted = value }

    mutating func update(_ value: Double) {
        pending = value == submitted ? nil : value
    }

    mutating func takePending() -> Double? {
        guard let value = pending else { return nil }
        pending = nil
        submitted = value
        return value
    }
}

final class GameShaderParameterCell: UITableViewCell {
    private let titleLabel = UILabel()
    private let valueLabel = UILabel()
    private let slider = UISlider()
    private var parameter: GameShaderParameter?
    private var updates = GameShaderSliderUpdates(value: 0)
    private var previewTimer: Timer?
    var onChange: ((Double) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.numberOfLines = 0
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        valueLabel.textColor = .secondaryLabel
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let labels = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        labels.spacing = 12
        labels.alignment = .firstBaseline
        let stack = UIStackView(arrangedSubviews: [labels, slider])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
        slider.tintColor = .mainColor
        slider.addTarget(self, action: #selector(changed), for: .valueChanged)
        slider.addTarget(self, action: #selector(finishEditing), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { previewTimer?.invalidate() }

    override func prepareForReuse() {
        finishEditing()
        onChange = nil
        super.prepareForReuse()
    }

    func configure(_ parameter: GameShaderParameter, value: Double, displayTitle: String? = nil) {
        self.parameter = parameter
        titleLabel.text = displayTitle ?? parameter.title
        slider.minimumValue = Float(parameter.minimum)
        slider.maximumValue = Float(parameter.maximum)
        slider.accessibilityLabel = displayTitle ?? parameter.title
        setValue(value)
    }

    func setValue(_ value: Double) {
        guard let parameter else { return }
        previewTimer?.invalidate()
        previewTimer = nil
        let value = parameter.normalized(value)
        updates = GameShaderSliderUpdates(value: value)
        slider.value = Float(value)
        updateLabel(value)
    }

    private func updateLabel(_ value: Double) {
        guard let parameter else { return }
        valueLabel.text = String(format: parameter.valueFormat, value)
        slider.accessibilityValue = valueLabel.text
    }

    @objc private func changed() {
        guard let parameter else { return }
        let value = parameter.normalized(Double(slider.value))
        // Do not move the thumb underneath the finger. Quantization affects labels and the shader only.
        updateLabel(value)
        updates.update(value)
        guard slider.isTracking else {
            slider.value = Float(value)
            flushPreview()
            return
        }
        guard previewTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: false) { [weak self] _ in self?.flushPreview() }
        previewTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func flushPreview() {
        previewTimer?.invalidate()
        previewTimer = nil
        if let value = updates.takePending() { onChange?(value) }
    }

    /// Flush before navigation, reset or save so the latest drag is never lost or applied late.
    @objc func finishEditing() {
        flushPreview()
        if let parameter {
            slider.value = Float(parameter.normalized(Double(slider.value)))
        }
    }
}
