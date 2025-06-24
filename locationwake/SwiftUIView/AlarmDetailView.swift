import SwiftUI
import MapKit
import AVFoundation

struct AlarmDetailView: View {
    var coordinate: CLLocationCoordinate2D
    var placeName: String?

    @State private var alarmName: String = ""
    @State private var selectedCoordinate: CLLocationCoordinate2D
    @State private var radius: Double = 3000
    @State private var isSoundEnabled: Bool = true
    @State private var selectedSound: String = "未選択"
    @State private var repeatWeekdays: Set<Int> = []
    @State private var mapRegion: MKCoordinateRegion
    @Environment(\.dismiss) var dismiss

    init(coordinate: CLLocationCoordinate2D, placeName: String?) {
        self.coordinate = coordinate
        self.placeName = placeName
        _selectedCoordinate = State(initialValue: coordinate)
        _alarmName = State(initialValue: placeName ?? "")
        _mapRegion = State(initialValue: MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 3000 / 80000, longitudeDelta: 3000 / 80000)))
    }

    var body: some View {
        Form {
            Section(header: Text("アラーム名")) {
                TextField("アラーム名を入力", text: $alarmName)
            }

            Section(header: Text("位置情報")) {
                Map(coordinateRegion: $mapRegion,
                    annotationItems: [IdentifiableCoordinate(coordinate: selectedCoordinate)]) { item in
                    MapAnnotation(coordinate: item.coordinate) {
                        Image(systemName: "mappin")
                            .foregroundColor(.red)
                    }
                }
                .overlay(
                    GeometryReader { geo in
                        let mapWidth = geo.size.width
                        let metersPerPoint = (radius * 2) / (mapWidth / 1.2)  // Remove padding effect
                        let visualRadius = radius / metersPerPoint

                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.2))
                                .frame(width: visualRadius * 2, height: visualRadius * 2)
                            Circle()
                                .stroke(Color.blue, lineWidth: 2)
                                .frame(width: visualRadius * 2, height: visualRadius * 2)
                        }
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    }
                )
                .aspectRatio(1, contentMode: .fit)
                .listRowInsets(EdgeInsets())
                .onChange(of: radius) { newValue in
                    let paddingFactor = 1.2  // Add 20% extra margin
                    mapRegion = MKCoordinateRegion(
                        center: selectedCoordinate,
                        latitudinalMeters: newValue * 2 * paddingFactor,
                        longitudinalMeters: newValue * 2 * paddingFactor
                    )
                }
                Text("緯度: \(selectedCoordinate.latitude), 経度: \(selectedCoordinate.longitude)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Section(header: Text("半径")) {
                Slider(value: $radius, in: 100...10000, step: 100)
                Text("\(Int(radius)) メートル")
            }

            Section(header: Text("アラーム音")) {
                Toggle("音を鳴らす", isOn: $isSoundEnabled)
                NavigationLink(destination: SoundSelectionView(selectedSound: $selectedSound)) {
                    HStack {
                        Text("選択中の音")
                        Spacer()
                        Text(selectedSound)
                            .foregroundColor(.gray)
                    }
                }
            }

            Section(header: Text("繰り返し")) {
                NavigationLink(destination: RepeatWeekdaySelectionView(selectedWeekdays: $repeatWeekdays)) {
                    HStack {
                        Text("選択された曜日")
                        Spacer()
                        Text(repeatWeekdays.sorted().map { ["日","月","火","水","木","金","土"][$0] }.joined(separator: ", "))
                            .foregroundColor(.gray)
                    }
                }
            }

            // Removed the "保存" button section from the bottom of the form
        }
        .navigationTitle("アラーム設定")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("保存") {
                    let newAlarm = Alarm(
                        name: alarmName,
                        repeatWeekdays: Array(repeatWeekdays).sorted(),
                        sound: selectedSound,
                        isAlarmEnabled: true,
                        isSoundEnabled: isSoundEnabled,
                        location: Location(latitude: selectedCoordinate.latitude, longitude: selectedCoordinate.longitude),
                        radius: radius
                    )

                    saveAlarmSetting(newAlarm)
                    DispatchQueue.main.async {
                        dismiss()
                    }
                }
            }
        }
    }
    
    func saveAlarmSetting(_ alarm: Alarm) {
        var savedAlarms = loadSavedAlarms()
        if let index = savedAlarms.firstIndex(where: { $0.name == alarm.name }) {
            savedAlarms[index] = alarm
        } else {
            savedAlarms.append(alarm)
        }

        if let encoded = try? JSONEncoder().encode(savedAlarms) {
            UserDefaults.standard.set(encoded, forKey: "SavedAlarms")
        }
    }

    func loadSavedAlarms() -> [Alarm] {
        if let savedData = UserDefaults.standard.data(forKey: "SavedAlarms"),
           let decoded = try? JSONDecoder().decode([Alarm].self, from: savedData) {
            return decoded
        }
        return []
    }
}

// 簡易的な音選択ビュー
struct SoundSelectionView: View {
    @Binding var selectedSound: String
    let sounds = ["kind", "modan", "siren"]
    @State private var audioPlayer: AVAudioPlayer?

    var body: some View {
        List {
            ForEach(sounds, id: \.self) { sound in
                HStack {
                    Text(sound)
                    Spacer()
                    if sound == selectedSound {
                        Image(systemName: "checkmark")
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedSound = sound
                    if let url = Bundle.main.url(forResource: sound, withExtension: "mp3") {
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
            }
        }
        .navigationTitle("サウンド選択")
    }
}

struct RepeatWeekdaySelectionView: View {
    @Binding var selectedWeekdays: Set<Int>
    let days = ["日", "月", "火", "水", "木", "金", "土"]

    var body: some View {
        List {
            ForEach(0..<days.count, id: \.self) { index in
                HStack {
                    Text(days[index])
                    Spacer()
                    if selectedWeekdays.contains(index) {
                        Image(systemName: "checkmark")
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if selectedWeekdays.contains(index) {
                        selectedWeekdays.remove(index)
                    } else {
                        selectedWeekdays.insert(index)
                    }
                    print("タップした曜日: \(index)")
                    print("現在の選択: \(selectedWeekdays.sorted())")
                }
            }
        }
        .navigationTitle("繰り返し設定")
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
        .onChange(of: selectedWeekdays) { newValue in
            print("選択された曜日: \(newValue.sorted())")
        }
    }
}

struct IdentifiableCoordinate: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}
