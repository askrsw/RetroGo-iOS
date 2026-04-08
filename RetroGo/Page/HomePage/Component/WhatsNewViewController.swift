//
//  WhatsNewViewController.swift
//  RetroGo
//
//  Created by haharsw on 2026/4/8.
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
import Defaults
import ObjcHelper
import XMLTextRenderKit
import YYText

final class WhatsNewViewController: UIViewController {
    private let appId = "6758611562"
    private static var presentationPending = false

    private let version: String
    private let versionNewContent: NSAttributedString
    private let scrollView = UIScrollView()
    private let contentLabel = YYLabel()

    init(version: String, versionNewContent: NSAttributedString) {
        self.version = version
        self.versionNewContent = versionNewContent
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension WhatsNewViewController {
    static func showIfNeeded() {
        guard !presentationPending else { return }
        guard !isCurrentlyDisplayed() else { return }
        guard let currentVersion = currentVersion() else { return }
        guard let viewedVersion = Defaults[.versionNewContentViewed] else {
            Defaults[.versionNewContentViewed] = currentVersion
            return
        }
        guard viewedVersion != currentVersion else { return }
        guard let xmlUrl = currentXMLURL() else { return }

        guard let contentText = XMLTextContentQuery.listAttributedString(xmlUrl: xmlUrl, listId: "v\(currentVersion)") else {
            return
        }
        guard !contentText.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            guard !presentationPending else { return }
            guard !isCurrentlyDisplayed() else { return }
            guard let presenter = UIViewController.currentActive() else { return }

            let controller = WhatsNewViewController(version: currentVersion, versionNewContent: contentText)
            let navigationController = UINavigationController(rootViewController: controller)
            navigationController.modalPresentationStyle = .pageSheet
            if let sheet = navigationController.sheetPresentationController {
                sheet.detents = [.large()]
                sheet.prefersGrabberVisible = true
                sheet.preferredCornerRadius = 20
            }
            presentationPending = true
            presenter.present(navigationController, animated: true) {
                Defaults[.versionNewContentViewed] = currentVersion
                presentationPending = false
            }
        }
    }

    private static func currentVersion() -> String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    private static func currentXMLURL() -> URL? {
        let languageKey = Bundle.currentSimpleLanguageKey()
        return Bundle.main.url(forResource: "version", withExtension: "xml", subdirectory: "Data/xmls/\(languageKey)")
    }

    private static func isCurrentlyDisplayed() -> Bool {
        UIViewController.currentActive() is WhatsNewViewController
    }
}

extension WhatsNewViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = Bundle.localizedString(forKey: "homepage_whats_new")
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(dismissSelf))
        setupViews()
        applyContent()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        contentLabel.preferredMaxLayoutWidth = scrollView.bounds.width - 40
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || presentingViewController == nil {
            Self.presentationPending = false
        }
    }

    @objc
    private func dismissSelf() {
        dismiss(animated: true)
    }

    @objc
    private func openReviewPage() {
        guard let url = URL(string: "itms-apps://apps.apple.com/app/id\(appId)?action=write-review") else {
            return
        }
        UIApplication.shared.open(url)
    }

    private func setupViews() {
        view.backgroundColor = .systemBackground

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        contentLabel.translatesAutoresizingMaskIntoConstraints = false
        contentLabel.numberOfLines = 0
        contentLabel.displaysAsynchronously = false
        contentLabel.isUserInteractionEnabled = true
        scrollView.addSubview(contentLabel)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            contentLabel.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentLabel.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            contentLabel.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            contentLabel.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentLabel.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40)
        ])
    }

    private func applyContent() {
        contentLabel.attributedText = makeDisplayText()
        accessibilityLabel = Bundle.localizedString(forKey: "homepage_whats_new")
    }

    private func makeDisplayText() -> NSAttributedString {
        let result = NSMutableAttributedString()
        let introAttributes = baseTextAttributes()
        let bodyAttributes = baseTextAttributes()
        let outroAttributes = baseTextAttributes()

        let prev = Bundle.localizedString(forKey: "homepage_whats_new_prev")
        let post = Bundle.localizedString(forKey: "homepage_whats_new_post")
        result.append(NSAttributedString(string: prev + "\n", attributes: introAttributes))
        result.append(normalizedAttributedText(from: versionNewContent, defaultAttributes: bodyAttributes))
        result.append(NSAttributedString(string: "\n\n" + post, attributes: outroAttributes))
        result.append(makeEncouragementText())
        return result
    }

    private func normalizedAttributedText(from text: NSAttributedString, defaultAttributes: [NSAttributedString.Key: Any]? = nil) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: text)
        let attributes = defaultAttributes ?? baseTextAttributes()
        let fallbackFont = attributes[.font] as? UIFont ?? UIFont.systemFont(ofSize: 16)
        let fallbackColor = attributes[.foregroundColor] as? UIColor ?? .label
        let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle
        let fullRange = NSRange(location: 0, length: result.length)

        result.enumerateAttributes(in: fullRange) { attributes, range, _ in
            var updatedAttributes = attributes
            if updatedAttributes[.font] == nil {
                updatedAttributes[.font] = fallbackFont
            }
            if updatedAttributes[.foregroundColor] == nil {
                updatedAttributes[.foregroundColor] = fallbackColor
            }
            if updatedAttributes[.paragraphStyle] == nil, let paragraphStyle {
                updatedAttributes[.paragraphStyle] = paragraphStyle
            }
            result.setAttributes(updatedAttributes, range: range)
        }
        return result
    }

    private func baseTextAttributes() -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 6
        paragraphStyle.paragraphSpacing = 10
        paragraphStyle.lineBreakMode = .byWordWrapping
        return [
            .font: UIFont.systemFont(ofSize: 16),
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraphStyle
        ]
    }

    private func makeEncouragementText() -> NSAttributedString {
        let actionTitle = Bundle.localizedString(forKey: "homepage_whats_new_encouragement")
        let actionText = "\n" + actionTitle
        let range = NSRange(location: 1, length: actionTitle.count)

        var attributes = baseTextAttributes()
        attributes[.foregroundColor] = UIColor.mainColor
        attributes[.font] = UIFont.systemFont(ofSize: 16, weight: .semibold)
        attributes[.baselineOffset] = 2

        let text = NSMutableAttributedString(string: actionText, attributes: attributes)

        let underline = YYTextDecoration(style: .single, width: 1.25, color: UIColor.mainColor)
        text.setTextUnderline(underline, range: range)

        let highlight = YYTextHighlight()

        let highlightUnderline = YYTextDecoration(style: .single, width: 1, color: UIColor.mainColor.withAlphaComponent(0.5))
        highlight.attributes = [
            NSAttributedString.Key.foregroundColor.rawValue: UIColor.mainColor.withAlphaComponent(0.5),
            YYTextUnderlineAttributeName: highlightUnderline,
        ]

        highlight.tapAction = { [weak self] _, _, _, _ in
            Vibration.selection.vibrate()
            self?.openReviewPage()
        }

        text.setTextHighlight(highlight, range: range)

        return text
    }
}
