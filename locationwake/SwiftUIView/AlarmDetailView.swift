import AVFoundation
import CoreLocation
import MapKit
import SwiftUI
import UIKit

private struct AlarmDraft: Equatable {
    var name: String
    var repeatWeekdays: Set<Int>
    var sound: String
    var isSoundEnabled: Bool
    var isVibrationEnabled: Bool
    var location: Location
    var radius: Double

    init(alarm: Alarm) {
        name = alarm.name
        repeatWeekdays = Set(Alarm.normalizedWeekdays(alarm.repeatWeekdays) ?? [])
        sound = alarm.sound
        isSoundEnabled = alarm.isSoundEnabled
        isVibrationEnabled = alarm.isVibrationEnabled
        location = alarm.location ?? Location(latitude: 0, longitude: 0)
        radius = alarm.geofenceRadius ?? Alarm.defaultGeofenceRadius
    }
}

struct AlarmDetailView: View {
    private let alarmID: String
    private let initialDraft: AlarmDraft
    private let isNewAlarm: Bool

    @State private var draft: AlarmDraft
    @State private var cameraPosition: MapCameraPosition
    @State private var showsDiscardConfirmation = false
    @State private var showsLimitAlert = false
    @State private var saveErrorMessage: String?
    @State private var monitoringFailure: String?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var navigationModel: NavigationModel
    @EnvironmentObject private var viewModel: AlarmListViewModel

