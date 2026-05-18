//
//  AppStorePurchaseViewController.swift
//  RetroGo
//
//  Created by haharsw on 2026/5/10.
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
import SnapKit
import ObjcHelper
import SafariServices

final class AppStorePurchaseViewController: UIViewController {
    private let gamePauseToken = RetroArchGamePauseToken()

    // MARK: UI
    let scrollView    = UIScrollView()
    let contentStack  = UIStackView()
    fileprivate let heroHeaderView = HeroHeaderView()
    fileprivate let planSectionContainer = UIView()
    fileprivate lazy var planSectionView = PlanSectionView(holder: self)
    private lazy var benefitSectionView = BenefitSectionView(frame: .zero)
    private lazy var bottomSectionView = BottomSectionView(frame: .zero)
    fileprivate var didInstallPurchaseSections = false
    fileprivate var didLayoutPurchaseSections = false
    fileprivate var planSectionHeightConstraint: Constraint?

    // Restore bar button
    private(set) lazy var restoreBarButton = { [unowned self] () -> UIBarButtonItem in
        let item = UIBarButtonItem(title: Bundle.localizedString(forKey: "iap_restore"), style: .plain, target: self, action: #selector(restoreAction))
        item.tintColor = .mainColor
        return item
    }()
    let restoreIndicator = UIActivityIndicatorView(style: .medium)
    private(set) lazy var restoreIndicatorBarButton = { [unowned self] () -> UIBarButtonItem in
        UIBarButtonItem(customView: restoreIndicator)
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor       = .systemGroupedBackground
        navigationItem.hidesBackButton = true
        navigationItem.title       = ""

        navigationItem.rightBarButtonItem = restoreBarButton
        navigationItem.leftBarButtonItem  = UIBarButtonItem(
            image: UIImage(systemName: "xmark.circle"),
            style: .plain, target: self, action: #selector(closeAction)
        )
        navigationItem.leftBarButtonItem?.tintColor = .mainColor

        configUI()

        AppStorePurchaseManager.shared.ensureBootstrapped()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        guard didInstallPurchaseSections else { return }
        if !didLayoutPurchaseSections {
            didLayoutPurchaseSections = true
            planSectionView.reloadState()
        } else {
            updatePlanSectionHeight(planSectionView)
        }
    }
}

// MARK: - Setup
private extension AppStorePurchaseViewController {
    func configUI() {
        view.addSubview(scrollView)
        scrollView.alwaysBounceVertical = true
        scrollView.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide)
        }

        contentStack.axis      = .vertical
        contentStack.spacing   = 40
        contentStack.alignment = .fill

        scrollView.addSubview(contentStack)
        contentStack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 16, left: 16, bottom: 24, right: 16))
            make.width.equalTo(scrollView.snp.width).offset(-32)
        }

        contentStack.addArrangedSubview(heroHeaderView)
        heroHeaderView.snp.makeConstraints { make in make.height.greaterThanOrEqualTo(150) }

        contentStack.addArrangedSubview(planSectionContainer)
        planSectionContainer.isHidden = true
        planSectionContainer.snp.makeConstraints { make in
            planSectionHeightConstraint = make.height.greaterThanOrEqualTo(1).constraint
        }
        planSectionHeightConstraint?.deactivate()

        contentStack.addArrangedSubview(benefitSectionView)
        benefitSectionView.snp.makeConstraints { make in make.height.greaterThanOrEqualTo(200) }

        contentStack.addArrangedSubview(bottomSectionView)
        bottomSectionView.snp.makeConstraints { make in make.height.greaterThanOrEqualTo(100) }

        didInstallPurchaseSections = true
    }
}

