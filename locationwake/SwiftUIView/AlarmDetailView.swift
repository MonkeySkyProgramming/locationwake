import SwiftUI
import MapKit
import AVFoundation

struct AlarmDetailView: View {
    private let alarmID: String
    var coordinate: CLLocationCoordinate2D
    var placeName: String?

    @State private var alarmName: String = ""
    @State private var selectedCoordinate: CLLocationCoordinate2D
    @State private var radius: Double = Alarm.defaultGeofenceRadius
    @State private var isSoundEnabled: Bool = true
    @State private var selectedSound: String = "未選択"
    @State private var repeatWeekdays: Set<Int> = []
    @State private var cameraPosition: MapCameraPosition
    @State private var isVibrationEnabled: Bool = true
    @State private var isAlarmLimitAlertPresented = false
    @State private var monitoringFailure: String?
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var navigationModel: NavigationModel
    @EnvironmentObject var viewModel: AlarmListViewModel

    init(alarm: Alarm) {
        let coordinate = CLLocationCoordinate2D(
            latitude: alarm.location?.latitude ?? 0,
            longitude: alarm.location?.longitude ?? 0
        )
        self.alarmID = alarm.id
        self.coordinate = coordinate
        self.placeName = alarm.name
        _selectedCoordinate = State(initialValue: coordinate)
        _alarmName = State(initialValue: alarm.name)
        let geofenceRadius = alarm.geofenceRadius ?? Alarm.defaultGeofenceRadius
        _radius = State(initialValue: geofenceRadius)
        _isSoundEnabled = State(initialValue: alarm.isSoundEnabled)
        _selectedSound = State(initialValue: alarm.sound)
        _repeatWeekdays = State(initialValue: Set(alarm.repeatWeekdays ?? []))
        _cameraPosition = State(initialValue: .region(MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: geofenceRadius * 3.2,
            longitudinalMeters: geofenceRadius * 3.2
        )))
        _isVibrationEnabled = State(initialValue: alarm.isVibrationEnabled)
    }

    var body: some View {
        VStack(spacing: 0) {
            AppNavigationHeader(title: "アラームを編集", showsBackButton: true, backAction: {
                dismiss()
            }) {
                AppSaveButton {
                    saveCurrentAlarm()
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    AppSectionTitle(title: "アラーム名")
                        .padding(.top, 18)
                        .padding(.bottom, 8)
                    AppCard {
                        HStack(spacing: 14) {
                            Image(systemName: "tag")
                                .font(.system(size: 21, weight: .medium))
                                .foregroundStyle(AppDesign.tint)
                            TextField("アラーム名を入力", text: $alarmName)
                                .font(.system(size: 17))
                            if !alarmName.isEmpty {
                                Button {
                                    alarmName = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 56)
                    }
                    .padding(.horizontal, AppDesign.horizontalPadding)

                    AppSectionTitle(title: "位置情報")
                        .padding(.top, 22)
                        .padding(.bottom, 8)
                    AppCard {
                        VStack(spacing: 0) {
                            Map(position: $cameraPosition) {
                                MapCircle(center: selectedCoordinate, radius: radius)
                                    .foregroundStyle(AppDesign.tint.opacity(0.22))
                                    .stroke(AppDesign.tint, lineWidth: 2)
                                Marker(alarmName.isEmpty ? "目的地" : alarmName, coordinate: selectedCoordinate)
                                    .tint(AppDesign.tint)
                            }
                            .frame(height: 214)
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .padding(10)
                            Divider()
                            HStack(spacing: 12) {
                                Image(systemName: "mappin")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(AppDesign.tint)
                                Text(String(format: "%.6f° N, %.6f° E", selectedCoordinate.latitude, selectedCoordinate.longitude))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                            .font(.system(size: 15))
                            .padding(.horizontal, 16)
                            .frame(height: 52)
                        }
                    }
                    .padding(.horizontal, AppDesign.horizontalPadding)
                    .onChange(of: radius) { _, newValue in
                        cameraPosition = .region(MKCoordinateRegion(
                            center: selectedCoordinate,
                            latitudinalMeters: newValue * 3.2,
                            longitudinalMeters: newValue * 3.2
                        ))
                    }

                    AppSectionTitle(title: "到着範囲")
                        .padding(.top, 22)
                        .padding(.bottom, 8)
                    AppCard {
                        VStack(spacing: 4) {
                            HStack(spacing: 14) {
                                Image(systemName: "scope")
                                    .font(.system(size: 23, weight: .medium))
                                    .foregroundStyle(AppDesign.tint)
                                Slider(value: $radius, in: Alarm.minimumGeofenceRadius...Alarm.maximumGeofenceRadius, step: 50)
                                Text("\(Int(radius)) m")
                                    .font(.system(size: 17))
                                    .frame(width: 62, alignment: .trailing)
                            }
                            HStack {
                                Text("50")
                                Spacer()
                                Text("150")
                                Spacer()
                                Text("300")
                                Spacer()
                                Text("500")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 39)
                            .padding(.trailing, 66)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 90)
                    }
                    .padding(.horizontal, AppDesign.horizontalPadding)

                    if let monitoringFailure {
                        Text(monitoringFailure)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                    }

                    AppSectionTitle(title: "通知")
                        .padding(.top, 22)
                        .padding(.bottom, 8)
                    AppCard {
                        VStack(spacing: 0) {
                            AlarmSettingToggleRow(icon: "bell", title: "音を鳴らす", isOn: $isSoundEnabled)
                            Divider().padding(.leading, 58)
                            AlarmSettingToggleRow(icon: "iphone.gen3.radiowaves.left.and.right", title: "バイブレーション", isOn: $isVibrationEnabled)
                            Divider().padding(.leading, 58)
                            NavigationLink(destination: SoundSelectionView(selectedSound: $selectedSound)) {
                                AlarmSettingNavigationRow(icon: "music.note", title: "サウンド", value: selectedSound)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, AppDesign.horizontalPadding)

                    AppSectionTitle(title: "繰り返し")
                        .padding(.top, 22)
                        .padding(.bottom, 8)
                    AppCard {
                        NavigationLink(destination: RepeatWeekdaySelectionView(selectedWeekdays: $repeatWeekdays)) {
                            AlarmSettingNavigationRow(
                                icon: "arrow.triangle.2.circlepath",
                                title: "繰り返し",
                                value: weekdaySummary
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, AppDesign.horizontalPadding)

                    AdScrollClearance()
                }
            }
            .tint(AppDesign.tint)
            .background(AppDesign.background)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .alert("アラームを追加できません", isPresented: $isAlarmLimitAlertPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("アラームは最大\(Alarm.maximumSavedAlarms)件まで登録できます。不要なアラームを削除してください。")
        }
        .onAppear {
            monitoringFailure = UserDefaults.standard.string(forKey: "MonitoringFailure_\(alarmID)")
        }
        .navigationBarBackButtonHidden(true)
    }

    func saveCurrentAlarm() {
        let newAlarm = Alarm(
            id: alarmID,
            name: alarmName,
            repeatWeekdays: Array(repeatWeekdays).sorted(),
            sound: selectedSound,
            isAlarmEnabled: true,
            isSoundEnabled: isSoundEnabled,
            isVibrationEnabled: isVibrationEnabled,
            location: Location(latitude: selectedCoordinate.latitude, longitude: selectedCoordinate.longitude),
            radius: Alarm.normalizedRadius(radius)
        )

        // Debug print
        print("🔍 保存するアラーム:")
        print("名前: \(newAlarm.name)")
        print("繰り返し: \(newAlarm.repeatWeekdays ?? [])")
        print("音: \(newAlarm.sound)")
        print("有効: \(newAlarm.isAlarmEnabled), 音有効: \(newAlarm.isSoundEnabled)")
        print("バイブレーション有効: \(newAlarm.isVibrationEnabled)")
        if let location = newAlarm.location {
            print("位置: 緯度 \(location.latitude), 経度 \(location.longitude)")
        } else {
            print("位置情報が設定されていません")
        }
        print("半径: \(newAlarm.radius ?? 0)")

        let allAlarms = loadSavedAlarms()
        print("📦 現在保存されているアラーム一覧:")
        for (i, alarm) in allAlarms.enumerated() {
            print("🔔 [\(i)] \(alarm.name), 繰り返し: \(alarm.repeatWeekdays ?? []), 音: \(alarm.sound), 緯度: \(alarm.location?.latitude ?? 0), 経度: \(alarm.location?.longitude ?? 0), 半径: \(alarm.radius ?? 0)")
        }

        let skipTimestampKey = "SkipTriggerAt_\(newAlarm.id)"
        UserDefaults.standard.set(Date(), forKey: skipTimestampKey)

        guard saveAlarmSetting(newAlarm) else {
            isAlarmLimitAlertPresented = true
            return
        }
        viewModel.loadAlarms()
        navigationModel.path = []
    }

    private var weekdaySummary: String {
        let names = ["日", "月", "火", "水", "木", "金", "土"]
        guard !repeatWeekdays.isEmpty else { return "繰り返さない" }
        return repeatWeekdays.sorted().map { names[$0] }.joined(separator: "・")
    }

    private var monitoringMethodDescription: String? {
        guard let geofenceMaximum = LocationManager.shared.maximumGeofenceRadius else {
            return "この設定では現在地を確認して到着をお知らせするため、電池の減りが早くなることがあります。"
        }
        let roundedMaximum = Int(geofenceMaximum)
        if radius <= geofenceMaximum {
            return nil
        }
        return "この端末では\(roundedMaximum)mを超える設定のため、電池の減りが早くなることがあります。"
    }
    
    func saveAlarmSetting(_ alarm: Alarm) -> Bool {
        var savedAlarms = loadSavedAlarms()
        let isExistingAlarm = savedAlarms.contains(where: { $0.id == alarm.id })
        guard isExistingAlarm || savedAlarms.count < Alarm.maximumSavedAlarms else {
            return false
        }
        // Insert geofence check and update hasTriggeredUntilExit before saving
        let manager: CLLocationManager = LocationManager.shared.locationManager
        let radius = alarm.geofenceRadius ?? Alarm.defaultGeofenceRadius
        if let userLocation = manager.location,
           LocationManager.isUsableLocation(
               userLocation,
               maximumHorizontalAccuracy: LocationManager.maximumHorizontalAccuracy(for: radius)
           ) {
            let center = CLLocation(latitude: alarm.location?.latitude ?? 0, longitude: alarm.location?.longitude ?? 0)
            let current = CLLocation(
                latitude: userLocation.coordinate.latitude,
                longitude: userLocation.coordinate.longitude
            )
            let distance = current.distance(from: center)
            let isInside = distance <= radius
            var updatedAlarm = alarm
            if updatedAlarm.id.isEmpty {
                updatedAlarm.id = UUID().uuidString
            }
            updatedAlarm.hasTriggeredUntilExit = isInside
            if let index = savedAlarms.firstIndex(where: { $0.id == updatedAlarm.id }) {
                savedAlarms[index] = updatedAlarm
            } else {
                var newAlarm = updatedAlarm
                if newAlarm.id.isEmpty {
                    newAlarm.id = UUID().uuidString
                }
                savedAlarms.append(newAlarm)
            }
        } else {
            // Use id-based matching instead of name-based matching
            if let index = savedAlarms.firstIndex(where: { $0.id == alarm.id }) {
                savedAlarms[index] = alarm
            } else {
                var newAlarm = alarm
                if newAlarm.id.isEmpty {
                    newAlarm.id = UUID().uuidString
                }
                savedAlarms.append(newAlarm)
            }
        }
        AlarmStore.save(savedAlarms)
        return true
    }

    func loadSavedAlarms() -> [Alarm] {
        AlarmStore.load()
    }
}

private struct AlarmSettingToggleRow: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(AppDesign.tint)
                .frame(width: 28)
            Text(title)
                .font(.system(size: 17))
            Spacer()
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .tint(AppDesign.tint)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }
}

private struct AlarmSettingNavigationRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(AppDesign.tint)
                .frame(width: 28)
            Text(title)
                .font(.system(size: 17))
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .contentShape(Rectangle())
    }
}

// 簡易的な音選択ビュー
struct SoundSelectionView: View {
    @Binding var selectedSound: String
    let sounds = ["kind", "modan", "siren"]
    @State private var audioPlayer: AVAudioPlayer?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            AppNavigationHeader(title: "サウンド", showsBackButton: true) {
                dismiss()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    AppSectionTitle(title: "アラーム音")
                        .padding(.top, 34)
                        .padding(.bottom, 8)
                    AppCard {
                        VStack(spacing: 0) {
                            ForEach(Array(sounds.enumerated()), id: \.element) { index, sound in
                                HStack(spacing: 14) {
                                    Button {
                                        selectedSound = sound
                                    } label: {
                                        HStack(spacing: 14) {
                                            Image(systemName: "speaker.wave.2")
                                                .font(.system(size: 21, weight: .medium))
                                                .foregroundStyle(AppDesign.tint)
                                                .frame(width: 28)
                                            Text(sound)
                                                .font(.system(size: 18))
                                                .foregroundStyle(.primary)
                                            if sound == selectedSound {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 18, weight: .semibold))
                                                    .foregroundStyle(AppDesign.tint)
                                            }
                                            Spacer()
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        preview(sound)
                                    } label: {
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(AppDesign.tint)
                                            .frame(width: 36, height: 36)
                                            .overlay {
                                                Circle().stroke(AppDesign.tint, lineWidth: 1.5)
                                            }
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("\(sound)を試聴")
                                }
                                .padding(.horizontal, 16)
                                .frame(height: 66)

                                if index < sounds.count - 1 {
                                    Divider().padding(.leading, 58)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, AppDesign.horizontalPadding)

                    Text("タップすると試聴できます")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)
                        .padding(.top, 12)

                    AdScrollClearance()
                }
            }
        }
        .background(AppDesign.background)
        .navigationBarBackButtonHidden(true)
    }

    private func preview(_ sound: String) {
        guard let url = Bundle.main.url(forResource: sound, withExtension: "mp3") else { return }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                audioPlayer?.stop()
            }
        } catch {
            print("Error playing sound: \(error.localizedDescription)")
        }
    }
}

