//
//  HomePageViewController.swift
//  RetroGo
//
//  Created by haharsw on 2026/2/11.
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

import Foundation
import UIKit
import SnapKit
import PanModal
import ObjcHelper
import RACoordinator

final class HomePageViewController: UIViewController {
    static weak var instance: HomePageViewController?

#if DEBUG
    private let logStartTime = CFAbsoluteTimeGetCurrent()
    private var stallMonitor: MainThreadStallMonitor?
#endif

    private let titleView = RetroRomPageTitleView()
    private var addBarButtonItem: UIBarButtonItem?

    private var fileBrowser: RetroRomFileBrowser!
    private var configView: RetroRomFileBrowserConfigView?
    private var viewSafeInsets = UIEdgeInsets.zero
    private var parentFileBrowser: RetroRomFileBrowser?

    private var emptyTipView: RetroRomEmptyTipView?

    private(set) var fileSortType = RetroRomHomePageState.shared.homeFileSortType {
        didSet {
            if fileSortType.rawValue != oldValue.rawValue {
                RetroRomHomePageState.shared.homeFileSortType = fileSortType
                configView?.updateState()
                fileBrowser.reloadData(reload: false, sortType: fileSortType)
            }
        }
    }

    private(set) var pendingRootParent: String?

    init() {
        super.init(nibName: nil, bundle: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: .languageChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(checkRetroItemIsEmpty), name: .romCountChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(retroFolderImported(_:)), name: .retroFolderImported, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(retroFileImported(_:)), name: .retroFileImported, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(fileTagColorChanged(_:)), name: .fileTagColorChanged, object: nil)
        Self.instance = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
#if DEBUG
        stallMonitor?.stop()
#endif
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
#if DEBUG
        trace("viewDidLoad begin")
        let monitor = MainThreadStallMonitor(threshold: 0.5, interval: 0.1)
        monitor.start()
        stallMonitor = monitor
#endif
        view.backgroundColor = .systemBackground
        navigationItem.titleView = titleView

        titleView.updatePageTitle()

        configUI()

        if RetroArchX.shared().initialized {
            updateFileBrowser()

            WhatsNewViewController.showIfNeeded()
        } else {
            NotificationCenter.default.addObserver(self, selector: #selector(retroArchReadyNotification(_:)), name: .RetroArchXReady, object: nil)
        }
#if DEBUG
        trace("viewDidLoad end")
#endif
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        if viewSafeInsets != view.safeAreaInsets {
            viewSafeInsets = view.safeAreaInsets

            let x = viewSafeInsets.left
            let y = viewSafeInsets.top
            let w = view.width - viewSafeInsets.left - viewSafeInsets.right
            let h = view.height - viewSafeInsets.top - viewSafeInsets.bottom

            if fileBrowser != nil {
                fileBrowser.frame = CGRect(x: x, y: y, width: w, height: h)
            }
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        configView?.removeFromSuperview()
        configView?.maskedView?.removeFromSuperview()
        configView?.barButtonItem.tintColor = UIColor.mainColor
        configView = nil
    }

    func iconOption() {
        Vibration.selection.vibrate()

        guard RetroRomHomePageState.shared.homeBrowserType != .icon else {
            return
        }

        RetroRomHomePageState.shared.homeBrowserType = .icon
        configView?.updateState()
        updateFileBrowser()
    }

    func listOption() {
        Vibration.selection.vibrate()

        guard RetroRomHomePageState.shared.homeBrowserType != .list else {
            return
        }

        RetroRomHomePageState.shared.homeBrowserType = .list
        configView?.updateState()
        updateFileBrowser()
    }

    func treeOption() {
        Vibration.selection.vibrate()

        guard RetroRomHomePageState.shared.homeBrowserType != .tree else {
            return
        }

        RetroRomHomePageState.shared.homeBrowserType = .tree
        configView?.updateState()
        updateFileBrowser()
    }

    func folderOption() {
        Vibration.selection.vibrate()

        guard RetroRomHomePageState.shared.homeOrganizeType != .byFolder else {
            return
        }

        RetroRomHomePageState.shared.homeOrganizeType = .byFolder
        configView?.updateState()
        updateFileBrowser()

        titleView.updatePageTitle()
        navigationController?.navigationBar.setNeedsLayout()
    }

    func tagOption() {
        Vibration.selection.vibrate()

        guard RetroRomHomePageState.shared.homeOrganizeType != .byTag else {
            return
        }

        RetroRomHomePageState.shared.homeOrganizeType = .byTag
        configView?.updateState()
        updateFileBrowser()

        titleView.updatePageTitle()
        navigationController?.navigationBar.setNeedsLayout()
    }

    func coreOption() {
        Vibration.selection.vibrate()

        guard RetroRomHomePageState.shared.homeOrganizeType != .byCore else {
            return
        }

        RetroRomHomePageState.shared.homeOrganizeType = .byCore
        configView?.updateState()
        updateFileBrowser()

        titleView.updatePageTitle()
        navigationController?.navigationBar.setNeedsLayout()
    }

    func nameOption() {
        Vibration.selection.vibrate()

        if fileSortType == .fileNameAsc {
            fileSortType = .fileNameDesc
        } else {
            fileSortType = .fileNameAsc
        }
    }

    func lastPlayOption() {
        Vibration.selection.vibrate()

        fileSortType = .lastPlay
    }

    func addDateOption() {
        Vibration.selection.vibrate()

        if fileSortType == .addDateDesc {
            fileSortType = .addDateAsc
        } else {
            fileSortType = .addDateDesc
        }
    }

    func gameDurationOption() {
        Vibration.selection.vibrate()

        fileSortType = .playTime
    }

    func refresh() {
        Vibration.selection.vibrate()

        fileBrowser.refresh(sortType: fileSortType)
    }

    func importForFolder(_ folderKey: String) {
        pendingRootParent = folderKey

        showGameImportSelector()
    }

    func enterFolder(_ item: RetroRomFolderItem, forward: Bool, completion: (() -> Void)? = nil) {
        RetroRomHomePageState.shared.homeCurrentFolder = item.key
        let meta: RetroRomFileBrowserMeta
        if RetroRomHomePageState.shared.homeBrowserType == .icon {
            meta = .iconView(organize: .byFolder, folderKey: item.key)
        } else if RetroRomHomePageState.shared.homeBrowserType == .list {
            meta = .listView(organize: .byFolder, folderKey: item.key)
        } else {
            return
        }

        let browser = getFileBrowser(meta: meta)
        view.addSubview(browser)

        let x = viewSafeInsets.left
        let y = viewSafeInsets.top
        let w = view.width - viewSafeInsets.left - viewSafeInsets.right
        let h = view.height - viewSafeInsets.top - viewSafeInsets.bottom

        if forward {
            browser.frame = CGRect(x: x + w, y: y, width: w, height: h)
            UIView.animate(withDuration: 0.25) { [unowned self] in
                browser.frame = CGRect(x: x, y: y, width: w, height: h)
                fileBrowser.frame = CGRect(x: x - w, y: y, width: w, height: h)
            } completion: { [unowned self] _ in
                fileBrowser.removeFromSuperview()
                fileBrowser = browser
                titleView.updatePageTitle()
                navigationController?.navigationBar.setNeedsLayout()

                completion?()
            }
        } else {
            browser.frame = CGRect(x: x - w, y: y, width: w, height: h)
            UIView.animate(withDuration: 0.25) { [unowned self] in
                browser.frame = CGRect(x: x, y: y, width: w, height: h)
                fileBrowser.frame = CGRect(x: x + w, y: y, width: w, height: h)
            } completion: { [unowned self] _ in
                fileBrowser.removeFromSuperview()
                fileBrowser = browser
                titleView.updatePageTitle()
                navigationController?.navigationBar.setNeedsLayout()

                completion?()
            }
        }
    }
}

extension HomePageViewController {
    private func updateFileBrowser() {
#if DEBUG
        trace("updateFileBrowser begin")
#endif
        if fileBrowser != nil {
            fileBrowser.removeFromSuperview()
        }

        fileBrowser = getFileBrowser(meta: RetroRomHomePageState.shared.browserMeta)
        view.addSubview(fileBrowser)

        do {
            let x = viewSafeInsets.left
            let y = viewSafeInsets.top
            let w = view.width - viewSafeInsets.left - viewSafeInsets.right
            let h = view.height - viewSafeInsets.top - viewSafeInsets.bottom
            fileBrowser.frame = CGRect(x: x, y: y, width: w, height: h)
        }

        checkRetroItemIsEmpty()
#if DEBUG
        trace("updateFileBrowser end")
#endif
    }

    private func getFileBrowser(meta: RetroRomFileBrowserMeta) -> RetroRomFileBrowser {
        let browserType: RetroRomFileBrowserType
        let organizeType: RetroRomFileOrganizeType
        let folderKey: String?
        switch meta {
            case .iconView(organize: let organize, folderKey: let key):
                browserType = .icon
                organizeType = organize
                folderKey = key
            case .listView(organize: let organize, folderKey: let key):
                browserType = .list
                organizeType = organize
                folderKey = key
            case .treeView:
                browserType = .tree
                organizeType = .byFolder
                folderKey = nil
        }

        let browser: RetroRomFileBrowser
        if let folderKey = folderKey, organizeType == .byFolder {
            switch browserType {
                case .icon:
                    browser = RetroRomIconFolderFileBrowser(folderKey: folderKey)
                case .list:
                    browser = RetroRomTableFolderFileBrowser(folderKey: folderKey)
                default:
                    fatalError()
            }
            if !RetroRomFolderItem.isRootFolder(key: folderKey) {
                let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handLeftPanGesture(_:)))
                browser.addGestureRecognizer(panGesture)
            }
        } else {
            switch browserType {
                case .icon:
                    browser = RetroRomIconSectionFileBrowser(organizeType: organizeType)
                case .list:
                    browser = RetroRomListSectionFileBrowser(organizeType: organizeType)
                case .tree:
                    browser = RetroRomTreeFileBrowser()
            }
        }
        return browser
    }

