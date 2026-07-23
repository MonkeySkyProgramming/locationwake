import CoreLocation
import Foundation

protocol LocationManagerDelegate: AnyObject {
    func didUpdateAlarmStatus(_ alarm: Alarm)
}

enum AlarmTriggerBlockReason: Equatable {
    case disabled
    case weekdayMismatch
    case initialStatePending
    case triggeredUntilExit
    // 旧版とのデータ互換性を保つために残す。現行の発火経路では使用しない。
    case memorySkip
    case storedSkipFlag
    case savedTooRecently
}

enum AlarmProximityAction: Equatable {
    case none
    case trigger
    case resetAfterExit
}

struct AlarmTriggerPolicy {
    static let saveSkipInterval: TimeInterval = 10

    static func weekdayIndex(for date: Date, calendar: Calendar = .current) -> Int {
        calendar.component(.weekday, from: date) - 1
    }

    static func blockReason(
        for alarm: Alarm,
        weekday: Int,
        hasMemorySkip: Bool = false,
        hasStoredSkipFlag: Bool = false,
        savedAt: Date? = nil,
        now: Date = Date()
    ) -> AlarmTriggerBlockReason? {
        if hasMemorySkip {
            return .memorySkip
        }
        if hasStoredSkipFlag {
            return .storedSkipFlag
        }
        if let savedAt, now.timeIntervalSince(savedAt) < saveSkipInterval {
            return .savedTooRecently
        }
        if alarm.needsInitialStateCheck {
            return .initialStatePending
        }
        if alarm.hasTriggeredUntilExit {
            return .triggeredUntilExit
        }
        if !alarm.isAlarmEnabled {
            return .disabled
        }
        if let repeatDays = alarm.repeatWeekdays,
           !repeatDays.isEmpty,
           !repeatDays.contains(weekday) {
            return .weekdayMismatch
        }
        return nil
    }

    static func proximityAction(
        for alarm: Alarm,
        distance: CLLocationDistance,
        radius: CLLocationDistance,
        weekday: Int
    ) -> AlarmProximityAction {
        if alarm.needsInitialStateCheck {
            return .none
        }
        if alarm.hasTriggeredUntilExit {
            return distance > radius ? .resetAfterExit : .none
        }
        guard !alarm.hasTriggered,
              blockReason(for: alarm, weekday: weekday) == nil,
              distance <= radius else {
            return .none
        }
        return .trigger
    }
}

enum AlarmMonitoringState: String, Equatable {
    case requested
    case active
    case retrying
    case failed
    case capacityExceeded
    case continuous
}

final class LocationManager: NSObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    static let maximumMonitoredGeofences = 20

    weak var delegate: LocationManagerDelegate?
    public var locationManager: CLLocationManager
    var alarms: [Alarm] = []

    private var monitoringTimer: Timer?
    private var authorizationCheckTimer: Timer?
    private var hasRestoredSavedAlarms = false
    private var startRequestedIDs = Set<String>()
    private var retryCounts: [String: Int] = [:]
    private var retryWorkItems: [String: DispatchWorkItem] = [:]
    private var reconciliationWorkItem: DispatchWorkItem?

    private let alarmScheduler = AlarmScheduler()

    private enum MonitoringDefaultsKey {
        static func state(_ alarmID: String) -> String { "MonitoringState_\(alarmID)" }
        static func failure(_ alarmID: String) -> String { "MonitoringFailure_\(alarmID)" }
    }

    var maximumGeofenceRadius: Double? {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            return nil
        }
        let maximumDistance = locationManager.maximumRegionMonitoringDistance
        guard maximumDistance > 0 else { return nil }
        return min(maximumDistance, Alarm.maximumGeofenceRadius)
    }

    override init() {
        locationManager = CLLocationManager()
        super.init()
        locationManager.delegate = self

        guard !AppRuntime.shouldSuppressExternalSideEffects else { return }

        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = true
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 50
        locationManager.activityType = .otherNavigation
        locationManagerDidChangeAuthorization(locationManager)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCalendarDayChange),
            name: .NSCalendarDayChanged,
            object: nil
        )

