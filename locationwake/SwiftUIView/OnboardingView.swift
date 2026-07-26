import SwiftUI
import CoreLocation
import UIKit
import UserNotifications

struct OnboardingView: View {
    enum PresentationMode: Equatable {
        case firstRun
        case help
    }

    private enum Step: Equatable {
        case intro
        case location
        case notification
    }

    private enum AccessibilityFocusTarget: Hashable {
        case stepHeading
        case authorizationStatus
        case primaryAction
    }

    private enum ScrollTarget {
        static let stepTop = "onboarding-step-top"
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject private var permissionReadiness: PermissionReadiness
    @AccessibilityFocusState private var accessibilityFocus: AccessibilityFocusTarget?
    @ScaledMetric(relativeTo: .largeTitle) private var heroSymbolSize = 106

    private let presentationMode: PresentationMode
    private let onCompleted: () -> Void

    @State private var step: Step = .intro
    @State private var hasAttemptedLocationRequest = false
    @State private var hasAttemptedNotificationRequest = false
    @State private var isRequestingNotification = false
    @State private var pendingAuthorizationStep: Step?

    init(
        presentationMode: PresentationMode = .firstRun,
        permissionReadiness: PermissionReadiness = .shared,
        onCompleted: @escaping () -> Void = {}
    ) {
        self.presentationMode = presentationMode
        self.onCompleted = onCompleted
        _permissionReadiness = ObservedObject(wrappedValue: permissionReadiness)
    }

    var body: some View {
        VStack(spacing: 0) {
            if presentationMode == .help {
                HStack {
                    Spacer()
                    Button("閉じる") {
                        dismiss()
                    }
                    .tint(AppDesign.tint)
                    .frame(minWidth: 44, minHeight: 44)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    stepContent
                        .id(ScrollTarget.stepTop)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 28)
                        .padding(.top, 24)
                        .padding(.bottom, 20)
                }
                .onChange(of: step) { _, _ in
                    accessibilityFocus = nil
                    DispatchQueue.main.async {
                        proxy.scrollTo(ScrollTarget.stepTop, anchor: .top)
                    }

                    let focusDelay = reduceMotion ? 0 : 0.25
                    DispatchQueue.main.asyncAfter(deadline: .now() + focusDelay) {
                        accessibilityFocus = .stepHeading
                    }
                }
            }

            controls
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .interactiveDismissDisabled(presentationMode == .firstRun)
        .accessibilityAddTraits(.isModal)
        .onAppear {
            permissionReadiness.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .locationAuthorizationDidChange)) { _ in
            permissionReadiness.refresh {
                focusAfterPendingAuthorizationResult()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            permissionReadiness.refresh {
                focusAfterPendingAuthorizationResult()
            }
        }
        .onChange(of: permissionReadiness.snapshot) { oldValue, newValue in
            focusAfterAuthorizationChange(from: oldValue, to: newValue)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .intro:
            introContent
        case .location:
            onboardingMessage(
                symbol: "location.fill.viewfinder",
                title: "到着を見守るために",
                message: "アプリを閉じている間も目的地への到着を検知するため、位置情報の「常に許可」が必要です。許可はあとから設定でも変更できます。",
                status: locationStatus
            )
        case .notification:
            onboardingMessage(
                symbol: "bell.badge.fill",
                title: "到着をお知らせするために",
                message: "目的地に近づいたことを、通知・音・バイブレーションでお知らせします。通知はあとから設定でも変更できます。",
                status: notificationStatus
            )
        }
    }