fileprivate extension AppStorePurchaseViewController {
    func setPlanSection(_ section: PlanSectionView, visible: Bool) {
        if visible {
            guard resolvedPlanSectionWidth() > 0 else { return }
            planSectionContainer.isHidden = false
            section.isHidden = false
            if section.superview == nil {
                planSectionContainer.addSubview(section)
                section.snp.makeConstraints { make in
                    make.edges.equalToSuperview()
                }
            }
            updatePlanSectionHeight(section)
        } else {
            section.removeFromSuperview()
            planSectionHeightConstraint?.deactivate()
            planSectionContainer.isHidden = true
        }
    }

    func updatePlanSectionHeight(_ section: PlanSectionView) {
        guard section.superview === planSectionContainer, !planSectionContainer.isHidden else { return }

        let width = resolvedPlanSectionWidth()
        guard width > 0 else { return }

        let fittingSize = CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
        let height = section.systemLayoutSizeFitting(
            fittingSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height

        planSectionHeightConstraint?.activate()
        planSectionHeightConstraint?.update(offset: max(ceil(height), 1))
    }

    func resolvedPlanSectionWidth() -> CGFloat {
        let containerWidth = planSectionContainer.bounds.width
        if containerWidth > 0 {
            return containerWidth
        }

        let stackWidth = contentStack.bounds.width
        if stackWidth > 0 {
            return stackWidth
        }

        let viewWidth = view.bounds.width - 32
        return max(viewWidth, 0)
    }
}

// MARK: - Actions
private extension AppStorePurchaseViewController {
    @objc func closeAction() {
        Vibration.selection.vibrate()
        if let navigationController, navigationController.viewControllers.count > 1 {
            navigationController.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    @objc func restoreAction() {
        let purchaseManager = AppStorePurchaseManager.shared
        guard !purchaseManager.flowState.isLoading else { return }
        Vibration.selection.vibrate()

        if purchaseManager.activeProEntitlement != nil {
            let alert = UIAlertController(
                title: Bundle.localizedString(forKey: "iap_retrogo_pro_is_active"),
                message: Bundle.localizedString(forKey: "iap_retrogo_pro_active_alert_text"),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: Bundle.localizedString(forKey: "ok"), style: .default))
            present(alert, animated: true)
            return
        }

        Task { @MainActor in
            do {
                try await purchaseManager.restorePurchases()
                AppToastManager.shared.toast(Bundle.localizedString(forKey: "iap_purchases_restored"), context: .ui, level: .success)
            } catch {
                AppToastManager.shared.toast(error.localizedDescription, context: .ui, level: .warning)
            }
            planSectionView.reloadState()
        }
    }
}

// MARK: - HeroHeaderView

private final class HeroHeaderView: UIView {
    let heroCrownImageView = UIImageView(image: UIImage(systemName: "crown.fill"))
    let heroCheckContainer = UIView()
    let heroCheckImageView = UIImageView(image: UIImage(systemName: "checkmark"))
    let heroTitleLabel = UILabel()
    let heroSubtitleLabel = UILabel()
    let heroDetailLabel = UILabel()
    private(set) var heroGradientLayer: CAGradientLayer?

    override init(frame: CGRect) {
        super.init(frame: frame)

        configUI()

        layer.cornerRadius = 20
        clipsToBounds      = true
        isUserInteractionEnabled = true

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tapGesture)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateGradientFrames()
    }

    func updateHeroState() {
        let purchaseManager = AppStorePurchaseManager.shared
        guard let entitlement = purchaseManager.activeProEntitlement else {
            heroCheckContainer.isHidden = true
            heroDetailLabel.isHidden = true
            heroTitleLabel.text = Bundle.localizedString(forKey: "iap_main_title")
            heroSubtitleLabel.text = Bundle.localizedString(forKey: "iap_hero_subtitle")
            heroCrownImageView.tintColor = UIColor(hex: 0xFFD700, alpha: 1.0)
            return
        }

        heroCheckContainer.isHidden = false
        heroDetailLabel.isHidden = false
        heroCrownImageView.tintColor = UIColor(hex: 0xFFD700, alpha: 1.0)

        if entitlement.isInFreeTrial {
            heroTitleLabel.text = Bundle.localizedString(forKey: "iap_retrogo_pro_is_trial")
            heroSubtitleLabel.text = Bundle.localizedString(forKey: "iap_retrogo_pro_trial_thanks")
        } else {
            heroTitleLabel.text = Bundle.localizedString(forKey: "iap_retrogo_pro_is_active")
            heroSubtitleLabel.text = Bundle.localizedString(forKey: "iap_retrogo_pro_purchase_thanks")
        }

        if let text = heroDetailText(for: entitlement) {
            heroDetailLabel.isHidden = false
            heroDetailLabel.text = text
        } else {
            heroDetailLabel.isHidden = true
        }
    }

    private func heroDetailText(for entitlement: AppStoreProEntitlementInfo) -> String? {
        if entitlement.isLifetime {
            return nil
        }

        let planText = entitlement.displayName
        guard let expirationDate = entitlement.expirationDate else {
            return planText
        }

        let dateText = getLocalizedDateString(from: expirationDate)
        if entitlement.isInFreeTrial {
            let formatter = Bundle.localizedString(forKey: "iap_retrogo_trial_ends_formatter")
            return String(format: formatter, planText, dateText)
        } else {
            let formatter = Bundle.localizedString(forKey: "iap_retrogo_active_until_formatter")
            return String(format: formatter, planText, dateText)
        }
    }

    private func getLocalizedDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = .current
        formatter.calendar = Calendar(identifier: .gregorian)

        switch Bundle.currentLanguage() {
        case let language where language.hasPrefix("zh"):
            formatter.locale = Locale(identifier: "zh_Hans_CN")
            formatter.dateFormat = "yyyy年M月d日"

        case let language where language.hasPrefix("en"):
            formatter.locale = Locale(identifier: "en_US")
            formatter.dateStyle = .medium
            formatter.timeStyle = .none

        default:
            formatter.locale = .current
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
        }

        return formatter.string(from: date)
    }

    private func updateGradientFrames() {
        if let layer = heroGradientLayer {
            layer.frame = bounds
        } else if bounds.size != .zero {
            let layer        = CAGradientLayer()
            layer.colors     = [
                UIColor(hex: 0x5B3FE8, alpha: 1).cgColor,
                UIColor(hex: 0xA45CF5, alpha: 1).cgColor
            ]
            layer.startPoint = CGPoint(x: 0, y: 0)
            layer.endPoint   = CGPoint(x: 1, y: 1)
            layer.frame      = bounds
            self.layer.insertSublayer(layer, at: 0)
            heroGradientLayer = layer
        }
    }

    @objc
    private func handleTap(_ gesture: UITapGestureRecognizer) {
        Vibration.soft.vibrate()
        playRipple(at: gesture.location(in: self))
    }

    private func playRipple(at point: CGPoint) {
        guard bounds.width > 0, bounds.height > 0 else { return }

        let diameter = max(bounds.width, bounds.height) * 1.35
        let rippleLayer = CAShapeLayer()
        rippleLayer.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        rippleLayer.position = point
        rippleLayer.path = UIBezierPath(ovalIn: rippleLayer.bounds).cgPath
        rippleLayer.fillColor = UIColor.white.withAlphaComponent(0.20).cgColor
        rippleLayer.opacity = 0
        rippleLayer.transform = CATransform3DMakeScale(0.02, 0.02, 1)
        layer.addSublayer(rippleLayer)

        let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
        scaleAnimation.fromValue = 0.02
        scaleAnimation.toValue = 1.0

        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = 0.85
        opacityAnimation.toValue = 0.0

        let animationGroup = CAAnimationGroup()
        animationGroup.animations = [scaleAnimation, opacityAnimation]
        animationGroup.duration = 0.48
        animationGroup.timingFunction = CAMediaTimingFunction(name: .easeOut)
        animationGroup.isRemovedOnCompletion = false
        animationGroup.fillMode = .forwards

        rippleLayer.add(animationGroup, forKey: "heroRipple")

        DispatchQueue.main.asyncAfter(deadline: .now() + animationGroup.duration) { [weak rippleLayer] in
            rippleLayer?.removeFromSuperlayer()
        }
    }

    private func configUI() {
        heroCrownImageView.tintColor    = UIColor(hex: 0xFFD700, alpha: 1.0)
        heroCrownImageView.contentMode  = .scaleAspectFit
        addSubview(heroCrownImageView)
        heroCrownImageView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().offset(16)
            make.size.equalTo(42)
        }

        heroCheckContainer.backgroundColor = UIColor(hex: 0x2ECC71, alpha: 1.0)
        heroCheckContainer.layer.cornerRadius = 10
        heroCheckContainer.layer.borderColor = UIColor.white.withAlphaComponent(0.85).cgColor
        heroCheckContainer.layer.borderWidth = 2
        heroCheckContainer.isHidden = true
        addSubview(heroCheckContainer)
        heroCheckContainer.snp.makeConstraints { make in
            make.centerX.equalTo(heroCrownImageView.snp.trailing).offset(-4)
            make.centerY.equalTo(heroCrownImageView.snp.top).offset(4)
            make.size.equalTo(20)
        }

        heroCheckImageView.tintColor = .white
        heroCheckImageView.contentMode = .scaleAspectFit
        heroCheckContainer.addSubview(heroCheckImageView)
        heroCheckImageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(11)
        }

        heroTitleLabel.text         = Bundle.localizedString(forKey: "iap_main_title")
        heroTitleLabel.font         = .roundedSystemFont(ofSize: 29, weight: .bold)
        heroTitleLabel.textColor    = .white
        heroTitleLabel.textAlignment = .center
        heroTitleLabel.adjustsFontSizeToFitWidth = true
        heroTitleLabel.minimumScaleFactor = 0.75
        addSubview(heroTitleLabel)
        heroTitleLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(heroCrownImageView.snp.bottom).offset(8)
            make.leading.trailing.equalToSuperview().inset(16)
        }

        heroSubtitleLabel.text          = Bundle.localizedString(forKey: "iap_hero_subtitle")
        heroSubtitleLabel.font          = .roundedSystemFont(ofSize: 16, weight: .semibold)
        heroSubtitleLabel.textColor     = UIColor.white.withAlphaComponent(0.84)
        heroSubtitleLabel.textAlignment = .center
        heroSubtitleLabel.numberOfLines = 2
        addSubview(heroSubtitleLabel)
        heroSubtitleLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(heroTitleLabel.snp.bottom).offset(8)
            make.leading.trailing.equalToSuperview().inset(20)
        }

        heroDetailLabel.font = .roundedSystemFont(ofSize: 14, weight: .bold)
        heroDetailLabel.textColor = UIColor.white.withAlphaComponent(0.92)
        heroDetailLabel.textAlignment = .center
        heroDetailLabel.numberOfLines = 2
        heroDetailLabel.isHidden = true
        addSubview(heroDetailLabel)
        heroDetailLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(heroSubtitleLabel.snp.bottom).offset(6)
            make.leading.trailing.equalToSuperview().inset(20)
            make.bottom.lessThanOrEqualToSuperview().offset(-20)
        }
    }
}

