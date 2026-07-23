import SwiftUI
import UIKit

enum RadiusChoice: String, CaseIterable, Identifiable {
    case oneHundred
    case threeHundred
    case fiveHundred
    case oneKilometer
    case threeKilometers
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneHundred: "100 m"
        case .threeHundred: "300 m"
        case .fiveHundred: "500 m"
        case .oneKilometer: "1 km"
        case .threeKilometers: "3 km"
        case .custom: "カスタム"
        }
    }

    var meters: Double? {
        switch self {
        case .oneHundred: 100
        case .threeHundred: 300
        case .fiveHundred: 500
        case .oneKilometer: 1_000
        case .threeKilometers: 3_000
        case .custom: nil
        }
    }

    static func matching(_ radius: Double) -> RadiusChoice {
        allCases.first {
            guard let meters = $0.meters else { return false }
            return abs(meters - radius) < 0.5
        } ?? .custom
    }
}

struct RadiusPickerControl: View {
    @Binding var radius: Double
    @State private var choice: RadiusChoice

    init(radius: Binding<Double>) {
        _radius = radius
        _choice = State(initialValue: RadiusChoice.matching(radius.wrappedValue))
    }

    var body: some View {
        Picker("到着範囲", selection: $choice) {
            ForEach(RadiusChoice.allCases) { choice in
                Text(choice.title).tag(choice)
            }
        }
        .onChange(of: choice) { _, newChoice in
            if let meters = newChoice.meters {
                radius = meters
            }
        }

        if choice == .custom {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Slider(
                        value: $radius,
                        in: Alarm.minimumGeofenceRadius...Alarm.maximumGeofenceRadius,
                        step: 100
                    )
                    .accessibilityLabel("カスタムの到着範囲")
                    .accessibilityValue(exactValue)

                    Text(exactValue)
                        .font(.body.monospacedDigit())
                        .frame(minWidth: 72, alignment: .trailing)
                        .accessibilityHidden(true)
                }

                Stepper(
                    value: $radius,
                    in: Alarm.minimumGeofenceRadius...Alarm.maximumGeofenceRadius,
                    step: 100
                ) {
                    HStack {
                        Text("100 mずつ調整")
                        Spacer()
                        Text(exactValue)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .accessibilityValue(exactValue)
            }
        }
    }

    private var exactValue: String {
        "\(Int(radius.rounded())) m"
    }
}

/// 編集中シートのスワイプ終了を検知し、破棄確認を表示するための橋渡し。
struct SheetDismissAttemptObserver: UIViewControllerRepresentable {
    let isDismissDisabled: Bool
    let onAttempt: () -> Void

    func makeUIViewController(context: Context) -> ObserverViewController {
        ObserverViewController()
    }

    func updateUIViewController(
        _ controller: ObserverViewController,
        context: Context
    ) {
        controller.isDismissDisabled = isDismissDisabled
        controller.onAttempt = onAttempt
        controller.installDelegate()
    }

    final class ObserverViewController: UIViewController,
        UIAdaptivePresentationControllerDelegate {
        var isDismissDisabled = false
        var onAttempt: (() -> Void)?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            installDelegate()
        }

        func installDelegate() {
            parent?.presentationController?.delegate = self
        }

        func presentationControllerShouldDismiss(
            _ presentationController: UIPresentationController
        ) -> Bool {
            !isDismissDisabled
        }

        func presentationControllerDidAttemptToDismiss(
            _ presentationController: UIPresentationController
        ) {
            guard isDismissDisabled else { return }
            onAttempt?()
        }
    }
}