    private func configUI() {
#if DEBUG
        trace("configUI begin")
#endif
        let gearIcon = UIImage(systemName: "gear")
        let gearButton = UIBarButtonItem(image: gearIcon, landscapeImagePhone: gearIcon, style: .plain, target: self, action: #selector(settingsAction))
        navigationItem.leftBarButtonItem = gearButton

        let plusIcon = UIImage(systemName: "plus")
        let plusButton = UIBarButtonItem(image: plusIcon, landscapeImagePhone: plusIcon, style: .plain, target: self, action: #selector(addAction))
        addBarButtonItem = plusButton

        let configIcon = UIImage(systemName: "slider.horizontal.3")
        let configButton = UIBarButtonItem(image: configIcon, landscapeImagePhone: configIcon, style: .plain, target: self, action: #selector(configAction))
        navigationItem.rightBarButtonItems = [configButton, plusButton]
#if DEBUG
        trace("configUI end")
#endif
    }

    private func showGameImportSelector() {
        let selector = GameImportSelector { [unowned self] type in
            importGame(fileType: type)
        }

        if traitCollection.userInterfaceIdiom == .pad {
            selector.modalPresentationStyle = .popover
            selector.preferredContentSize = CGSize(width: 320, height: GameImportSelectorHeaderView.headerHeight + GameImportSelectorTableViewCell.cellHeight * 2)
            if let popover = selector.popoverPresentationController {
                popover.barButtonItem = addBarButtonItem
                popover.permittedArrowDirections = .up
                popover.delegate = self
            }
            present(selector, animated: true)
        } else {
            presentPanModal(selector)
        }
    }

    private func importGame(fileType: GameImportSelector.FileType) {
        let types: [UTType] = fileType == .file ? RetroArchX.shared().allSupportedExtensions : [.folder]
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        documentPicker.delegate = self
        documentPicker.modalPresentationStyle = .formSheet
        documentPicker.allowsMultipleSelection = fileType == .file ? true : false
        present(documentPicker, animated: true, completion: nil)
    }
}

extension HomePageViewController: UIPopoverPresentationControllerDelegate {
    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        .none
    }
}

extension HomePageViewController {
#if DEBUG
    private func trace(_ message: String) {
        let delta = CFAbsoluteTimeGetCurrent() - logStartTime
        let logMessage = String(format: "[HomePage] %@ (t=%.3fs)", message, delta)
        NSLog(logMessage)
    }
#endif

    @objc
    private func handLeftPanGesture(_ pan: UIPanGestureRecognizer) {
        let translation = pan.translation(in: pan.view)
        switch pan.state {
            case .began:
                let parent = RetroRomHomePageState.shared.homeCurrentFolderItem.parent
                guard let parentItem = RetroRomFileManager.shared.folderItem(key: parent) else {
                    return
                }
                let meta: RetroRomFileBrowserMeta
                if RetroRomHomePageState.shared.homeBrowserType == .icon {
                    meta = .iconView(organize: .byFolder, folderKey: parentItem.key)
                } else if RetroRomHomePageState.shared.homeBrowserType == .list {
                    meta = .listView(organize: .byFolder, folderKey: parentItem.key)
                } else {
                    return
                }
                parentFileBrowser = getFileBrowser(meta: meta)
                view.addSubview(parentFileBrowser!)
                do {
                    let x = viewSafeInsets.left
                    let y = viewSafeInsets.top
                    let w = view.width - viewSafeInsets.left - viewSafeInsets.right
                    let h = view.height - viewSafeInsets.top - viewSafeInsets.bottom
                    parentFileBrowser?.frame = CGRect(x: x - w, y: y, width: w, height: h)
                }
                Vibration.selection.vibrate()
                break
            case .changed:
                guard let parentFileBrowser = parentFileBrowser, translation.x > 0 else {
                    return
                }
                if translation.x > 0 {
                    fileBrowser.transform = CGAffineTransform(translationX: translation.x, y: 0)
                    parentFileBrowser.transform = CGAffineTransform(translationX: translation.x, y: 0)
                }
            case .ended, .cancelled:
                guard let parentFileBrowser = parentFileBrowser else {
                    return
                }

                if translation.x > view.width * 0.5 {
                    let duration = (view.width - translation.x) / view.width * 0.3

                    UIView.animate(withDuration: duration) {
                        self.fileBrowser.transform = CGAffineTransform(translationX: self.view.width, y: 0)
                        parentFileBrowser.transform = CGAffineTransform(translationX: self.view.width, y: 0)
                    } completion: { [self] _ in
                        fileBrowser.removeFromSuperview()

                        parentFileBrowser.transform = .identity
                        fileBrowser = parentFileBrowser
                        do {
                            let x = viewSafeInsets.left
                            let y = viewSafeInsets.top
                            let w = view.width - viewSafeInsets.left - viewSafeInsets.right
                            let h = view.height - viewSafeInsets.top - viewSafeInsets.bottom
                            fileBrowser.frame = CGRect(x: x, y: y, width: w, height: h)
                        }

                        let parent = RetroRomHomePageState.shared.homeCurrentFolderItem.parent
                        guard let parentItem = RetroRomFileManager.shared.folderItem(key: parent) else {
                            return
                        }
                        RetroRomHomePageState.shared.homeCurrentFolder = parentItem.key
                        self.titleView.updatePageTitle()
                        self.navigationController?.navigationBar.setNeedsLayout()
                        self.parentFileBrowser = nil
                    }
                } else {
                    let duration = translation.x / view.width * 0.3
                    UIView.animate(withDuration: duration) {
                        self.fileBrowser.transform = .identity
                        parentFileBrowser.transform = .identity
                    } completion: { _ in
                        parentFileBrowser.removeFromSuperview()
                        self.parentFileBrowser = nil
                    }
                }
        default:
            break
        }
    }

    @objc
    private func languageChanged() {
        emptyTipView?.updateTipText()
        fileBrowser.languageChanged()
    }

    @objc
    private func addAction() {
        Vibration.selection.vibrate()

        guard RetroArchX.shared().initialized else { return }

        switch fileBrowser.meta {
            case .iconView(organize: let organize, folderKey: let folderKey):
                pendingRootParent = organize == .byFolder ? folderKey : "root"
            case .listView(organize: let organize, folderKey: let folderKey):
                pendingRootParent = organize == .byFolder ? folderKey : "root"
            case .treeView:
                pendingRootParent = "root"
        }

        showGameImportSelector()
    }

    @objc
    private func settingsAction() {
        Vibration.selection.vibrate()

        let controller = AppSettingViewController()
        let naviController = UINavigationController(rootViewController: controller)
        present(naviController, animated: true)
    }

    @objc
    private func checkRetroItemIsEmpty() {
        emptyTipView?.removeFromSuperview()

        if fileBrowser.couldShowEmptyTip {
            let tipView = RetroRomEmptyTipView()
            view.addSubview(tipView)
            tipView.snp.makeConstraints { make in
                make.leading.equalTo(view.safeAreaLayoutGuide.snp.leading)
                make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
                make.trailing.equalTo(view.safeAreaLayoutGuide.snp.trailing)
                make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom)
            }
            emptyTipView = tipView
        } else {
            emptyTipView = nil
        }
    }

    @objc
    private func retroArchReadyNotification(_ notif: Notification) {
#if DEBUG
        trace("retroArchReadyNotification")
#endif
        NotificationCenter.default.removeObserver(self, name: .RetroArchXReady, object: nil)
        updateFileBrowser()
    }

    @objc
    private func retroFileImported(_ notif: Notification) {
        if let keys = notif.object as? [String] {
            fileBrowser.fileItemImported(keys)
        }
    }

    @objc
    private func retroFolderImported(_ notif: Notification) {
        if let folderKey = notif.object as? String, let info = notif.userInfo as? [String: [String]], let fileKeys = info["fileKeys"]  {
            fileBrowser.folderItemImported(folderKey: folderKey, itemKeys: fileKeys)
        }
    }

    @objc
    private func fileTagColorChanged(_ notif: Notification) {
        guard let tagId = notif.object as? Int else {
            return
        }
        fileBrowser.fileTagColorChanged(tagId: tagId)
    }

    @objc
    private func configAction(_ sender: UIBarButtonItem) {
        Vibration.selection.vibrate()

        guard RetroArchX.shared().initialized else { return }

        fileBrowser.resignKeyboardFocus()

        let configView = RetroRomFileBrowserConfigView(barButtonItem: sender)
        configView.install()
        self.configView = configView
    }
}

extension HomePageViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let rootParent = pendingRootParent ?? RetroRomHomePageState.shared.homeCurrentFolder
        RetroRomFileManager.shared.importGame(urls: urls, rootParent: rootParent)

        pendingRootParent = nil
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        pendingRootParent = nil
    }
}

#if DEBUG
private final class MainThreadStallMonitor {
    private let threshold: TimeInterval
    private let interval: TimeInterval
    private let queue = DispatchQueue(label: "com.retrogo.main.thread.stall", qos: .background)
    private var timer: DispatchSourceTimer?
    private var isRunning = false

    init(threshold: TimeInterval, interval: TimeInterval) {
        self.threshold = threshold
        self.interval = interval
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.ping()
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
        isRunning = false
    }

    private func ping() {
        let sent = CFAbsoluteTimeGetCurrent()
        DispatchQueue.main.async {
            let delay = CFAbsoluteTimeGetCurrent() - sent
            if delay > self.threshold {
                let logMessage = String(format: "[Stall] main thread blocked %.3fs", delay)
                NSLog(logMessage)
            }
        }
    }
}
#endif