// MARK: - PlanSectionView

private final class GradientButtonBackgroundView: UIView {
    private let gradientLayer = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)

        layer.cornerRadius = 16
        clipsToBounds = true

        gradientLayer.colors = [
            UIColor(hex: 0x6B48FF, alpha: 1).cgColor,
            UIColor(hex: 0xAB5CF7, alpha: 1).cgColor
        ]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        layer.insertSublayer(gradientLayer, at: 0)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = bounds
        CATransaction.commit()

        if gradientLayer.superlayer == nil {
            layer.insertSublayer(gradientLayer, at: 0)
        }
    }
}

fileprivate final class PlanSectionView: UIStackView {
    private let purchaseManager = AppStorePurchaseManager.shared

    private var productInfoByKind: [AppStoreProductKind: AppStoreProductInfo] = [:]
    private var selectedKind: AppStoreProductKind?

    private let planTitleRow      = UIView()
    private let subscriptionRow   = UIStackView()       // Monthly + Yearly
    private lazy var monthlyCard  = PlanCardView(kind: .proMonthly)
    private lazy var yearlyCard   = PlanCardView(kind: .proYearly)
    private lazy var lifetimeCard = PlanCardView(kind: .proLifetime)

    private let subscribeWrapper = UIView()
    private let subscribeInner   = GradientButtonBackgroundView()
    private let subscribeButton  = UIButton(type: .custom)

    private let tipLabel         = UILabel()
    private let emptyStateLabel  = UILabel()

    private weak var holder: AppStorePurchaseViewController?
    private var refreshTask: Task<Void, Never>?

    init(holder: AppStorePurchaseViewController) {
        self.holder = holder
        super.init(frame: .zero)

        axis      = .vertical
        spacing   = 20
        alignment = .fill

        configUI()

        NotificationCenter.default.addObserver(self, selector: #selector(purchaseStateDidChange), name: .appStorePurchaseStateDidChange, object: nil)

        refreshProducts(forceReload: true)
        renderPlans()
        updateUIFromState()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        refreshTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    private func renderPlans() {
        guard let holder else { return }

        let isPro = purchaseManager.activeProEntitlement != nil
        let showsPlanSkeleton = shouldShowPlanSkeleton()

        holder.heroHeaderView.updateHeroState()

        if isPro {
            if holder.didInstallPurchaseSections {
                holder.setPlanSection(self, visible: false)
            } else {
                isHidden = false
            }
            return
        }

        if holder.didInstallPurchaseSections {
            holder.setPlanSection(self, visible: true)
        } else {
            isHidden = false
        }

        planTitleRow.isHidden = false
        monthlyCard.isHidden  = !showsPlanSkeleton && productInfoByKind[.proMonthly]  == nil
        yearlyCard.isHidden   = !showsPlanSkeleton && productInfoByKind[.proYearly]   == nil
        lifetimeCard.isHidden = !showsPlanSkeleton && productInfoByKind[.proLifetime] == nil
        subscribeWrapper.isHidden = false
        tipLabel.isHidden = false

        // Hide the subscription row entirely if both monthly and yearly are absent
        subscriptionRow.isHidden = monthlyCard.isHidden && yearlyCard.isHidden

        let yearlySaving = yearlySavingPercentText()

        monthlyCard.apply(info: productInfoByKind[.proMonthly],  selected: selectedKind == .proMonthly, savingText: nil)
        yearlyCard.apply(info: productInfoByKind[.proYearly],   selected: selectedKind == .proYearly, savingText: yearlySaving)
        lifetimeCard.apply(info: productInfoByKind[.proLifetime], selected: selectedKind == .proLifetime, savingText: Bundle.localizedString(forKey: "iap_lifetime_tip"))
        holder.updatePlanSectionHeight(self)
    }

    func updateUIFromState() {
        guard let holder else { return }

        let flowState      = purchaseManager.flowState
        let bootstrapState = purchaseManager.bootstrapState
        let loading        = flowState.isLoading
        let showsPlanSkeleton = shouldShowPlanSkeleton()
        let isPro = purchaseManager.activeProEntitlement != nil

        if productInfoByKind.isEmpty && !showsPlanSkeleton && !isPro {
            emptyStateLabel.isHidden = false
            switch bootstrapState {
            case .loading:
                emptyStateLabel.text = Bundle.localizedString(forKey: "iap_loading_products")
            case .failed(let message):
                let formatter = Bundle.localizedString(forKey: "iap_failed_load_products")
                emptyStateLabel.text = String(format: formatter, message)
            default:
                emptyStateLabel.text = Bundle.localizedString(forKey: "iap_no_subscription_products")
            }
        } else {
            emptyStateLabel.isHidden = true
        }

        [monthlyCard, yearlyCard, lifetimeCard].forEach { card in
            card.isUserInteractionEnabled = !loading
            card.alpha = loading ? 0.85 : 1.0
        }

        if flowState.isRestoring {
            holder.restoreIndicator.color = .mainColor
            holder.restoreIndicator.startAnimating()
            holder.navigationItem.rightBarButtonItem = holder.restoreIndicatorBarButton
        } else {
            holder.restoreIndicator.stopAnimating()
            holder.navigationItem.rightBarButtonItem = holder.restoreBarButton
            holder.restoreBarButton.isEnabled        = !flowState.isPurchasing
        }

        var subscribeConfig = subscribeButton.configuration ?? UIButton.Configuration.plain()
        subscribeConfig.showsActivityIndicator = flowState.isPurchasing
        subscribeButton.configuration = subscribeConfig
        subscribeButton.isEnabled     = !isPro && !flowState.isLoading && selectedKind != nil
        subscribeWrapper.alpha        = subscribeButton.isEnabled ? 1.0 : 0.55

        if let selectedKind = selectedKind, let selectedInfo = productInfoByKind[selectedKind] {
            subscribeConfig.title = purchaseButtonTitle(for: selectedInfo)
            subscribeButton.configuration = subscribeConfig
            if selectedInfo.hasFreeTrial, selectedInfo.isEligibleForIntroOffer, let text = selectedInfo.freeTrialDisplayText {
                tipLabel.text = String(format: Bundle.localizedString(forKey: "iap_yearly_trial_desc"), text)
            } else {
                tipLabel.text = cycleDescription(for: selectedKind)
            }
        } else {
            subscribeConfig.title = Bundle.localizedString(forKey: "iap_loading")
            subscribeButton.configuration = subscribeConfig
            tipLabel.text = nil
        }
        holder.updatePlanSectionHeight(self)
    }

    func reloadState() {
        productInfoByKind = Dictionary(uniqueKeysWithValues: purchaseManager.productInfos().map { ($0.kind, $0) })
        chooseDefaultSelectedPlanIfNeeded()
        renderPlans()
        updateUIFromState()
    }

    private func refreshProducts(forceReload: Bool) {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }

            await self.purchaseManager.refreshEntitlements()
            guard !Task.isCancelled else { return }

            self.productInfoByKind = Dictionary(uniqueKeysWithValues: self.purchaseManager.productInfos().map { ($0.kind, $0) })
            self.renderPlans()
            self.updateUIFromState()

            if forceReload || self.purchaseManager.productInfos().isEmpty {
                self.renderPlans()
                self.updateUIFromState()

                do {
                    try await self.purchaseManager.loadProducts()
                    await self.purchaseManager.refreshEntitlements()
                } catch {
                    AppToastManager.shared.toast(error.localizedDescription, context: .ui, level: .warning)
                }
            }

            guard !Task.isCancelled else { return }

            self.productInfoByKind = Dictionary(uniqueKeysWithValues: self.purchaseManager.productInfos().map { ($0.kind, $0) })
            self.chooseDefaultSelectedPlanIfNeeded()
            self.renderPlans()
            self.updateUIFromState()
        }
    }

    private func purchaseButtonTitle(for info: AppStoreProductInfo) -> String {
        switch info.kind {
        case .proLifetime:
            return "\(Bundle.localizedString(forKey: "iap_unlock_lifetime")) · \(info.displayPrice)"
        case .proMonthly:
            if info.hasFreeTrial, info.isEligibleForIntroOffer, let trial = info.freeTrialDisplayText {
                return "\(Bundle.localizedString(forKey: "start")) \(trial)"
            }
            return "\(Bundle.localizedString(forKey: "iap_subscribe_now")) · \(info.displayPrice) / \(Bundle.localizedString(forKey: "month"))"
        case .proYearly:
            if info.hasFreeTrial, info.isEligibleForIntroOffer, let trial = info.freeTrialDisplayText {
                return "\(Bundle.localizedString(forKey: "start")) \(trial)"
            }
            return "\(Bundle.localizedString(forKey: "iap_subscribe_now")) · \(info.displayPrice) / \(Bundle.localizedString(forKey: "year"))"
        }
    }

    private func cycleDescription(for kind: AppStoreProductKind) -> String {
        switch kind {
        case .proMonthly:  return Bundle.localizedString(forKey: "iap_monthly_desc")
        case .proYearly:   return Bundle.localizedString(forKey: "iap_yearly_desc")
        case .proLifetime: return Bundle.localizedString(forKey: "iap_lifetime_desc")
        }
    }

    private func chooseDefaultSelectedPlanIfNeeded() {
        if let selectedKind, productInfoByKind[selectedKind] != nil { return }
        if      productInfoByKind[.proYearly]   != nil { selectedKind = .proYearly   }
        else if productInfoByKind[.proMonthly]  != nil { selectedKind = .proMonthly  }
        else if productInfoByKind[.proLifetime] != nil { selectedKind = .proLifetime }
        else                                           { selectedKind = nil          }
    }

    private func shouldShowPlanSkeleton() -> Bool {
        guard productInfoByKind.isEmpty else { return false }
        switch purchaseManager.bootstrapState {
        case .idle, .loading:
            return true
        case .ready, .failed:
            return false
        }
    }

    private func yearlySavingPercentText() -> String? {
        guard let monthly = productInfoByKind[.proMonthly],
              let yearly = productInfoByKind[.proYearly] else {
            return nil
        }

        let fullYearPrice = monthly.price * Decimal(12)
        guard fullYearPrice > yearly.price else {
            return nil
        }

        let saved = fullYearPrice - yearly.price
        let ratio = saved / fullYearPrice

        let percent = NSDecimalNumber(decimal: ratio * Decimal(100)).doubleValue
        let roundedPercent = Int(percent.rounded())

        guard roundedPercent > 0 else {
            return nil
        }

        return "\(Bundle.localizedString(forKey: "iap_save")) \(roundedPercent)%"
    }

    private func configUI() {

        let icon          = UIImageView(image: UIImage(systemName: "creditcard.fill"))
        icon.tintColor    = UIColor(hex: 0x8B5CF6, alpha: 1.0)
        icon.contentMode  = .scaleAspectFit
        icon.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        icon.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let planTitleLabel          = UILabel()
        planTitleLabel.text         = Bundle.localizedString(forKey: "iap_chooseplan")
        planTitleLabel.font         = UIFont.roundedSystemFont(ofSize: 22, weight: .semibold)
        planTitleLabel.numberOfLines = 1
        planTitleLabel.adjustsFontSizeToFitWidth = true
        planTitleLabel.minimumScaleFactor = 0.75
        planTitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        planTitleRow.addSubview(icon)
        planTitleRow.addSubview(planTitleLabel)
        addArrangedSubview(planTitleRow)
        planTitleRow.snp.makeConstraints { make in
            make.height.greaterThanOrEqualTo(28).priority(.high)
        }

        icon.snp.makeConstraints { make in
            make.leading.equalToSuperview()
            make.centerY.equalToSuperview()
            make.size.equalTo(22)
        }

        planTitleLabel.snp.makeConstraints { make in
            make.leading.equalTo(icon.snp.trailing).offset(6).priority(.high)
            make.centerY.equalToSuperview()
            make.trailing.lessThanOrEqualToSuperview().priority(.high)
        }

        // Row 1: Monthly + Yearly side by side
        subscriptionRow.axis         = .horizontal
        subscriptionRow.spacing      = 10
        subscriptionRow.distribution = .fillEqually
        subscriptionRow.addArrangedSubview(monthlyCard)
        subscriptionRow.addArrangedSubview(yearlyCard)
        addArrangedSubview(subscriptionRow)
        subscriptionRow.snp.makeConstraints { make in make.height.equalTo(90) }

        monthlyCard.onTap = { [weak self] kind in self?.selectPlan(kind: kind) }
        yearlyCard.onTap  = { [weak self] kind in self?.selectPlan(kind: kind) }

        // Row 2: Lifetime full-width
        addArrangedSubview(lifetimeCard)
        lifetimeCard.snp.makeConstraints { make in make.height.equalTo(90) }
        lifetimeCard.onTap = { [weak self] kind in self?.selectPlan(kind: kind) }

        // Subscribe button
        subscribeWrapper.layer.shadowColor   = UIColor(hex: 0x6B48FF, alpha: 1).cgColor
        subscribeWrapper.layer.shadowOffset  = CGSize(width: 0, height: 6)
        subscribeWrapper.layer.shadowRadius  = 14
        subscribeWrapper.layer.shadowOpacity = 0.45

        subscribeWrapper.addSubview(subscribeInner)
        subscribeInner.snp.makeConstraints { make in make.edges.equalToSuperview() }

        var subscribeConfig = UIButton.Configuration.plain()
        subscribeConfig.baseForegroundColor   = .white
        subscribeConfig.contentInsets         = NSDirectionalEdgeInsets(top: 10, leading: 18, bottom: 10, trailing: 18)
        subscribeConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var result = incoming
            result.font = .roundedSystemFont(ofSize: 22, weight: .semibold)
            return result
        }
        subscribeButton.configuration = subscribeConfig
        subscribeButton.addTarget(self, action: #selector(subscribeAction), for: .touchUpInside)
        subscribeButton.addTarget(self, action: #selector(subscribeButtonPressed),  for: .touchDown)
        subscribeButton.addTarget(self, action: #selector(subscribeButtonReleased), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        subscribeInner.addSubview(subscribeButton)
        subscribeButton.snp.makeConstraints { make in make.edges.equalToSuperview() }

        addArrangedSubview(subscribeWrapper)
        subscribeWrapper.snp.makeConstraints { make in make.height.equalTo(54) }

        tipLabel.textAlignment  = .center
        tipLabel.numberOfLines  = 0
        tipLabel.font           = .roundedSystemFont(ofSize: 14, weight: .medium)
        tipLabel.textColor      = .secondaryLabel
        addArrangedSubview(tipLabel)

        emptyStateLabel.textAlignment  = .center
        emptyStateLabel.numberOfLines  = 0
        emptyStateLabel.font           = .roundedSystemFont(ofSize: 14, weight: .regular)
        emptyStateLabel.textColor      = .secondaryLabel
        emptyStateLabel.isHidden       = true
        addArrangedSubview(emptyStateLabel)
    }

    private func selectPlan(kind: AppStoreProductKind) {
        guard !purchaseManager.flowState.isLoading else { return }
        guard productInfoByKind[kind] != nil        else { return }
        Vibration.selection.vibrate()
        selectedKind = kind
        renderPlans()
        updateUIFromState()
    }

    @objc
    private func purchaseStateDidChange() {
        reloadState()
    }

    @objc
    private func subscribeAction() {
        guard !purchaseManager.flowState.isLoading else { return }
        guard let selectedKind = selectedKind else {
            AppToastManager.shared.toast(Bundle.localizedString(forKey: "iap_select_a_plan"), context: .ui, level: .warning)
            return
        }
        if purchaseManager.isPurchased(selectedKind) {
            AppToastManager.shared.toast(Bundle.localizedString(forKey: "iap_plan_already_unlocked"), context: .ui, level: .info)
            return
        }
        Vibration.selection.vibrate()
        Task { @MainActor in
            do {
                let result = try await purchaseManager.purchase(selectedKind)
                switch result {
                case .success:
                    AppToastManager.shared.toast(Bundle.localizedString(forKey: "iap_purchase_successful"), context: .ui, level: .success)
                case .pending:
                    AppToastManager.shared.toast(Bundle.localizedString(forKey: "iap_purchase_pending_approval"), context: .ui, level: .info)
                case .userCancelled:
                    AppToastManager.shared.toast(Bundle.localizedString(forKey: "iap_purchase_cancelled"), context: .ui, level: .warning)
                }
            } catch {
                AppToastManager.shared.toast(error.localizedDescription, context: .ui, level: .error)
            }
            productInfoByKind = Dictionary(uniqueKeysWithValues: purchaseManager.productInfos().map { ($0.kind, $0) })
            chooseDefaultSelectedPlanIfNeeded()
            renderPlans()
            updateUIFromState()
        }
    }

    @objc
    private func subscribeButtonPressed() {
        UIView.animate(withDuration: 0.1) {
            self.subscribeWrapper.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
        }
    }

    @objc
    private func subscribeButtonReleased() {
        UIView.animate(withDuration: 0.15, delay: 0, options: .allowUserInteraction) {
            self.subscribeWrapper.transform = .identity
        }
    }
}

// MARK: - BenefitSectionView

private final class BenefitSectionView: UIStackView {
    private let benefitsTitleLabel = UILabel()
    private let benefitsStack      = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        axis      = .vertical
        spacing   = 20
        alignment = .fill

        configUI()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configUI() {
        let titleRow = UIStackView()
        titleRow.axis      = .horizontal
        titleRow.spacing   = 6
        titleRow.alignment = .center

        let sparklesIcon          = UIImageView(image: UIImage(systemName: "sparkles"))
        sparklesIcon.tintColor    = UIColor(hex: 0xFFD700, alpha: 1.0)
        sparklesIcon.contentMode  = .scaleAspectFit
        sparklesIcon.snp.makeConstraints { make in make.size.equalTo(22) }

        benefitsTitleLabel.text = Bundle.localizedString(forKey: "iap_probenefits")
        benefitsTitleLabel.font = UIFont.roundedSystemFont(ofSize: 22, weight: .semibold)

        titleRow.addArrangedSubview(sparklesIcon)
        titleRow.addArrangedSubview(benefitsTitleLabel)
        addArrangedSubview(titleRow)

        benefitsStack.axis         = .vertical
        benefitsStack.spacing      = 12
        benefitsStack.distribution = .fill
        addArrangedSubview(benefitsStack)

        let benefits: [(String, UIColor)] = [
            (Bundle.localizedString(forKey: "iap_probenefit1"), UIColor(hex: 0x2ECC71, alpha: 1.0)),
            (Bundle.localizedString(forKey: "iap_probenefit2"), UIColor(hex: 0xF1C40F, alpha: 1.0)),
            (Bundle.localizedString(forKey: "iap_probenefit3"), UIColor(hex: 0xE74C3C, alpha: 1.0)),
            (Bundle.localizedString(forKey: "iap_probenefit4"), UIColor(hex: 0x3498D8, alpha: 1.0)),
            (Bundle.localizedString(forKey: "iap_probenefit5"), UIColor(hex: 0x9B59B6, alpha: 1.0)),
        ]
        benefits.forEach { benefitsStack.addArrangedSubview(BenefitRowView(text: $0.0, dotColor: $0.1)) }
    }
}

// MARK: - BottomSectionView

private final class BottomSectionView: UIStackView {
    private let legalTextLabel     = LinkTextView()
    private let bottomButtonsStack = UIStackView()
    private let policyButton       = UIButton(type: .system)
    private let termsButton        = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)

        axis      = .vertical
        spacing   = 20
        alignment = .fill

        configUI()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configUI() {
        let textAttributes: [NSAttributedString.Key: Any] = {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 5
            return [.foregroundColor: UIColor.secondaryLabel,
                    .font: UIFont.roundedSystemFont(ofSize: UIFont.smallSystemFontSize, weight: .regular),
                    .paragraphStyle: style]
        }()

        let text        = Bundle.localizedString(forKey: "iap_foottiptext")
        let manageText  = Bundle.localizedString(forKey: "iap_foottipmanage")
        let contactText = Bundle.localizedString(forKey: "iap_foottipcontact")
        legalTextLabel.backgroundColor = .clear
        legalTextLabel.tintColor       = .link
        legalTextLabel.attributedText  = NSAttributedString(string: text, attributes: textAttributes)
        legalTextLabel.addLinks([
            manageText:  "itms-apps://apps.apple.com/account/subscriptions",
            contactText: "mailto:askrsw@163.com?subject=RetroGo%20Feedback"
        ])
        addArrangedSubview(legalTextLabel)

        bottomButtonsStack.axis         = .horizontal
        bottomButtonsStack.spacing      = 0
        bottomButtonsStack.alignment    = .fill
        bottomButtonsStack.distribution = .fill
        addArrangedSubview(bottomButtonsStack)
        bottomButtonsStack.snp.makeConstraints { make in make.height.equalTo(40) }

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        configureBottomButton(policyButton, title: Bundle.localizedString(forKey: "iap_privacypolicy"))
        policyButton.addTarget(self, action: #selector(openPolicyAction), for: .touchUpInside)

        configureBottomButton(termsButton,  title: Bundle.localizedString(forKey: "iap_termsofuse"))
        termsButton.addTarget(self,  action: #selector(openTermsAction),  for: .touchUpInside)

        policyButton.snp.makeConstraints { make in make.width.greaterThanOrEqualTo(110) }
        termsButton.snp.makeConstraints  { make in make.width.greaterThanOrEqualTo(110) }

        bottomButtonsStack.addArrangedSubview(policyButton)
        bottomButtonsStack.addArrangedSubview(spacer)
        bottomButtonsStack.addArrangedSubview(termsButton)
    }

    private func configureBottomButton(_ button: UIButton, title: String) {
        var config = UIButton.Configuration.filled()
        config.cornerStyle         = .capsule
        config.baseBackgroundColor = .tertiarySystemGroupedBackground
        config.baseForegroundColor = .label
        config.title               = title
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var result = incoming
            result.font = .roundedSystemFont(ofSize: 14, weight: .medium)
            return result
        }
        button.configuration = config
    }

    @objc
    private func openPolicyAction() {
        guard let privacyPolicyURL = URL(string: "https://matrix4x4.com/retrogo/policy") else { return }
        guard let current = UIViewController.currentActive() else { return }
        Vibration.selection.vibrate()
        current.present(SFSafariViewController(url: privacyPolicyURL), animated: true)
    }

    @objc
    private func openTermsAction() {
        guard let termsURL = URL(string: "https://matrix4x4.com/retrogo/eula") else { return }
        guard let current = UIViewController.currentActive() else { return }
        Vibration.selection.vibrate()
        current.present(SFSafariViewController(url: termsURL), animated: true)
    }
}

// MARK: - PlanCardView

private final class PlanCardView: UIControl {
    let kind:  AppStoreProductKind
    var onTap: ((AppStoreProductKind) -> Void)?

    private let titleLabel  = UILabel()
    private let priceLabel  = UILabel()
    private let badgeLabel  = UILabel()   // "Flexible / Popular / Best"
    private let savingLabel = UILabel()
    private let borderView  = UIView()
    private let skeletonTitleView = UIView()
    private let skeletonPriceView = UIView()
    private var skeletonLayers: [CAGradientLayer] = []
    private var isSkeletonVisible = false

    init(kind: AppStoreProductKind) {
        self.kind  = kind
        super.init(frame: .zero)
        configUI()
        addTarget(self, action: #selector(handleTap), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: Apply

    func apply(info: AppStoreProductInfo?, selected: Bool, savingText: String?) {
        guard let info else {
            isUserInteractionEnabled = false
            alpha = 1
            showSkeleton()
            badgeLabel.isHidden = true
            savingLabel.text = nil
            savingLabel.isHidden = true
            borderView.layer.borderColor = UIColor.clear.cgColor
            borderView.layer.borderWidth = 0
            backgroundColor   = .tertiarySystemGroupedBackground
            return
        }

        isUserInteractionEnabled = true
        hideSkeleton()
        alpha = 1
        titleLabel.text = planTitle(for: info.kind)
        priceLabel.text = info.displayPrice

        if info.isPurchased {
            // "Current" badge in green
            badgeLabel.isHidden       = false
            badgeLabel.text           = Bundle.localizedString(forKey: "iap_current_plan")
            badgeLabel.textColor      = .systemGreen
            badgeLabel.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.14)
        } else {
            // Characteristic badge for each plan
            badgeLabel.isHidden        = false
            badgeLabel.text            = Bundle.localizedString(forKey: badgeKey(for: info.kind))
            badgeLabel.textColor       = .white
            badgeLabel.backgroundColor = badgeColor(for: info.kind)

            savingLabel.text = savingText
            savingLabel.isHidden = savingText == nil
        }

        if selected {
            borderView.layer.borderWidth = 2
            borderView.layer.borderColor = UIColor.systemOrange.cgColor
            backgroundColor   = UIColor.systemOrange.withAlphaComponent(0.10)
        } else {
            borderView.layer.borderWidth = 0
            borderView.layer.borderColor = UIColor.clear.cgColor
            backgroundColor   = .tertiarySystemGroupedBackground
        }
        bringSubviewToFront(badgeLabel)
    }

    // MARK: Private helpers

    private func planTitle(for kind: AppStoreProductKind) -> String {
        switch kind {
        case .proMonthly:  return Bundle.localizedString(forKey: "iap_monthly")
        case .proYearly:   return Bundle.localizedString(forKey: "iap_yearly")
        case .proLifetime: return Bundle.localizedString(forKey: "iap_lifetime")
        }
    }

    private func badgeKey(for kind: AppStoreProductKind) -> String {
        switch kind {
        case .proMonthly:  return "iap_monthly_badge"
        case .proYearly:   return "iap_yearly_badge"
        case .proLifetime: return "iap_lifetime_badge"
        }
    }

    private func badgeColor(for kind: AppStoreProductKind) -> UIColor {
        switch kind {
        case .proMonthly:  return UIColor(hex: 0x3B82F6, alpha: 1.0)   // blue  — flexible
        case .proYearly:   return UIColor(hex: 0xF59E0B, alpha: 1.0)   // amber — popular
        case .proLifetime: return UIColor(hex: 0x8B5CF6, alpha: 1.0)   // purple — best value
        }
    }

    // MARK: Layout

    private func configUI() {
        layer.cornerRadius = 18
        clipsToBounds      = false
        backgroundColor    = .tertiarySystemGroupedBackground

        borderView.isUserInteractionEnabled = false
        borderView.backgroundColor = .clear
        borderView.layer.cornerRadius = 18
        borderView.layer.borderColor = UIColor.clear.cgColor
        borderView.layer.borderWidth = 0

        [skeletonTitleView, skeletonPriceView].forEach { view in
            view.isHidden = true
            view.backgroundColor = UIColor.systemGray4.withAlphaComponent(0.45)
            view.layer.cornerRadius = 6
            view.clipsToBounds = true
            view.isUserInteractionEnabled = false
        }

        badgeLabel.font                = .roundedSystemFont(ofSize: 11, weight: .bold)
        badgeLabel.textAlignment       = .center
        badgeLabel.layer.cornerRadius  = 10
        badgeLabel.layer.masksToBounds = true
        badgeLabel.isHidden            = true
        badgeLabel.numberOfLines       = 1
        badgeLabel.adjustsFontSizeToFitWidth = true
        badgeLabel.minimumScaleFactor  = 0.75
        badgeLabel.transform           = CGAffineTransform(rotationAngle: .pi / 6)

        savingLabel.font = .roundedSystemFont(ofSize: 11, weight: .medium)
        savingLabel.textColor = .secondaryLabel
        savingLabel.numberOfLines = 1
        savingLabel.adjustsFontSizeToFitWidth = true
        savingLabel.minimumScaleFactor = 0.75
        savingLabel.isHidden = true

        addSubview(borderView)
        addSubview(titleLabel)
        addSubview(priceLabel)
        addSubview(badgeLabel)
        addSubview(savingLabel)
        addSubview(skeletonTitleView)
        addSubview(skeletonPriceView)

        borderView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        configLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateSkeletonLayerFrames()
    }

    private func configLayout() {
        titleLabel.font          = .roundedSystemFont(ofSize: 18, weight: .regular)
        titleLabel.textColor     = .secondaryLabel
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.75
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        priceLabel.font                      = .roundedSystemFont(ofSize: 30, weight: .heavy)
        priceLabel.textColor                 = .label
        priceLabel.adjustsFontSizeToFitWidth = true
        priceLabel.minimumScaleFactor        = 0.65
        priceLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        priceLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        savingLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        savingLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        titleLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(12).priority(.high)
            make.top.equalToSuperview().offset(12)
            make.trailing.lessThanOrEqualToSuperview().offset(-12).priority(.high)
        }

        badgeLabel.snp.makeConstraints { make in
            make.centerX.equalTo(self.snp.trailing).offset(-26)
            make.centerY.equalTo(self.snp.top).offset(18)
            make.height.equalTo(20)
            make.width.equalTo(70)
        }

        priceLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(12)
            make.bottom.equalToSuperview().offset(-12)
        }

        savingLabel.snp.makeConstraints { make in
            make.leading.equalTo(priceLabel.snp.trailing).offset(6).priority(.high)
            make.lastBaseline.equalTo(priceLabel.snp.lastBaseline)
            make.trailing.lessThanOrEqualToSuperview().offset(-12).priority(.high)
        }

        skeletonTitleView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(12)
            make.top.equalToSuperview().offset(14)
            make.width.equalTo(76)
            make.height.equalTo(18)
        }

        skeletonPriceView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(12)
            make.bottom.equalToSuperview().offset(-14)
            make.width.equalTo(94)
            make.height.equalTo(30)
        }
    }

    @objc private func handleTap() { onTap?(kind) }

    private func showSkeleton() {
        guard !isSkeletonVisible else { return }
        isSkeletonVisible = true

        titleLabel.isHidden = true
        priceLabel.isHidden = true
        badgeLabel.isHidden = true
        savingLabel.isHidden = true

        [skeletonTitleView, skeletonPriceView].forEach { view in
            view.isHidden = false
        }

        setNeedsLayout()
        layoutIfNeeded()
        startSkeletonAnimation()
    }

    private func hideSkeleton() {
        guard isSkeletonVisible else { return }
        isSkeletonVisible = false

        titleLabel.isHidden = false
        priceLabel.isHidden = false

        [skeletonTitleView, skeletonPriceView].forEach { view in
            view.isHidden = true
        }

        skeletonLayers.forEach {
            $0.removeAnimation(forKey: "shimmer")
            $0.removeFromSuperlayer()
        }
        skeletonLayers.removeAll()
    }

    private func startSkeletonAnimation() {
        skeletonLayers.forEach {
            $0.removeAnimation(forKey: "shimmer")
            $0.removeFromSuperlayer()
        }
        skeletonLayers.removeAll()

        [skeletonTitleView, skeletonPriceView].forEach { view in
            let gradient = CAGradientLayer()
            gradient.colors = [
                UIColor.systemGray4.withAlphaComponent(0.35).cgColor,
                UIColor.systemGray3.withAlphaComponent(0.70).cgColor,
                UIColor.systemGray4.withAlphaComponent(0.35).cgColor
            ]
            gradient.locations = [0.0, 0.5, 1.0]
            gradient.startPoint = CGPoint(x: 0.0, y: 0.5)
            gradient.endPoint = CGPoint(x: 1.0, y: 0.5)
            gradient.frame = view.bounds.insetBy(dx: -view.bounds.width, dy: 0)
            view.layer.addSublayer(gradient)
            skeletonLayers.append(gradient)

            let animation = CABasicAnimation(keyPath: "transform.translation.x")
            animation.fromValue = -view.bounds.width
            animation.toValue = view.bounds.width
            animation.duration = 1.15
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            gradient.add(animation, forKey: "shimmer")
        }
    }

    private func updateSkeletonLayerFrames() {
        guard isSkeletonVisible else { return }
        let views = [skeletonTitleView, skeletonPriceView]
        for (index, layer) in skeletonLayers.enumerated() where index < views.count {
            let view = views[index]
            layer.frame = view.bounds.insetBy(dx: -view.bounds.width, dy: 0)
        }
    }
}