#if DEBUG
        startMonitoringGeofenceStatus()
#endif
        startAuthorizationStatusCheck()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        reconciliationWorkItem?.cancel()
        retryWorkItems.values.forEach { $0.cancel() }
    }

    func restoreSavedAlarms(reason: String) {
        alarms = AlarmStore.load()
        hasRestoredSavedAlarms = true
#if DEBUG
        print("ℹ️ event=alarmsRestored reason=\(reason) count=\(alarms.count)")
#endif
        AlarmActivityCenter.shared.presentCurrentAlarmIfNeeded()
        startMonitoring(alarms: alarms)
    }

    /// 保存済みアラームと現在の監視状態を差分同期する。
    ///
    /// 新規保存・再有効化・目的地変更は `needsInitialStateCheck` の間は発火せず、
    /// 現在地またはCore Locationの領域状態から「退出待ち」か「監視中」へ解決する。
    func startMonitoring(alarms: [Alarm], skipImmediateCheck: Bool = false) {
        self.alarms = Alarm.normalizedForPersistence(alarms)
        updateContinuousLocationMonitoring(for: locationManager.authorizationStatus)

        if !skipImmediateCheck {
            if let currentLocation = locationManager.location {
                evaluateAlarms(at: currentLocation)
            }
            requestLocationIfInitialStateIsPending()
        }

        synchronizeGeofences()
    }

    static func geofenceEligibleAlarms(from alarms: [Alarm]) -> [Alarm] {
        alarms.filter {
            $0.isAlarmEnabled && $0.location != nil && $0.geofenceRadius != nil
        }
    }

    static func preparedForInitialStateCheck(
        _ alarm: Alarm,
        currentLocation: CLLocation?
    ) -> Alarm {
        var prepared = alarm
        prepared.prepareForInitialStateCheck()

        guard let currentLocation,
              let destination = prepared.location,
              let radius = prepared.geofenceRadius,
              isUsableLocation(
                  currentLocation,
                  maximumHorizontalAccuracy: maximumHorizontalAccuracy(for: radius)
              ) else {
            return prepared
        }

        let target = CLLocation(
            latitude: destination.latitude,
            longitude: destination.longitude
        )
        prepared.resolveInitialState(
            isInside: currentLocation.distance(from: target) <= radius
        )
        return prepared
    }

    static func monitoringState(
        for alarmID: String,
        defaults: UserDefaults = .standard
    ) -> AlarmMonitoringState? {
        guard let rawValue = defaults.string(
            forKey: MonitoringDefaultsKey.state(alarmID)
        ) else {
            return nil
        }
        return AlarmMonitoringState(rawValue: rawValue)
    }

    private func geofenceRegion(for alarm: Alarm) -> CLCircularRegion? {
        guard usesGeofence(for: alarm),
              let location = alarm.location,
              let radius = alarm.geofenceRadius else {
            return nil
        }

        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(
                latitude: location.latitude,
                longitude: location.longitude
            ),
            radius: radius,
            identifier: alarm.id
        )
        region.notifyOnEntry = true
        region.notifyOnExit = true
        return region
    }

    private func usesGeofence(for alarm: Alarm) -> Bool {
        guard let radius = alarm.geofenceRadius,
              let maximumGeofenceRadius else {
            return false
        }
        return radius <= maximumGeofenceRadius
    }

    private func geofenceAlarms(from alarms: [Alarm]) -> [Alarm] {
        Self.geofenceEligibleAlarms(from: alarms).filter(usesGeofence)
    }

    private func synchronizeGeofences() {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            for alarm in Self.geofenceEligibleAlarms(from: alarms) {
                setMonitoringState(.failed, alarmID: alarm.id, failure: "この端末では到着範囲の監視を利用できません。")
            }
            return
        }

        let desiredAlarms = geofenceAlarms(from: alarms)
        let desiredByID = Dictionary(uniqueKeysWithValues: desiredAlarms.map { ($0.id, $0) })
        let currentRegions = locationManager.monitoredRegions
        var unchangedIDs = Set<String>()
        var regionsToStop = [CLRegion]()

        for region in currentRegions {
            guard let alarm = desiredByID[region.identifier],
                  let expectedRegion = geofenceRegion(for: alarm),
                  sameConfiguration(region, expectedRegion) else {
                regionsToStop.append(region)
                continue
            }
            unchangedIDs.insert(alarm.id)
            if alarm.needsInitialStateCheck {
                locationManager.requestState(for: region)
            }
        }

        if !regionsToStop.isEmpty {
            for region in regionsToStop {
                locationManager.stopMonitoring(for: region)
#if DEBUG
                print("ℹ️ event=monitoringStopRequested alarmID=\(region.identifier)")
#endif
            }
            scheduleReconciliation(after: 0.5)
            return
        }

        for alarm in Self.geofenceEligibleAlarms(from: alarms) where !usesGeofence(for: alarm) {
            setMonitoringState(.continuous, alarmID: alarm.id)
        }

        let alarmsToStart = desiredAlarms.filter {
            !unchangedIDs.contains($0.id) && !startRequestedIDs.contains($0.id)
        }
        let reservedCount = currentRegions.count + startRequestedIDs.count
        let remainingCapacity = max(
            0,
            Self.maximumMonitoredGeofences - reservedCount
        )
        let alarmsWithinCapacity = Array(alarmsToStart.prefix(remainingCapacity))
        let excludedAlarms = alarmsToStart.dropFirst(remainingCapacity)

        for alarm in excludedAlarms {
            setMonitoringState(
                .capacityExceeded,
                alarmID: alarm.id,
                failure: "同時に監視できる到着範囲の上限に達しています。"
            )
        }

        for alarm in alarmsWithinCapacity {
            guard let region = geofenceRegion(for: alarm) else { continue }
            startRequestedIDs.insert(alarm.id)
            setMonitoringState(.requested, alarmID: alarm.id)
            locationManager.startMonitoring(for: region)
#if DEBUG
            print("ℹ️ event=monitoringStartRequested alarmID=\(alarm.id)")
#endif
        }
    }

    private func scheduleReconciliation(after delay: TimeInterval) {
        reconciliationWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.synchronizeGeofences()
        }
        reconciliationWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func sameConfiguration(
        _ currentRegion: CLRegion,
        _ expectedRegion: CLCircularRegion
    ) -> Bool {
        guard let currentRegion = currentRegion as? CLCircularRegion else {
            return false
        }
        return currentRegion.identifier == expectedRegion.identifier
            && abs(currentRegion.center.latitude - expectedRegion.center.latitude) < 0.000_001
            && abs(currentRegion.center.longitude - expectedRegion.center.longitude) < 0.000_001
            && abs(currentRegion.radius - expectedRegion.radius) < 0.5
            && currentRegion.notifyOnEntry == expectedRegion.notifyOnEntry
            && currentRegion.notifyOnExit == expectedRegion.notifyOnExit
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard alarms.contains(where: { $0.id == region.identifier }) else { return }

        if let index = alarms.firstIndex(where: { $0.id == region.identifier }),
           alarms[index].needsInitialStateCheck {
            alarms[index].resolveInitialState(isInside: true)
            persistAlarmStateChange(at: index)
            return
        }

        triggerAlarm(alarmID: region.identifier)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let index = alarms.firstIndex(where: { $0.id == region.identifier }) else {
            return
        }
        alarms[index].resolveInitialState(isInside: false)
        persistAlarmStateChange(at: index)
    }

    func locationManager(
        _ manager: CLLocationManager,
        didDetermineState state: CLRegionState,
        for region: CLRegion
    ) {
        guard let index = alarms.firstIndex(where: { $0.id == region.identifier }) else {
            return
        }

        switch state {
        case .inside:
            if alarms[index].needsInitialStateCheck {
                alarms[index].resolveInitialState(isInside: true)
                persistAlarmStateChange(at: index)
            } else {
                triggerAlarm(alarmID: region.identifier)
            }
        case .outside:
            if alarms[index].needsInitialStateCheck
                || alarms[index].hasTriggeredUntilExit {
                alarms[index].resolveInitialState(isInside: false)
                persistAlarmStateChange(at: index)
            }
        case .unknown:
            requestLocationIfInitialStateIsPending()
        @unknown default:
            requestLocationIfInitialStateIsPending()
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didStartMonitoringFor region: CLRegion
    ) {
        startRequestedIDs.remove(region.identifier)
        retryCounts[region.identifier] = 0
        retryWorkItems[region.identifier]?.cancel()
        retryWorkItems[region.identifier] = nil
        setMonitoringState(.active, alarmID: region.identifier)
        manager.requestState(for: region)
        synchronizeGeofences()
    }

    func locationManager(
        _ manager: CLLocationManager,
        monitoringDidFailFor region: CLRegion?,
        withError error: Error
    ) {
        guard let alarmID = region?.identifier else {
#if DEBUG
            print("❌ event=monitoringFailed alarmID=unknown reason=\(error.localizedDescription)")
#endif
            return
        }
        startRequestedIDs.remove(alarmID)
        let attempt = retryCounts[alarmID, default: 0] + 1
        retryCounts[alarmID] = attempt

        guard attempt <= 3,
              alarms.contains(where: {
                  $0.id == alarmID && $0.isAlarmEnabled
              }) else {
            setMonitoringState(
                .failed,
                alarmID: alarmID,
                failure: "到着範囲の監視を開始できませんでした。設定を確認して再度お試しください。"
            )
            return
        }

        setMonitoringState(.retrying, alarmID: alarmID)
        retryWorkItems[alarmID]?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.retryWorkItems[alarmID] = nil
            self?.synchronizeGeofences()
        }
        retryWorkItems[alarmID] = item
        let delay = pow(2.0, Double(attempt - 1))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        evaluateAlarms(at: location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let clError = error as? CLError, clError.code == .locationUnknown else {
#if DEBUG
            print("⚠️ event=locationUpdateFailed reason=\(error.localizedDescription)")
#endif
            return
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        NotificationCenter.default.post(
            name: .locationAuthorizationDidChange,
            object: nil,
            userInfo: ["status": status.rawValue]
        )
        updateContinuousLocationMonitoring(for: status)
        if hasRestoredSavedAlarms {
            synchronizeGeofences()
            requestLocationIfInitialStateIsPending()
        }
    }

    private func evaluateAlarms(at location: CLLocation) {
        var stateChangedIDs = Set<String>()
        var alarmIDsToTrigger = [String]()
        let today = AlarmTriggerPolicy.weekdayIndex(for: Date())

        for snapshot in alarms {
            guard snapshot.isAlarmEnabled,
                  let destination = snapshot.location,
                  let radius = snapshot.geofenceRadius,
                  Self.isUsableLocation(
                      location,
                      maximumHorizontalAccuracy: Self.maximumHorizontalAccuracy(for: radius)
                  ) else {
                continue
            }

            let target = CLLocation(
                latitude: destination.latitude,
                longitude: destination.longitude
            )
            let distance = location.distance(from: target)

            if snapshot.needsInitialStateCheck {
                if let index = alarms.firstIndex(where: { $0.id == snapshot.id }) {
                    alarms[index].resolveInitialState(isInside: distance <= radius)
                    stateChangedIDs.insert(snapshot.id)
                }
                continue
            }

            switch AlarmTriggerPolicy.proximityAction(
                for: snapshot,
                distance: distance,
                radius: radius,
                weekday: today
            ) {
            case .none:
                continue
            case .resetAfterExit:
                if let index = alarms.firstIndex(where: { $0.id == snapshot.id }) {
                    alarms[index].resolveInitialState(isInside: false)
                    stateChangedIDs.insert(snapshot.id)
                }
            case .trigger:
                alarmIDsToTrigger.append(snapshot.id)
            }
        }

        if !stateChangedIDs.isEmpty {
            saveAlarms()
            notifyAlarmUpdates(for: stateChangedIDs)
        }

        for alarmID in alarmIDsToTrigger {
            triggerAlarm(alarmID: alarmID)
        }
        synchronizeGeofences()
    }

    private func triggerAlarm(alarmID: String) {
        guard let index = alarms.firstIndex(where: { $0.id == alarmID }) else {
            return
        }
        let alarm = alarms[index]
        let today = AlarmTriggerPolicy.weekdayIndex(for: Date())
        guard AlarmTriggerPolicy.blockReason(for: alarm, weekday: today) == nil else {
            return
        }

        // 状態を副作用より先に保存し、重複delegateイベントでも一度だけ発火させる。
        if alarms[index].repeatWeekdays?.isEmpty ?? true {
            alarms[index].isAlarmEnabled = false
        }
        alarms[index].hasTriggered = true
        alarms[index].hasTriggeredUntilExit = true
        alarms[index].needsInitialStateCheck = false
        let updatedAlarm = alarms[index]
        saveAlarms()

        let playbackDecision = AlarmActivityCenter.shared.registerArrival(
            for: updatedAlarm
        )
        let shouldRing = playbackDecision == .ring
        alarmScheduler.scheduleAlarm(
            alarm: updatedAlarm,
            isRinging: shouldRing
        )

        if shouldRing {
            if updatedAlarm.isSoundEnabled {
                SoundPlayer.shared.startAlarm(
                    id: updatedAlarm.id,
                    sound: updatedAlarm.sound
                )
            }
            if updatedAlarm.isVibrationEnabled {
                HapticManager.startAlarm(
                    id: updatedAlarm.id,
                    type: .systemVibrate,
                    count: .max,
                    interval: 1
                )
            }
        }

        delegate?.didUpdateAlarmStatus(updatedAlarm)
        NotificationCenter.default.post(name: .alarmUpdated, object: updatedAlarm)
        synchronizeGeofences()
    }

    private func persistAlarmStateChange(at index: Int) {
        let alarm = alarms[index]
        saveAlarms()
        delegate?.didUpdateAlarmStatus(alarm)
        NotificationCenter.default.post(name: .alarmUpdated, object: alarm)
    }

    private func notifyAlarmUpdates(for alarmIDs: Set<String>) {
        for alarm in alarms where alarmIDs.contains(alarm.id) {
            delegate?.didUpdateAlarmStatus(alarm)
            NotificationCenter.default.post(name: .alarmUpdated, object: alarm)
        }
    }

    private func requestLocationIfInitialStateIsPending() {
        guard alarms.contains(where: {
            $0.isAlarmEnabled && $0.needsInitialStateCheck
        }) else {
            return
        }

        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.requestLocation()
        case .notDetermined, .restricted, .denied:
            break
        @unknown default:
            break
        }
    }

    private func setMonitoringState(
        _ state: AlarmMonitoringState,
        alarmID: String,
        failure: String? = nil
    ) {
        let defaults = UserDefaults.standard
        defaults.set(state.rawValue, forKey: MonitoringDefaultsKey.state(alarmID))
        if let failure {
            defaults.set(failure, forKey: MonitoringDefaultsKey.failure(alarmID))
        } else if state == .active || state == .continuous {
            defaults.removeObject(forKey: MonitoringDefaultsKey.failure(alarmID))
        }
        NotificationCenter.default.post(
            name: .alarmMonitoringStatusDidChange,
            object: alarmID
        )
    }

    func saveAlarms() {
        alarms = Alarm.normalizedForPersistence(alarms)
        AlarmStore.save(alarms)
    }

    func stopMonitoringForAlarm(alarm: Alarm) {
        for region in locationManager.monitoredRegions where region.identifier == alarm.id {
            locationManager.stopMonitoring(for: region)
        }
        startRequestedIDs.remove(alarm.id)
        retryWorkItems[alarm.id]?.cancel()
        retryWorkItems[alarm.id] = nil
        retryCounts[alarm.id] = nil
        UserDefaults.standard.removeObject(
            forKey: MonitoringDefaultsKey.state(alarm.id)
        )
        UserDefaults.standard.removeObject(
            forKey: MonitoringDefaultsKey.failure(alarm.id)
        )
        alarmScheduler.cancelAlarm(alarm: alarm)
        scheduleReconciliation(after: 0.5)
    }

    static func shouldRunContinuousLocationMonitoring(
        for status: CLAuthorizationStatus,
        alarms: [Alarm],
        maximumGeofenceRadius: CLLocationDistance?
    ) -> Bool {
        guard status == .authorizedAlways else { return false }
        return geofenceEligibleAlarms(from: alarms).contains { alarm in
            let usesSelectedWeekdays = !(alarm.repeatWeekdays?.isEmpty ?? true)
            guard let maximumGeofenceRadius,
                  let radius = alarm.geofenceRadius else {
                return true
            }
            return usesSelectedWeekdays || radius > maximumGeofenceRadius
        }
    }

    static func maximumHorizontalAccuracy(
        for radius: CLLocationDistance
    ) -> CLLocationAccuracy {
        min(max(radius / 2, 100), 1_000)
    }

    static func isUsableLocation(
        _ location: CLLocation,
        now: Date = Date(),
        maximumAge: TimeInterval = 30,
        maximumHorizontalAccuracy: CLLocationAccuracy
    ) -> Bool {
        location.horizontalAccuracy >= 0
            && location.horizontalAccuracy <= maximumHorizontalAccuracy
            && abs(now.timeIntervalSince(location.timestamp)) <= maximumAge
    }

    private func updateContinuousLocationMonitoring(
        for status: CLAuthorizationStatus
    ) {
        if Self.shouldRunContinuousLocationMonitoring(
            for: status,
            alarms: alarms,
            maximumGeofenceRadius: maximumGeofenceRadius
        ) {
            locationManager.startUpdatingLocation()
        } else {
            locationManager.stopUpdatingLocation()
        }
    }

    func startMonitoringGeofenceStatus() {
        monitoringTimer?.invalidate()
        monitoringTimer = Timer.scheduledTimer(
            withTimeInterval: 30,
            repeats: true
        ) { [weak self] _ in
            self?.printGeodefence()
        }
    }

    func printGeodefence() {
#if DEBUG
        print("現在監視中の領域数: \(locationManager.monitoredRegions.count)")
#endif
    }

    func startAuthorizationStatusCheck() {
        authorizationCheckTimer?.invalidate()
        authorizationCheckTimer = Timer.scheduledTimer(
            withTimeInterval: 60 * 60,
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            NotificationCenter.default.post(
                name: .locationAuthorizationDidChange,
                object: nil,
                userInfo: ["status": self.locationManager.authorizationStatus.rawValue]
            )
        }
    }

    @objc private func handleCalendarDayChange() {
        for region in locationManager.monitoredRegions {
            locationManager.requestState(for: region)
        }
        if let location = locationManager.location {
            evaluateAlarms(at: location)
        } else {
            requestLocationIfInitialStateIsPending()
        }
    }
}

extension Notification.Name {
    static let locationAuthorizationDidChange = Notification.Name(
        "LocationAuthorizationDidChange"
    )
    static let alarmUpdated = Notification.Name("AlarmUpdated")
}