    private var introContent: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 12)

            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell.fill")
                    .font(.system(size: displayedHeroSymbolSize, weight: .regular))
                    .foregroundStyle(AppDesign.tint)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(
                        size: displayedHeroSymbolSize * 0.4,
                        weight: .regular
                    ))
                    .foregroundStyle(AppDesign.tint)
                    .background(Circle().fill(.background).padding(3))
                    .offset(x: 8, y: -4)
            }
            .accessibilityHidden(true)

            Text("目的地で、確実に起きる。")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .lineLimit(dynamicTypeSize >= .xxLarge ? 2 : 1)
                .minimumScaleFactor(0.72)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($accessibilityFocus, equals: .stepHeading)

            Text("到着時に通知・音・バイブレーションでお知らせします。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            onboardingFlow
                .padding(.vertical, 8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("場所を探す、目的地を設定する、到着をお知らせする")

            preparationCallout
            .padding(18)
            .background(
                AppDesign.tint.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )

            Spacer(minLength: 12)
        }
        .frame(minHeight: 520)
    }

    private var displayedHeroSymbolSize: CGFloat {
        dynamicTypeSize.isAccessibilitySize
            ? min(heroSymbolSize, 96)
            : heroSymbolSize
    }

    @ViewBuilder
    private var preparationCallout: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                preparationCalloutIcon
                preparationCalloutText
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .top, spacing: 14) {
                preparationCalloutIcon
                preparationCalloutText
                Spacer(minLength: 0)
            }
        }
    }

    private var preparationCalloutIcon: some View {
        Image(systemName: "info.circle")
            .font(.title2)
            .foregroundStyle(AppDesign.tint)
            .accessibilityHidden(true)
    }

    private var preparationCalloutText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("準備が必要です")
                .font(.headline)
            Text("次に、到着を見守るための設定を行います。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var onboardingFlow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                onboardingFlowRow(
                    symbol: "magnifyingglass",
                    title: "さがす",
                    color: .secondary
                )
                verticalFlowDivider
                onboardingFlowRow(
                    symbol: "mappin.circle.fill",
                    title: "目的地を設定",
                    color: .primary
                )
                verticalFlowDivider
                onboardingFlowRow(
                    symbol: "bell.badge.fill",
                    title: "到着をお知らせ",
                    color: AppDesign.tint
                )
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                onboardingFlowItem(
                    symbol: "magnifyingglass",
                    title: "さがす",
                    color: .secondary
                )
                flowDivider
                onboardingFlowItem(
                    symbol: "mappin.circle.fill",
                    title: "目的地を設定",
                    color: .secondary
                )
                flowDivider
                onboardingFlowItem(
                    symbol: "bell.badge.fill",
                    title: "到着をお知らせ",
                    color: AppDesign.tint
                )
            }
        }
    }

    private func onboardingFlowItem(
        symbol: String,
        title: String,
        color: Color
    ) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title)
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private func onboardingFlowRow(
        symbol: String,
        title: String,
        color: Color
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title)
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
            Text(title)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var flowDivider: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 24, height: 1)
            .padding(.top, 22)
            .accessibilityHidden(true)
    }

    private var verticalFlowDivider: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 1, height: 16)
            .padding(.leading, 22)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var controls: some View {
        switch step {
        case .intro:
            primaryButton("設定を始める", identifier: "onboarding.prepare") {
                move(to: .location)
            }
        case .location:
            locationControls
        case .notification:
            notificationControls
        }
    }

    @ViewBuilder
    private var locationControls: some View {
        let authorization = permissionReadiness.snapshot.locationAuthorization

        switch authorization {
        case .notDetermined:
            primaryButton(
                "位置情報を許可",
                identifier: "onboarding.location.request"
            ) {
                hasAttemptedLocationRequest = true
                pendingAuthorizationStep = .location
                permissionReadiness.requestAlwaysLocationAuthorization()
            }

            if hasAttemptedLocationRequest {
                secondaryButton(
                    "あとで設定する",
                    identifier: "onboarding.location.continue"
                ) {
                    move(to: .notification)
                }
            }
        case .authorizedAlways:
            primaryButton(
                "次へ",
                identifier: "onboarding.location.continue"
            ) {
                move(to: .notification)
            }
        case .authorizedWhenInUse:
            primaryButton(
                permissionReadiness.canRequestAlwaysUpgradeInApp
                    ? "「常に許可」をリクエスト"
                    : "設定で「常に許可」にする",
                identifier: "onboarding.location.requestAlways"
            ) {
                hasAttemptedLocationRequest = true
                pendingAuthorizationStep = .location
                permissionReadiness.requestAlwaysLocationAuthorization()
            }
            secondaryButton(
                "あとで設定する",
                identifier: "onboarding.location.continue"
            ) {
                move(to: .notification)
            }
        case .denied, .restricted:
            primaryButton(
                "通知の設定へ",
                identifier: "onboarding.location.continue"
            ) {
                move(to: .notification)
            }
            if authorization == .denied {
                secondaryButton("設定を開く", identifier: "onboarding.location.settings") {
                    pendingAuthorizationStep = .location
                    permissionReadiness.openAppSettings()
                }
            }
        @unknown default:
            primaryButton(
                "通知の設定へ",
                identifier: "onboarding.location.continue"
            ) {
                move(to: .notification)
            }
        }
    }

    @ViewBuilder
    private var notificationControls: some View {
        let authorization = permissionReadiness.snapshot.notificationAuthorization

        switch authorization {
        case .notDetermined:
            primaryButton(
                isRequestingNotification ? "確認中…" : "通知を許可",
                identifier: "onboarding.notification.request"
            ) {
                hasAttemptedNotificationRequest = true
                isRequestingNotification = true
                pendingAuthorizationStep = .notification
                permissionReadiness.requestNotificationAuthorization {
                    isRequestingNotification = false
                    focusAfterPendingAuthorizationResult()
                }
            }
            .disabled(isRequestingNotification)

            if hasAttemptedNotificationRequest && !isRequestingNotification {
                secondaryButton(
                    "あとで設定する",
                    identifier: "onboarding.complete"
                ) {
                    finish()
                }
            }
        case .authorized, .provisional, .ephemeral:
            primaryButton("はじめる", identifier: "onboarding.complete") {
                finish()
            }
        case .denied:
            primaryButton("はじめる", identifier: "onboarding.complete") {
                finish()
            }
            secondaryButton("設定を開く", identifier: "onboarding.notification.settings") {
                pendingAuthorizationStep = .notification
                permissionReadiness.openAppSettings()
            }
        @unknown default:
            primaryButton("はじめる", identifier: "onboarding.complete") {
                finish()
            }
        }
    }

    private var locationStatus: (text: String, isReady: Bool)? {
        switch permissionReadiness.snapshot.locationAuthorization {
        case .authorizedAlways:
            return ("「常に許可」が選ばれています。iOSから確認が表示された場合も「常に許可」を選んでください", true)
        case .authorizedWhenInUse:
            return ("現在は「このAppの使用中」です", false)
        case .denied:
            return ("位置情報は許可されていません", false)
        case .restricted:
            return ("この端末では位置情報が制限されています", false)
        case .notDetermined:
            return nil
        @unknown default:
            return ("位置情報の状態を確認できません", false)
        }
    }

    private var notificationStatus: (text: String, isReady: Bool)? {
        switch permissionReadiness.snapshot.notificationAuthorization {
        case .authorized, .provisional, .ephemeral:
            return ("通知は許可されています", true)
        case .denied:
            return ("通知は許可されていません", false)
        case .notDetermined:
            return nil
        @unknown default:
            return ("通知の状態を確認できません", false)
        }
    }

    private func onboardingMessage(
        symbol: String,
        title: String,
        message: String,
        status: (text: String, isReady: Bool)? = nil
    ) -> some View {
        VStack(spacing: 24) {
            Spacer(minLength: 24)
            Image(systemName: symbol)
                .font(.system(size: displayedHeroSymbolSize, weight: .regular))
                .foregroundStyle(AppDesign.tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($accessibilityFocus, equals: .stepHeading)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let status {
                Label(
                    status.text,
                    systemImage: status.isReady
                        ? "checkmark.circle.fill"
                        : "exclamationmark.triangle.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(status.isReady ? AppDesign.tint : Color.orange)
                .multilineTextAlignment(.center)
                .accessibilityFocused($accessibilityFocus, equals: .authorizationStatus)
            }
            Spacer(minLength: 24)
        }
        .frame(minHeight: 430)
    }

    private func primaryButton(
        _ title: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, minHeight: 28)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppDesign.prominentButtonTint)
        .controlSize(.large)
        .accessibilityIdentifier(identifier)
        .accessibilityFocused($accessibilityFocus, equals: .primaryAction)
    }

    private func secondaryButton(
        _ title: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderless)
            .frame(minHeight: 44)
            .padding(.top, 4)
            .accessibilityIdentifier(identifier)
    }

    private func move(to nextStep: Step) {
        pendingAuthorizationStep = nil
        accessibilityFocus = nil
        if reduceMotion {
            step = nextStep
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                step = nextStep
            }
        }
    }

    private func focusAfterAuthorizationChange(
        from oldValue: PermissionReadinessSnapshot,
        to newValue: PermissionReadinessSnapshot
    ) {
        let didChangeCurrentAuthorization: Bool
        switch step {
        case .location where oldValue.locationAuthorization != newValue.locationAuthorization:
            didChangeCurrentAuthorization = true
        case .notification
            where oldValue.notificationAuthorization != newValue.notificationAuthorization:
            didChangeCurrentAuthorization = true
        default:
            didChangeCurrentAuthorization = false
        }
        guard didChangeCurrentAuthorization else { return }
        pendingAuthorizationStep = nil
        focusOnCurrentAuthorizationSuccessor()
    }

    private func focusAfterPendingAuthorizationResult() {
        guard pendingAuthorizationStep == step else { return }
        pendingAuthorizationStep = nil
        focusOnCurrentAuthorizationSuccessor()
    }

    private func focusOnCurrentAuthorizationSuccessor() {
        let target: AccessibilityFocusTarget
        switch step {
        case .location:
            target = locationStatus == nil ? .primaryAction : .authorizationStatus
        case .notification:
            target = notificationStatus == nil ? .primaryAction : .authorizationStatus
        case .intro:
            target = .stepHeading
        }

        accessibilityFocus = nil
        DispatchQueue.main.async {
            accessibilityFocus = target
        }
    }

    private func finish() {
        onCompleted()
        dismiss()
    }
}