// MARK: - BenefitRowView

private final class BenefitRowView: UIView {
    private let dotView   = UIView()
    private let textLabel = UILabel()

    init(text: String, dotColor: UIColor) {
        super.init(frame: .zero)
        configUI(text: text, dotColor: dotColor)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func configUI(text: String, dotColor: UIColor) {
        backgroundColor    = .secondarySystemGroupedBackground
        layer.cornerRadius = 16

        dotView.backgroundColor    = dotColor
        dotView.layer.cornerRadius = 4.5

        textLabel.font           = .roundedSystemFont(ofSize: 16, weight: .regular)
        textLabel.textColor      = .label
        textLabel.numberOfLines  = 0
        textLabel.attributedText = makeAttributedText(text)

        addSubview(dotView)
        addSubview(textLabel)

        dotView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.width.height.equalTo(9)
            make.centerY.equalTo(textLabel.snp.top).offset(textLabel.font.lineHeight * 0.5)
        }
        textLabel.snp.makeConstraints { make in
            make.leading.equalTo(dotView.snp.trailing).offset(10)
            make.trailing.equalToSuperview().offset(-16)
            make.top.equalToSuperview().offset(12)
            make.bottom.equalToSuperview().offset(-12)
        }
    }

    private func makeAttributedText(_ text: String) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineSpacing   = 5
        style.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: text, attributes: [
            .font:            textLabel.font as Any,
            .foregroundColor: textLabel.textColor as Any,
            .paragraphStyle:  style
        ])
    }
}

// MARK: - LinkTextView

class LinkTextView: UITextView, UITextViewDelegate {
    typealias Links     = [String: String]
    typealias OnLinkTap = (URL) -> Bool
    var onLinkTap: OnLinkTap?

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        isEditable      = false
        isSelectable    = true
        isScrollEnabled = false
        delegate        = self
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    func addLinks(_ links: Links) {
        guard attributedText.length > 0 else { return }
        let mText = NSMutableAttributedString(attributedString: attributedText)
        for (linkText, urlString) in links {
            guard linkText.count > 0 else { continue }
            let range = mText.mutableString.range(of: linkText)
            if range.location != NSNotFound {
                mText.addAttribute(.link, value: urlString, range: range)
            }
        }
        attributedText = mText
    }

    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange) -> Bool {
        return onLinkTap?(URL) ?? true
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        textView.selectedTextRange = nil
    }
}

extension UIFont {
    static func roundedSystemFont(ofSize size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let baseFont = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = baseFont.fontDescriptor.withDesign(.rounded) else {
            return baseFont
        }
        return UIFont(descriptor: descriptor, size: size)
    }
}
