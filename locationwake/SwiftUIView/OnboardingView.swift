import SwiftUI
import CoreLocation
import UIKit
import UserNotifications

struct OnboardingView: View {
    enum PresentationMode: Equatable {
        case firstRun
        case help
    }

    private enum Step {
        case intro
        case location
        case notification
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject private var permissionReadiness: PermissionReadiness
    @ScaledMetric(relativeTo: .largeTitle) private var heroSymbolSize = 88

    private let presentationMode: PresentationMode
    private let onCompleted: () -> Void

    @State private var step: Step = .intro
    @State private var hasAttemptedLocationRequest = false
    @State private var hasAttemptedNotificationRequest = false
    @State private var isRequestingNotification = false

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
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
            }

            ScrollView {
                stepContent
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
                    .padding(.bottom, 20)
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
            permissionReadiness.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            permissionReadiness.refresh()
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
                    .font(.system(size: heroSymbolSize, weight: .regular))
                    .foregroundStyle(AppDesign.tint)
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(AppDesign.tint)
                    .background(Circle().fill(.background).padding(3))
                    .offset(x: 8, y: -4)
            }
            .accessibilityHidden(true)

            Text("目的地で、確実に起きる。")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(0.78)

            Text("到着時に通知・音・バイブレーションでお知らせします。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(alignment: .top, spacing: 10) {
                onboardingFlowItem(
                    symbol: "magnifyingglass",
                    title: "さがす"
                )
                flowDivider
                onboardingFlowItem(
                    symbol: "mappin.circle.fill",
                    title: "目的地を設定"
                )
                flowDivider
                onboardingFlowItem(
                    symbol: "bell.badge.fill",
                    title: "到着をお知らせ"
                )
            }
            .padding(.vertical, 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("場所を探す、目的地を設定する、到着をお知らせする")

            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "info.circle")
                    .font(.title2)
                    .foregroundStyle(AppDesign.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("準備が必要です")
                        .font(.headline)
                    Text("次に、到着を見守るための設定を行います。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )

            Spacer(minLength: 12)
        }
        .frame(minHeight: 520)
    }

    private func onboardingFlowItem(
        symbol: String,
        title: String
    ) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(AppDesign.tint)
                .frame(width: 44, height: 44)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var flowDivider: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 24, height: 1)
            .padding(.top, 22)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var controls: some View {
        switch step {
        case .intro:
            primaryButton("準備を始める", identifier: "onboarding.prepare") {
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
                "「常に許可」をリクエスト",
                identifier: "onboarding.location.requestAlways"
            ) {
                hasAttemptedLocationRequest = true
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
                permissionReadiness.requestNotificationAuthorization {
                    isRequestingNotification = false
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
            return ("「常に許可」になっています", true)
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
                .font(.system(size: heroSymbolSize, weight: .regular))
                .foregroundStyle(AppDesign.tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
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
            .tint(AppDesign.tint)
            .controlSize(.large)
            .accessibilityIdentifier(identifier)
    }

    private func secondaryButton(
        _ title: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderless)
            .padding(.top, 10)
            .accessibilityIdentifier(identifier)
    }

    private func move(to nextStep: Step) {
        if reduceMotion {
            step = nextStep
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                step = nextStep
            }
        }
        UIAccessibility.post(
            notification: .screenChanged,
            argument: nil
        )
    }

    private func finish() {
        onCompleted()
        dismiss()
    }
}