    init(alarm: Alarm, isNew: Bool? = nil) {
        let initialDraft = AlarmDraft(alarm: alarm)
        alarmID = alarm.id
        self.initialDraft = initialDraft
        isNewAlarm = isNew ?? !AlarmStore.load().contains(where: { $0.id == alarm.id })
        _draft = State(initialValue: initialDraft)
        _cameraPosition = State(initialValue: .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: initialDraft.location.latitude,
                longitude: initialDraft.location.longitude
            ),
            latitudinalMeters: max(initialDraft.radius * 3.2, 900),
            longitudinalMeters: max(initialDraft.radius * 3.2, 900)
        )))
    }

    var body: some View {
        Form {
            nameSection
            locationSection
            radiusSection
            monitoringSection
            notificationSection
            repeatSection
        }
        .formStyle(.grouped)
        .tint(AppDesign.tint)
        .scrollContentBackground(.hidden)
        .background(AppDesign.background)
        .navigationTitle(isNewAlarm ? "新しいアラーム" : "アラームを編集")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル", action: cancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: saveCurrentAlarm)
                    .fontWeight(.semibold)
                    .disabled(trimmedName.isEmpty)
                    .accessibilityHint(
                        trimmedName.isEmpty
                            ? "保存するにはアラーム名を入力してください"
                            : "アラームの設定を保存します"
                    )
            }
        }
        .interactiveDismissDisabled(isDirty)
        .background {
            SheetDismissAttemptObserver(
                isDismissDisabled: isDirty,
                onAttempt: { showsDiscardConfirmation = true }
            )
            .frame(width: 0, height: 0)
        }
        .alert("変更を破棄しますか？", isPresented: $showsDiscardConfirmation) {
            Button("編集を続ける", role: .cancel) {}
            Button("変更を破棄", role: .destructive) {
                dismiss()
            }
        } message: {
            Text("保存していない変更は失われます。")
        }
        .alert("アラームを追加できません", isPresented: $showsLimitAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("アラームは最大\(Alarm.maximumSavedAlarms)件です。不要なアラームを削除してから、もう一度お試しください。")
        }
        .alert(
            "保存できませんでした",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "")
        }
        .onAppear(perform: refreshMonitoringFailure)
        .onReceive(
            NotificationCenter.default.publisher(for: .alarmMonitoringStatusDidChange)
        ) { notification in
            guard notification.object as? String == alarmID else { return }
            refreshMonitoringFailure()
        }
    }

    private var nameSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "tag")
                    .foregroundStyle(AppDesign.tint)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                TextField("例：大阪駅", text: $draft.name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .accessibilityLabel("アラーム名")
                    .accessibilityIdentifier("alarmEditor.name")

                if !draft.name.isEmpty {
                    Button {
                        draft.name = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("アラーム名を消去")
                }
            }

            if trimmedName.isEmpty {
                Label {
                    Text("保存するにはアラーム名を入力してください")
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                }
                    .font(.footnote)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("保存できません。アラーム名を入力してください")
                    .accessibilityAddTraits(.isStaticText)
                    .accessibilityIdentifier("alarmEditor.nameValidation")
            }
        } header: {
            Text("アラーム名")
        }
    }

    private var locationSection: some View {
        Section("目的地") {
            AlarmDetailMapPreview(
                cameraPosition: $cameraPosition,
                location: draft.location,
                radius: draft.radius,
                title: trimmedName.isEmpty ? "目的地" : trimmedName
            )

            Label {
                Text("選択した目的地")
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(AppDesign.tint)
            }
        }
        .onChange(of: draft.radius) { _, radius in
            cameraPosition = .region(MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: max(radius * 3.2, 900),
                longitudinalMeters: max(radius * 3.2, 900)
            ))
        }
    }

    private var radiusSection: some View {
        Section {
            RadiusPickerControl(radius: $draft.radius)
        } header: {
            Text("到着範囲")
        } footer: {
            Text("現在値が候補にない場合は「カスタム」として表示します。")
        }
    }

    @ViewBuilder
    private var monitoringSection: some View {
        if monitoringFailure != nil || monitoringMethodDescription != nil {
            Section("監視状況") {
                if let monitoringFailure {
                    Label(monitoringFailure, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                if let monitoringMethodDescription {
                    Label(monitoringMethodDescription, systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var notificationSection: some View {
        Section {
            Toggle(isOn: $draft.isSoundEnabled) {
                Label("音を鳴らす", systemImage: "bell")
            }

            Toggle(isOn: $draft.isVibrationEnabled) {
                Label(
                    "バイブレーション",
                    systemImage: "iphone.gen3.radiowaves.left.and.right"
                )
            }

            NavigationLink {
                SoundSelectionView(selectedSound: $draft.sound)
            } label: {
                LabeledContent {
                    Text(draft.sound)
                        .foregroundStyle(.secondary)
                } label: {
                    Label("サウンド", systemImage: "music.note")
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
        } header: {
            Text("通知方法")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("アラームは、目的地の範囲外に出てから再び入ると通知します。")
                Text("バイブレーションのみの場合、バックグラウンドでの繰り返し振動は保証されません。")
            }
        }
    }

    private var repeatSection: some View {
        Section("繰り返し") {
            NavigationLink {
                RepeatWeekdaySelectionView(
                    selectedWeekdays: $draft.repeatWeekdays
                )
            } label: {
                LabeledContent {
                    Text(weekdaySummary)
                        .foregroundStyle(.secondary)
                } label: {
                    Label(
                        "繰り返し",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
        }
    }

    private var isDirty: Bool {
        draft != initialDraft
    }

    private var trimmedName: String {
        draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: draft.location.latitude,
            longitude: draft.location.longitude
        )
    }

    private var weekdaySummary: String {
        let names = ["日", "月", "火", "水", "木", "金", "土"]
        let validDays = draft.repeatWeekdays.filter { names.indices.contains($0) }
        guard !validDays.isEmpty else { return "繰り返さない" }
        return validDays.sorted().map { names[$0] }.joined(separator: "・")
    }

    private var monitoringMethodDescription: String? {
        guard let geofenceMaximum = LocationManager.shared.maximumGeofenceRadius else {
            return "この到着範囲は現在地の継続確認を使うため、電池消費が増えることがあります。"
        }
        guard draft.radius > geofenceMaximum else { return nil }
        return "\(Int(geofenceMaximum)) mを超えるため、現在地の継続確認を使います。"
    }

    private func cancel() {
        if isDirty {
            showsDiscardConfirmation = true
        } else {
            dismiss()
        }
    }

    private func saveCurrentAlarm() {
        guard !trimmedName.isEmpty else {
            UIAccessibility.post(
                notification: .announcement,
                argument: "アラーム名を入力してください"
            )
            return
        }

        let loadResult = AlarmStore.loadResult()
        guard case .success(var savedAlarms) = loadResult else {
            if case .failure(let error) = loadResult {
                saveErrorMessage = error.localizedDescription
            } else {
                saveErrorMessage = "保存したアラームを読み込めませんでした。"
            }
            return
        }
        let existingIndex = savedAlarms.firstIndex(where: { $0.id == alarmID })

        if isNewAlarm {
            guard savedAlarms.count < Alarm.maximumSavedAlarms else {
                showsLimitAlert = true
                return
            }
        } else if existingIndex == nil {
            saveErrorMessage = "編集中のアラームが見つかりません。削除された可能性があります。"
            return
        }

        let currentLocation = LocationManager.shared.locationManager.location
        let savedAlarm: Alarm

        if let existingIndex {
            // 発火中に状態が変わる可能性があるため、保存直前の最新値へ編集項目だけを反映する。
            var latest = savedAlarms[existingIndex]

            latest.name = trimmedName
            latest.repeatWeekdays = Alarm.normalizedWeekdays(
                Array(draft.repeatWeekdays)
            )
            latest.sound = draft.sound
            latest.isSoundEnabled = draft.isSoundEnabled
            latest.isVibrationEnabled = draft.isVibrationEnabled
            latest.location = draft.location
            latest.radius = Alarm.normalizedRadius(draft.radius)

            // 明示的に保存した時は、すでに領域内でも即発火させず、
            // 新しい監視世代で「退出後の再入場」を待つ。
            if latest.isAlarmEnabled {
                latest = LocationManager.preparedForInitialStateCheck(
                    latest,
                    currentLocation: currentLocation
                )
            }
            savedAlarms[existingIndex] = latest
            savedAlarm = latest
        } else {
            var newAlarm = Alarm(
                id: alarmID,
                name: trimmedName,
                repeatWeekdays: Array(draft.repeatWeekdays),
                sound: draft.sound,
                isAlarmEnabled: true,
                isSoundEnabled: draft.isSoundEnabled,
                isVibrationEnabled: draft.isVibrationEnabled,
                location: draft.location,
                radius: draft.radius
            )
            newAlarm = LocationManager.preparedForInitialStateCheck(
                newAlarm,
                currentLocation: currentLocation
            )
            savedAlarms.append(newAlarm)
            savedAlarm = newAlarm
        }

        switch AlarmStore.save(savedAlarms) {
        case .success:
            break
        case .failure(let error):
            saveErrorMessage = error.localizedDescription
            return
        }
        viewModel.loadAlarms()
        if !AppRuntime.shouldSuppressExternalSideEffects {
            LocationManager.shared.startMonitoring(alarms: savedAlarms)
        }
        NotificationCenter.default.post(name: .alarmSaved, object: savedAlarm)
        UIAccessibility.post(
            notification: .announcement,
            argument: "アラームを保存しました"
        )
        navigationModel.path = []
        dismiss()
    }

    private func refreshMonitoringFailure() {
        monitoringFailure = UserDefaults.standard.string(
            forKey: "MonitoringFailure_\(alarmID)"
        )
    }
}

private struct AlarmDetailMapPreview: View {
    @Binding var cameraPosition: MapCameraPosition
    let location: Location
    let radius: Double
    let title: String

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: location.latitude,
            longitude: location.longitude
        )
    }

    var body: some View {
        Map(position: $cameraPosition, interactionModes: []) {
            MapCircle(center: coordinate, radius: radius)
                .foregroundStyle(AppDesign.tint.opacity(0.2))
                .stroke(AppDesign.tint, lineWidth: 2)
            Marker(title, coordinate: coordinate)
                .tint(AppDesign.tint)
        }
        .frame(height: 214)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("目的地の地図")
        .accessibilityValue("\(title)、到着範囲 \(Int(radius)) m")
    }
}

struct SoundSelectionView: View {
    @Binding var selectedSound: String
    private let sounds = ["kind", "modan", "siren"]
    @State private var audioPlayer: AVAudioPlayer?

    var body: some View {
        Form {
            Section("アラーム音") {
                ForEach(sounds, id: \.self) { sound in
                    HStack(spacing: 8) {
                        Button {
                            selectedSound = sound
                        } label: {
                            HStack {
                                Label(sound, systemImage: "speaker.wave.2")
                                Spacer()
                                if sound == selectedSound {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(AppDesign.tint)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(
                            sound == selectedSound ? "選択済み" : "未選択"
                        )
                        .accessibilityAddTraits(
                            sound == selectedSound
                                ? .isSelected
                                : AccessibilityTraits()
                        )

                        Button {
                            preview(sound)
                        } label: {
                            Image(systemName: "play.fill")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("\(sound)を試聴")
                    }
                }
            }
        }
        .tint(AppDesign.tint)
        .scrollContentBackground(.hidden)
        .background(AppDesign.background)
        .navigationTitle("サウンド")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            audioPlayer?.stop()
            audioPlayer = nil
        }
    }

    private func preview(_ sound: String) {
        guard let url = Bundle.main.url(
            forResource: sound,
            withExtension: "mp3"
        ) else {
            return
        }
        do {
            audioPlayer?.stop()
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
        } catch {
#if DEBUG
            print("Error playing sound: \(error.localizedDescription)")
#endif
        }
    }
}

struct RepeatWeekdaySelectionView: View {
    @Binding var selectedWeekdays: Set<Int>
    private let days = [
        "日曜日", "月曜日", "火曜日", "水曜日", "木曜日", "金曜日", "土曜日"
    ]
    private let shortDays = ["日", "月", "火", "水", "木", "金", "土"]

    var body: some View {
        Form {
            Section {
                selectionButton(
                    title: "繰り返さない",
                    isSelected: selectedWeekdays.isEmpty
                ) {
                    selectedWeekdays.removeAll()
                }

                ForEach(days.indices, id: \.self) { index in
                    selectionButton(
                        title: days[index],
                        isSelected: selectedWeekdays.contains(index)
                    ) {
                        if selectedWeekdays.contains(index) {
                            selectedWeekdays.remove(index)
                        } else {
                            selectedWeekdays.insert(index)
                        }
                    }
                }
            } header: {
                Text("繰り返し")
            } footer: {
                Text(footerText)
            }
        }
        .tint(AppDesign.tint)
        .scrollContentBackground(.hidden)
        .background(AppDesign.background)
        .navigationTitle("繰り返し")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func selectionButton(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(AppDesign.tint)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? "選択済み" : "未選択")
        .accessibilityAddTraits(
            isSelected ? .isSelected : AccessibilityTraits()
        )
    }

    private var footerText: String {
        let selected = selectedWeekdays
            .filter { shortDays.indices.contains($0) }
            .sorted()
            .map { shortDays[$0] }
        if selected.isEmpty {
            return "次回の到着時に一度だけお知らせします。"
        }
        return "\(selected.joined(separator: "・"))曜日に到着をお知らせします。"
    }
}