struct RepeatWeekdaySelectionView: View {
    @Binding var selectedWeekdays: Set<Int>
    let days = ["日曜日", "月曜日", "火曜日", "水曜日", "木曜日", "金曜日", "土曜日"]
    let shortDays = ["日", "月", "火", "水", "木", "金", "土"]
    @Environment(\.dismiss) private var dismiss

    private var selectedDaySummary: String {
        let selected = selectedWeekdays.sorted().map { shortDays[$0] }
        return selected.isEmpty ? "繰り返さない" : selected.joined(separator: "・") + "曜日"
    }

    var body: some View {
        VStack(spacing: 0) {
            AppNavigationHeader(title: "繰り返し", showsBackButton: true) {
                dismiss()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    AppSectionTitle(title: "繰り返し")
                        .padding(.top, 34)
                        .padding(.bottom, 8)
                    AppCard {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack(spacing: 12) {
                                Image(systemName: "repeat")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(AppDesign.tint)
                                    .frame(width: 34, height: 34)
                                    .background(AppDesign.tint.opacity(0.12), in: Circle())

                                VStack(alignment: .leading, spacing: 3) {
                                    Text("繰り返し")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    Text(selectedDaySummary)
                                        .font(.system(size: 15))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if selectedWeekdays.isEmpty {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundStyle(AppDesign.tint)
                                        .accessibilityLabel("繰り返さない")
                                } else {
                                    Button("解除") {
                                        selectedWeekdays.removeAll()
                                    }
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(AppDesign.tint)
                                    .buttonStyle(.plain)
                                    .accessibilityHint("曜日の繰り返しを解除します")
                                }
                            }

                            Divider()

                            Text("曜日を選択")
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)

                            HStack(spacing: 0) {
                                ForEach(0..<days.count, id: \.self) { index in
                                    Button {
                                        if selectedWeekdays.contains(index) {
                                            selectedWeekdays.remove(index)
                                        } else {
                                            selectedWeekdays.insert(index)
                                        }
                                    } label: {
                                        Text(shortDays[index])
                                            .font(.system(size: 16, weight: .semibold))
                                            .frame(width: 40, height: 40)
                                            .foregroundStyle(selectedWeekdays.contains(index) ? .white : .primary)
                                            .background(
                                                selectedWeekdays.contains(index) ? AppDesign.tint : Color(uiColor: .tertiarySystemFill),
                                                in: Circle()
                                            )
                                            .overlay {
                                                Circle()
                                                    .stroke(
                                                        selectedWeekdays.contains(index) ? Color.clear : Color.secondary.opacity(0.12),
                                                        lineWidth: 1
                                                    )
                                            }
                                    }
                                    .buttonStyle(.plain)
                                    .frame(maxWidth: .infinity)
                                    .accessibilityLabel(days[index])
                                    .accessibilityValue(selectedWeekdays.contains(index) ? "選択済み" : "未選択")
                                }
                            }
                        }
                        .padding(16)
                    }
                    .padding(.horizontal, 9)

                    Text(selectedWeekdays.isEmpty ? "繰り返さない場合は、次回の到着時に一度だけお知らせします。" : "塗りつぶされた曜日に、到着をお知らせします。")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)
                        .padding(.top, 14)

                    AdScrollClearance()
                }
            }
        }
        .background(AppDesign.background)
        .navigationBarBackButtonHidden(true)
    }
}

// 曜日選択のビュー
struct WeekdayPickerView: View {
    @Binding var selectedWeekdays: Set<Int>
    let days = ["日", "月", "火", "水", "木", "金", "土"]

    var body: some View {
        HStack {
            ForEach(0..<7, id: \.self) { i in
                Button(action: {
                    if selectedWeekdays.contains(i) {
                        selectedWeekdays.remove(i)
                    } else {
                        selectedWeekdays.insert(i)
                    }
                    print("タップした曜日: \(i)")
                    print("現在の選択: \(selectedWeekdays.sorted())")
                }) {
                    Text(days[i])
                        .font(.caption)
                        .padding(8)
                        .background(selectedWeekdays.contains(i) ? Color.accentColor : Color.gray.opacity(0.3))
                        .foregroundColor(.white)
                        .clipShape(Circle())
                }
            }
        }
        .padding(.vertical, 4)
        .onChange(of: selectedWeekdays) { _, newValue in
            print("選択された曜日: \(newValue.sorted())")
        }
    }
}

struct IdentifiableCoordinate: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}
