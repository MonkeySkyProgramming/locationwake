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

enum ArrivalDeliveryCompletionAction: Equatable {
    case acknowledge
    case retry
    case none
}

enum AlarmBoundaryState: Equatable {
    case inside
    case outside
    case uncertain
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
        weekday: Int,
        horizontalAccuracy: CLLocationAccuracy = 0
    ) -> AlarmProximityAction {
        if alarm.needsInitialStateCheck {
            return .none
        }
        let boundaryState = boundaryState(
            distance: distance,
            radius: radius,
            horizontalAccuracy: horizontalAccuracy
        )
        if alarm.hasTriggeredUntilExit {
            return boundaryState == .outside ? .resetAfterExit : .none
        }
        guard !alarm.hasTriggered,
              blockReason(for: alarm, weekday: weekday) == nil,
              boundaryState == .inside else {
            return .none
        }
        return .trigger
    }

    /// GPSの誤差範囲全体が境界の内側／外側に入った時だけ確定する。
    /// 境界付近の曖昧な測位で「退出→再入場」を誤って成立させない。
    static func boundaryState(
        distance: CLLocationDistance,
        radius: CLLocationDistance,
        horizontalAccuracy: CLLocationAccuracy
    ) -> AlarmBoundaryState {
        let accuracy = max(0, horizontalAccuracy)
        if distance + accuracy <= radius {
            return .inside
        }
        if distance - accuracy > radius {
            return .outside
        }
        return .uncertain
    }
}

enum AlarmMonitoringState: String, Equatable {
    case requested
    case active
    case retrying
    case failed
    case capacityExceeded
    case continuous
    case permissionRequired
}

final class LocationManager: NSObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    static let maximumMonitoredGeofences = 20
    static let maximumMonitoringRetryAttempts = 3
    static let maximumArrivalDeliveryRetryAttempts = 3
    static let monitoringStartTimeout: TimeInterval = 15
    private static let monitoringAttemptSeparator = ".attempt."

    private struct PendingRegionStart {
        let alarmID: String
        let region: CLCircularRegion
        let token: UUID
    }

    weak var delegate: LocationManagerDelegate?
    public var locationManager: CLLocationManager
    var alarms: [Alarm] = []

    private var monitoringTimer: Timer?
    private var authorizationCheckTimer: Timer?
    private var hasRestoredSavedAlarms = false
    private var lastAuthorizationStatus: CLAuthorizationStatus?
    private var pendingRegionStarts: [String: PendingRegionStart] = [:]
    private var startTimeoutWorkItems: [String: DispatchWorkItem] = [:]
    private var retryCounts: [String: Int] = [:]
    private var retryWorkItems: [String: DispatchWorkItem] = [:]
    private var retryTokens: [String: UUID] = [:]
    private var retryAlarmIDs: [String: String] = [:]
    private var reconciliationWorkItem: DispatchWorkItem?
    private var currentRegionIdentifiersBySession: [String: String] = [:]
    private var retiredRegionIdentifiers = Set<String>()
    private var arrivalDeliveryRetryCounts: [String: Int] = [:]
    private var arrivalDeliveryRetryWorkItems: [String: DispatchWorkItem] = [:]
    private var arrivalDeliveryRetryTokens: [String: UUID] = [:]

    private let alarmScheduler = AlarmScheduler()
    /// テストでは保存失敗と鳴動所有権を分離して検証できるよう差し替える。
    var alarmSaveHandler: ([Alarm]) -> Result<Void, AlarmStore.SaveError> = {
        AlarmStore.save($0)
    }
    /// 到着判断の並列テストで実通知の非同期ackを発生させないための差し替え口。
    var alarmScheduleOverride: ((Alarm, Bool, String?) -> Void)?
    var alarmActivityCenter: AlarmActivityCenter = .shared

    static func arrivalDeliveryCompletionAction(
        for result: AlarmNotificationScheduleResult,
        shouldRing: Bool,
        ownsPlayback: Bool
    ) -> ArrivalDeliveryCompletionAction {
        switch result {
        case .enqueued:
            return .acknowledge
        case .failed:
            return .retry
        case .cancelled:
            // 明示的な停止でこの到着の所有権が解除された場合だけ、
            // 通知登録中でもoutboxを完了させる。
            return shouldRing && !ownsPlayback ? .acknowledge : .none
        case .superseded:
            return .none
        }
    }

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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCalendarDayChange),
            name: .NSSystemTimeZoneDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSystemClockChange),
            name: .NSSystemClockDidChange,
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
        startTimeoutWorkItems.values.forEach { $0.cancel() }
        arrivalDeliveryRetryWorkItems.values.forEach { $0.cancel() }
    }

    @discardableResult
    func restoreSavedAlarms(
        reason: String,
        loadResult: Result<[Alarm], AlarmStore.LoadError>? = nil
    ) -> Result<Int, AlarmStore.LoadError> {
        if !AppRuntime.shouldSuppressExternalSideEffects {
            AlarmActivityCenter.shared.presentCurrentAlarmIfNeeded()
        }

        let result = loadResult ?? AlarmStore.loadResult()
        guard case .success(let restoredAlarms) = result else {
#if DEBUG
            if case .failure(let error) = result {
                print("⚠️ event=alarmsRestoreSkipped reason=\(reason) error=\(error.localizedDescription)")
            }
#endif
            return result.map(\.count)
        }

        alarms = restoredAlarms
        hasRestoredSavedAlarms = true
        deliverPendingArrivals()
#if DEBUG
        print("ℹ️ event=alarmsRestored reason=\(reason) count=\(alarms.count)")
#endif
        startMonitoring(alarms: alarms)
        return .success(alarms.count)
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
            requestCurrentLocationForEnabledAlarms()
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
        currentLocation: CLLocation?,
        sessionID: String = UUID().uuidString,
        now: Date = Date()
    ) -> Alarm {
        var prepared = alarm
        prepared.prepareForInitialStateCheck(sessionID: sessionID, now: now)

        guard let currentLocation,
              let destination = prepared.location,
              let radius = prepared.geofenceRadius,
              prepared.canResolveInitialState(
                  usingLocationTimestamp: currentLocation.timestamp
              ),
              isUsableLocation(
                  currentLocation,
                  now: now,
                  maximumHorizontalAccuracy: maximumHorizontalAccuracy(for: radius)
              ) else {
            return prepared
        }

        let target = CLLocation(
            latitude: destination.latitude,
            longitude: destination.longitude
        )
        switch AlarmTriggerPolicy.boundaryState(
            distance: currentLocation.distance(from: target),
            radius: radius,
            horizontalAccuracy: currentLocation.horizontalAccuracy
        ) {
        case .inside:
            prepared.resolveInitialState(isInside: true)
        case .outside:
            prepared.resolveInitialState(isInside: false)
        case .uncertain:
            // 境界付近では誤差の小さい次の測位を待つ。
            break
        }
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

    private func geofenceRegion(
        for alarm: Alarm,
        identifier: String? = nil
    ) -> CLCircularRegion? {
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
            identifier: identifier ?? alarm.monitoringSessionID
        )
        region.notifyOnEntry = true
        region.notifyOnExit = true
        return region
    }

    static func monitoringRegionIdentifier(
        sessionID: String,
        attemptID: UUID
    ) -> String {
        "\(sessionID)\(monitoringAttemptSeparator)\(attemptID.uuidString)"
    }

    static func monitoringSessionID(
        fromRegionIdentifier regionIdentifier: String
    ) -> String {
        guard let separatorRange = regionIdentifier.range(
            of: monitoringAttemptSeparator,
            options: .backwards
        ) else {
            return regionIdentifier
        }
        let attemptID = String(regionIdentifier[separatorRange.upperBound...])
        guard UUID(uuidString: attemptID) != nil else {
            return regionIdentifier
        }
        return String(regionIdentifier[..<separatorRange.lowerBound])
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
                setMonitoringState(.failed, alarmID: alarm.id, failure: AppStrings.text("この端末では到着範囲の監視を利用できません。"))
            }
            return
        }

        let desiredAlarms = geofenceAlarms(from: alarms)
        let desiredByRegionID = Dictionary(
            uniqueKeysWithValues: desiredAlarms.map {
                ($0.monitoringSessionID, $0)
            }
        )
        let desiredRegionIDs = Set(desiredByRegionID.keys)
        invalidateRegionTracking(notIn: desiredRegionIDs)

        let currentRegions = locationManager.monitoredRegions
        var validRegionsBySession = [String: [CLRegion]]()
        var regionsToStop = [CLRegion]()

        for region in currentRegions {
            let sessionID = Self.monitoringSessionID(
                fromRegionIdentifier: region.identifier
            )
            guard !retiredRegionIdentifiers.contains(region.identifier),
                  let alarm = desiredByRegionID[sessionID],
                  let expectedRegion = geofenceRegion(
                      for: alarm,
                      identifier: region.identifier
                  ),
                  sameConfiguration(region, expectedRegion) else {
                regionsToStop.append(region)
                continue
            }
            validRegionsBySession[sessionID, default: []].append(region)
        }

        var unchangedSessionIDs = Set<String>()
        for (sessionID, candidateRegions) in validRegionsBySession {
            guard let alarm = desiredByRegionID[sessionID] else { continue }
            let preferredIdentifier = currentRegionIdentifiersBySession[
                sessionID
            ]
            let selectedRegion = candidateRegions.first {
                $0.identifier == preferredIdentifier
            } ?? candidateRegions.first {
                pendingRegionStarts[$0.identifier] != nil
            } ?? candidateRegions.sorted {
                $0.identifier < $1.identifier
            }.first
            guard let selectedRegion else { continue }

            currentRegionIdentifiersBySession[sessionID] =
                selectedRegion.identifier
            unchangedSessionIDs.insert(sessionID)
            for region in candidateRegions
            where region.identifier != selectedRegion.identifier {
                retiredRegionIdentifiers.insert(region.identifier)
                regionsToStop.append(region)
            }

            if pendingRegionStarts[selectedRegion.identifier] == nil {
                if Self.monitoringState(for: alarm.id) != .active {
                    setMonitoringState(.active, alarmID: alarm.id)
                }
                if alarm.needsInitialStateCheck {
                    locationManager.requestState(for: selectedRegion)
                }
            }
        }

        for sessionID in Array(currentRegionIdentifiersBySession.keys)
        where !unchangedSessionIDs.contains(sessionID)
            && pendingRegionStarts.values.contains(where: {
                Self.monitoringSessionID(
                    fromRegionIdentifier: $0.region.identifier
                ) == sessionID
            }) == false {
            currentRegionIdentifiersBySession[sessionID] = nil
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

        guard Self.canAttemptLocationMonitoring(
            for: locationManager.authorizationStatus
        ) else {
            suspendRegionStartsForMissingAuthorization(
                desiredAlarms: Self.geofenceEligibleAlarms(from: alarms)
            )
            return
        }

        for alarm in Self.geofenceEligibleAlarms(from: alarms) where !usesGeofence(for: alarm) {
            setMonitoringState(.continuous, alarmID: alarm.id)
        }

        let alarmsToStart = desiredAlarms.filter {
            let regionID = $0.monitoringSessionID
            return !unchangedSessionIDs.contains(regionID)
                && !pendingRegionStarts.values.contains(where: {
                    Self.monitoringSessionID(
                        fromRegionIdentifier: $0.region.identifier
                    ) == regionID
                })
                && retryWorkItems[regionID] == nil
                && Self.shouldRetryMonitoring(
                    afterFailureCount: retryCounts[regionID, default: 0]
                )
        }
        let remainingCapacity = Self.remainingGeofenceCapacity(
            currentRegionIDs: Set(currentRegions.map(\.identifier)),
            pendingRegionIDs: Set(pendingRegionStarts.keys)
        )
        let alarmsWithinCapacity = Array(alarmsToStart.prefix(remainingCapacity))
        let excludedAlarms = alarmsToStart.dropFirst(remainingCapacity)

        for alarm in excludedAlarms {
            setMonitoringState(
                .capacityExceeded,
                alarmID: alarm.id,
                failure: AppStrings.text("同時に監視できる到着範囲の上限に達しています。")
            )
        }

        for alarm in alarmsWithinCapacity {
            beginMonitoring(for: alarm)
        }
    }

    static func remainingGeofenceCapacity(
        currentRegionIDs: Set<String>,
        pendingRegionIDs: Set<String>
    ) -> Int {
        let reservedIDs = currentRegionIDs.union(pendingRegionIDs)
        return max(0, maximumMonitoredGeofences - reservedIDs.count)
    }

    static func shouldRetryMonitoring(afterFailureCount failureCount: Int) -> Bool {
        failureCount <= maximumMonitoringRetryAttempts
    }

    static func canAttemptLocationMonitoring(
        for status: CLAuthorizationStatus
    ) -> Bool {
        status == .authorizedAlways || status == .authorizedWhenInUse
    }

    static func shouldResetMonitoringAttempts(
        previousStatus: CLAuthorizationStatus?,
        currentStatus: CLAuthorizationStatus
    ) -> Bool {
        canAttemptLocationMonitoring(for: currentStatus)
            && previousStatus != currentStatus
    }

    private func beginMonitoring(for alarm: Alarm) {
        let token = UUID()
        let physicalRegionID = Self.monitoringRegionIdentifier(
            sessionID: alarm.monitoringSessionID,
            attemptID: token
        )
        guard let region = geofenceRegion(
            for: alarm,
            identifier: physicalRegionID
        ) else {
            return
        }
        let regionID = region.identifier
        pendingRegionStarts[regionID] = PendingRegionStart(
            alarmID: alarm.id,
            region: region,
            token: token
        )
        currentRegionIdentifiersBySession[alarm.monitoringSessionID] = regionID
        setMonitoringState(.requested, alarmID: alarm.id)

        startTimeoutWorkItems[regionID]?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            self?.handleMonitoringStartTimeout(regionID: regionID, token: token)
        }
        startTimeoutWorkItems[regionID] = timeout
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.monitoringStartTimeout,
            execute: timeout
        )
        locationManager.startMonitoring(for: region)
#if DEBUG
        print("ℹ️ event=monitoringStartRequested alarmID=\(alarm.id) sessionID=\(regionID)")
#endif
    }

    private func handleMonitoringStartTimeout(regionID: String, token: UUID) {
        guard let pending = pendingRegionStarts[regionID],
              pending.token == token else {
            return
        }
        let sessionID = Self.monitoringSessionID(
            fromRegionIdentifier: regionID
        )
        finishPendingStart(regionID: regionID)

        guard let index = alarmIndex(matchingRegionID: regionID),
              let expectedRegion = geofenceRegion(
                  for: alarms[index],
                  identifier: regionID
              ) else {
            synchronizeGeofences()
            return
        }

        if let monitoredRegion = locationManager.monitoredRegions.first(where: {
            $0.identifier == regionID && sameConfiguration($0, expectedRegion)
        }) {
            retryCounts[sessionID] = 0
            cancelRetry(regionID: sessionID, clearCount: false)
            setMonitoringState(.active, alarmID: alarms[index].id)
            locationManager.requestState(for: monitoredRegion)
            synchronizeGeofences()
            return
        }

        retiredRegionIdentifiers.insert(regionID)
        locationManager.stopMonitoring(for: pending.region)
        if currentRegionIdentifiersBySession[sessionID] == regionID {
            currentRegionIdentifiersBySession[sessionID] = nil
        }
        scheduleMonitoringRetry(
            regionID: sessionID,
            alarmID: pending.alarmID
        )
    }

    private func finishPendingStart(regionID: String) {
        pendingRegionStarts[regionID] = nil
        startTimeoutWorkItems[regionID]?.cancel()
        startTimeoutWorkItems[regionID] = nil
    }

    private func invalidateRegionTracking(notIn desiredRegionIDs: Set<String>) {
        let obsoletePendingRegionIDs = pendingRegionStarts.keys.filter {
            !desiredRegionIDs.contains(
                Self.monitoringSessionID(fromRegionIdentifier: $0)
            )
        }
        for regionID in obsoletePendingRegionIDs {
            guard let pending = pendingRegionStarts[regionID] else { continue }
            retiredRegionIdentifiers.insert(regionID)
            locationManager.stopMonitoring(for: pending.region)
            finishPendingStart(regionID: regionID)
        }

        let retryRegionIDs = Set(retryCounts.keys)
            .union(retryWorkItems.keys)
            .union(retryAlarmIDs.keys)
        for regionID in retryRegionIDs where !desiredRegionIDs.contains(regionID) {
            cancelRetry(regionID: regionID, clearCount: true)
        }
        for sessionID in currentRegionIdentifiersBySession.keys
        where !desiredRegionIDs.contains(sessionID) {
            currentRegionIdentifiersBySession[sessionID] = nil
        }
        retiredRegionIdentifiers = retiredRegionIdentifiers.filter {
            desiredRegionIDs.contains(
                Self.monitoringSessionID(fromRegionIdentifier: $0)
            )
        }
    }

    private func suspendRegionStartsForMissingAuthorization(
        desiredAlarms: [Alarm]
    ) {
        let desiredRegionIDs = Set(desiredAlarms.map(\.monitoringSessionID))
        for regionID in pendingRegionStarts.keys.filter({
            desiredRegionIDs.contains(
                Self.monitoringSessionID(fromRegionIdentifier: $0)
            )
        }) {
            guard let pending = pendingRegionStarts[regionID] else { continue }
            retiredRegionIdentifiers.insert(regionID)
            locationManager.stopMonitoring(for: pending.region)
            finishPendingStart(regionID: regionID)
            cancelRetry(regionID: regionID, clearCount: true)
        }
        for alarm in desiredAlarms {
            cancelRetry(
                regionID: alarm.monitoringSessionID,
                clearCount: true
            )
            setMonitoringState(
                .permissionRequired,
                alarmID: alarm.id,
                failure: AppStrings.text("到着範囲を監視するには位置情報の許可が必要です。")
            )
        }
    }

    private func scheduleMonitoringRetry(regionID: String, alarmID: String) {
        finishPendingStart(regionID: regionID)
        cancelRetry(regionID: regionID, clearCount: false)

        guard Self.canAttemptLocationMonitoring(
            for: locationManager.authorizationStatus
        ) else {
            cancelRetry(regionID: regionID, clearCount: true)
            setMonitoringState(
                .permissionRequired,
                alarmID: alarmID,
                failure: AppStrings.text("到着範囲を監視するには位置情報の許可が必要です。")
            )
            return
        }

        let failureCount = retryCounts[regionID, default: 0] + 1
        retryCounts[regionID] = failureCount
        retryAlarmIDs[regionID] = alarmID

        guard Self.shouldRetryMonitoring(afterFailureCount: failureCount),
              alarms.contains(where: {
                  $0.id == alarmID
                      && $0.monitoringSessionID == regionID
                      && $0.isAlarmEnabled
              }) else {
            setMonitoringState(
                .failed,
                alarmID: alarmID,
                failure: AppStrings.text("到着範囲の監視を開始できませんでした。設定を確認して再度お試しください。")
            )
            return
        }

        setMonitoringState(.retrying, alarmID: alarmID)
        let token = UUID()
        retryTokens[regionID] = token
        let item = DispatchWorkItem { [weak self] in
            guard let self,
                  self.retryTokens[regionID] == token else {
                return
            }
            self.retryWorkItems[regionID] = nil
            self.retryTokens[regionID] = nil
            self.synchronizeGeofences()
        }
        retryWorkItems[regionID] = item
        let delay = pow(2.0, Double(failureCount - 1))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func cancelRetry(regionID: String, clearCount: Bool) {
        retryWorkItems[regionID]?.cancel()
        retryWorkItems[regionID] = nil
        retryTokens[regionID] = nil
        retryAlarmIDs[regionID] = nil
        if clearCount {
            retryCounts[regionID] = nil
        }
    }

    private func resetMonitoringAttemptsForDesiredAlarms() {
        for alarm in geofenceAlarms(from: alarms) {
            let regionID = alarm.monitoringSessionID
            for pending in pendingRegionStarts.values
            where pending.alarmID == alarm.id {
                retiredRegionIdentifiers.insert(pending.region.identifier)
                locationManager.stopMonitoring(for: pending.region)
            }
            for pendingRegionID in pendingRegionStarts.keys.filter({
                Self.monitoringSessionID(fromRegionIdentifier: $0) == regionID
            }) {
                finishPendingStart(regionID: pendingRegionID)
            }
            cancelRetry(regionID: regionID, clearCount: true)
            currentRegionIdentifiersBySession[regionID] = nil
            UserDefaults.standard.removeObject(
                forKey: MonitoringDefaultsKey.failure(alarm.id)
            )
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

    private func alarmIndex(matchingRegionID regionID: String) -> Int? {
        let sessionID = Self.monitoringSessionID(
            fromRegionIdentifier: regionID
        )
        return alarms.firstIndex {
            $0.isAlarmEnabled && $0.monitoringSessionID == sessionID
        }
    }

    private func alarmIndex(matching region: CLRegion) -> Int? {
        let sessionID = Self.monitoringSessionID(
            fromRegionIdentifier: region.identifier
        )
        guard !retiredRegionIdentifiers.contains(region.identifier),
              currentRegionIdentifiersBySession[sessionID]
                  == region.identifier,
              let index = alarmIndex(matchingRegionID: region.identifier),
              let expectedRegion = geofenceRegion(
                  for: alarms[index],
                  identifier: region.identifier
              ),
              sameConfiguration(region, expectedRegion) else {
            return nil
        }
        return index
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let index = alarmIndex(matching: region) else { return }
        if alarms[index].needsInitialStateCheck {
            // 現在の監視sessionで届いたentryは、保存後の実際の境界通過。
            // 初期inside判定は requestState / 保存後timestampの位置でのみ行う。
            alarms[index].resolveInitialState(isInside: false)
        }

        triggerAlarm(alarmID: alarms[index].id)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let index = alarmIndex(matching: region) else { return }
        let previousAlarm = alarms[index]
        alarms[index].resolveInitialState(isInside: false)
        persistAlarmStateChange(
            at: index,
            restoring: previousAlarm
        )
    }

    func locationManager(
        _ manager: CLLocationManager,
        didDetermineState state: CLRegionState,
        for region: CLRegion
    ) {
        guard let index = alarmIndex(matching: region) else { return }

        switch state {
        case .inside:
            if alarms[index].needsInitialStateCheck {
                let previousAlarm = alarms[index]
                alarms[index].resolveInitialState(isInside: true)
                persistAlarmStateChange(
                    at: index,
                    restoring: previousAlarm
                )
            } else {
                triggerAlarm(alarmID: alarms[index].id)
            }
        case .outside:
            if alarms[index].needsInitialStateCheck
                || alarms[index].hasTriggeredUntilExit {
                let previousAlarm = alarms[index]
                alarms[index].resolveInitialState(isInside: false)
                persistAlarmStateChange(
                    at: index,
                    restoring: previousAlarm
                )
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
        let regionID = region.identifier
        let sessionID = Self.monitoringSessionID(
            fromRegionIdentifier: regionID
        )
        guard !retiredRegionIdentifiers.contains(regionID),
              currentRegionIdentifiersBySession[sessionID] == regionID else {
            finishPendingStart(regionID: regionID)
            manager.stopMonitoring(for: region)
            scheduleReconciliation(after: 0.5)
            return
        }
        finishPendingStart(regionID: regionID)
        guard let index = alarmIndex(matching: region) else {
            cancelRetry(regionID: sessionID, clearCount: true)
            retiredRegionIdentifiers.insert(regionID)
            manager.stopMonitoring(for: region)
            scheduleReconciliation(after: 0.5)
            return
        }

        retryCounts[sessionID] = 0
        cancelRetry(regionID: sessionID, clearCount: false)
        setMonitoringState(.active, alarmID: alarms[index].id)
        manager.requestState(for: region)
        synchronizeGeofences()
    }

    func locationManager(
        _ manager: CLLocationManager,
        monitoringDidFailFor region: CLRegion?,
        withError error: Error
    ) {
        guard let region else {
#if DEBUG
            print("❌ event=monitoringFailed alarmID=unknown reason=\(error.localizedDescription)")
#endif
            // active monitorに紐付かないruntime failureもあるため、OS台帳を
            // 再監査し、消失したregionを復旧する。
            scheduleReconciliation(after: 0.5)
            return
        }

        let regionID = region.identifier
        let sessionID = Self.monitoringSessionID(
            fromRegionIdentifier: regionID
        )
        guard !retiredRegionIdentifiers.contains(regionID),
              currentRegionIdentifiersBySession[sessionID] == regionID else {
            finishPendingStart(regionID: regionID)
            manager.stopMonitoring(for: region)
            scheduleReconciliation(after: 0.5)
            return
        }
        finishPendingStart(regionID: regionID)
        guard let index = alarmIndex(matching: region) else {
            cancelRetry(regionID: sessionID, clearCount: true)
            return
        }
        retiredRegionIdentifiers.insert(regionID)
        currentRegionIdentifiersBySession[sessionID] = nil
        manager.stopMonitoring(for: region)
        scheduleMonitoringRetry(
            regionID: sessionID,
            alarmID: alarms[index].id
        )
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
        let previousStatus = lastAuthorizationStatus
        lastAuthorizationStatus = status
        NotificationCenter.default.post(
            name: .locationAuthorizationDidChange,
            object: nil,
            userInfo: ["status": status.rawValue]
        )
        updateContinuousLocationMonitoring(for: status)
        if hasRestoredSavedAlarms {
            if Self.shouldResetMonitoringAttempts(
                previousStatus: previousStatus,
                currentStatus: status
            ) {
                resetMonitoringAttemptsForDesiredAlarms()
            }
            synchronizeGeofences()
            requestCurrentLocationForEnabledAlarms()
        }
    }

    private func evaluateAlarms(at location: CLLocation) {
        let alarmsBeforeEvaluation = alarms
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
                guard snapshot.canResolveInitialState(
                    usingLocationTimestamp: location.timestamp
                ) else {
                    continue
                }
                let boundaryState = AlarmTriggerPolicy.boundaryState(
                    distance: distance,
                    radius: radius,
                    horizontalAccuracy: location.horizontalAccuracy
                )
                guard boundaryState != .uncertain,
                      let index = alarms.firstIndex(where: { $0.id == snapshot.id }) else {
                    continue
                }
                alarms[index].resolveInitialState(isInside: boundaryState == .inside)
                stateChangedIDs.insert(snapshot.id)
                continue
            }

            switch AlarmTriggerPolicy.proximityAction(
                for: snapshot,
                distance: distance,
                radius: radius,
                weekday: today,
                horizontalAccuracy: location.horizontalAccuracy
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
            guard case .success = saveAlarms() else {
                alarms = alarmsBeforeEvaluation
                return
            }
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
        let alarmsBeforeTrigger = alarms
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
        alarms[index].initialStateCheckBeganAt = nil
        let occurrenceID = UUID().uuidString
        alarms[index].enqueueArrivalDelivery(occurrenceID: occurrenceID)
        guard case .success = saveAlarms() else {
            alarms = alarmsBeforeTrigger
            return
        }

        deliverArrival(
            alarmID: alarmID,
            occurrenceID: occurrenceID
        )

        let updatedAlarm = alarms[index]
        delegate?.didUpdateAlarmStatus(updatedAlarm)
        NotificationCenter.default.post(name: .alarmUpdated, object: updatedAlarm)
        synchronizeGeofences()
    }

    private func deliverPendingArrivals() {
        let pendingDeliveries = alarms.flatMap { alarm in
            alarm.pendingArrivalDeliveries.map {
                (alarmID: alarm.id, occurrenceID: $0.occurrenceID)
            }
        }
        for pendingDelivery in pendingDeliveries {
            _ = deliverArrival(
                alarmID: pendingDelivery.alarmID,
                occurrenceID: pendingDelivery.occurrenceID,
                recoveringPendingDelivery: true,
                notifyChangeOnSuccess: true
            )
        }
    }

    @discardableResult
    func deliverArrival(
        alarmID: String,
        occurrenceID: String,
        recoveringPendingDelivery: Bool = false,
        notifyChangeOnSuccess: Bool = false
    ) -> Bool {
        if !Thread.isMainThread {
            return DispatchQueue.main.sync {
                performArrivalDelivery(
                    alarmID: alarmID,
                    occurrenceID: occurrenceID,
                    recoveringPendingDelivery: recoveringPendingDelivery,
                    notifyChangeOnSuccess: notifyChangeOnSuccess
                )
            }
        }
        return performArrivalDelivery(
            alarmID: alarmID,
            occurrenceID: occurrenceID,
            recoveringPendingDelivery: recoveringPendingDelivery,
            notifyChangeOnSuccess: notifyChangeOnSuccess
        )
    }

    /// 再生所有権の予約、判断保存、鳴動開始をmain queue上の一続きの処理にする。
    private func performArrivalDelivery(
        alarmID: String,
        occurrenceID: String,
        recoveringPendingDelivery: Bool,
        notifyChangeOnSuccess: Bool
    ) -> Bool {
        guard let index = alarms.firstIndex(where: {
            $0.id == alarmID && $0.isArrivalDeliveryPending
        }),
        let delivery = alarms[index].arrivalDelivery(
            occurrenceID: occurrenceID
        ) else {
            return false
        }

        var alarm = alarms[index]
        var shouldRing: Bool
        if let persistedDecision = delivery.shouldRing {
            shouldRing = persistedDecision
        } else {
            let alarmBeforeDecision = alarms[index]
            let playbackDecision = alarmActivityCenter.reserveArrival(
                alarmID: alarm.id,
                occurrenceID: occurrenceID,
                recoveringPendingDelivery: recoveringPendingDelivery
            )
            shouldRing = playbackDecision == .ring
            alarms[index].setArrivalDeliveryDecision(
                occurrenceID: occurrenceID,
                shouldRing: shouldRing
            )
            guard case .success = saveAlarms() else {
                alarms[index] = alarmBeforeDecision
                if shouldRing {
                    _ = alarmActivityCenter.releaseReservedArrival(
                        alarmID: alarmID,
                        occurrenceID: occurrenceID
                    )
                }
                return false
            }
            alarm = alarms[index]
        }

        if shouldRing {
            let currentDelivery = alarms[index].arrivalDelivery(
                occurrenceID: occurrenceID
            )
            let ownsPlayback = alarmActivityCenter.ownsPlayback(
                alarmID: alarmID,
                occurrenceID: occurrenceID
            )
            let isPlaybackActivated = alarmActivityCenter.isPlaybackActivated(
                alarmID: alarmID,
                occurrenceID: occurrenceID
            )

            if recoveringPendingDelivery,
               currentDelivery?.didActivateRinging == true,
               !ownsPlayback,
               !isPlaybackActivated {
                // 再生開始済みの永続状態だけが残り、所有権がない場合は、
                // 明示停止後に通知取消の完了保存より先に終了した状態。
                return acknowledgeArrivalDelivery(
                    alarmID: alarmID,
                    occurrenceID: occurrenceID,
                    notifyChange: notifyChangeOnSuccess
                )
            }

            if !ownsPlayback {
                let recoveredDecision = alarmActivityCenter.reserveArrival(
                    alarmID: alarmID,
                    occurrenceID: occurrenceID,
                    recoveringPendingDelivery: recoveringPendingDelivery
                )
                if recoveredDecision == .notifyOnly {
                    let alarmBeforeDowngrade = alarms[index]
                    alarms[index].setArrivalDeliveryDecision(
                        occurrenceID: occurrenceID,
                        shouldRing: false
                    )
                    guard case .success = saveAlarms() else {
                        alarms[index] = alarmBeforeDowngrade
                        return false
                    }
                    shouldRing = false
                    alarm = alarms[index]
                }
            }

            if shouldRing {
                if !alarmActivityCenter.isPlaybackActivated(
                    alarmID: alarmID,
                    occurrenceID: occurrenceID
                ) {
                    guard alarmActivityCenter.activateReservedArrival(
                        for: alarm,
                        occurrenceID: occurrenceID
                    ) else {
                        scheduleArrivalDeliveryRetry(
                            alarmID: alarmID,
                            occurrenceID: occurrenceID
                        )
                        return false
                    }
                }

                if alarms[index].arrivalDelivery(
                    occurrenceID: occurrenceID
                )?.didActivateRinging != true {
                    let alarmBeforeActivationMark = alarms[index]
                    alarms[index].markArrivalDeliveryActivated(
                        occurrenceID: occurrenceID
                    )
                    guard case .success = saveAlarms() else {
                        alarms[index] = alarmBeforeActivationMark
                        scheduleArrivalDeliveryRetry(
                            alarmID: alarmID,
                            occurrenceID: occurrenceID
                        )
                        return false
                    }
                    alarm = alarms[index]
                }
            }
        }

        if let alarmScheduleOverride {
            alarmScheduleOverride(alarm, shouldRing, occurrenceID)
        } else {
            alarmScheduler.scheduleAlarm(
                alarm: alarm,
                isRinging: shouldRing,
                occurrenceID: occurrenceID
            ) { [weak self] result in
                DispatchQueue.main.async {
                    let action = Self.arrivalDeliveryCompletionAction(
                        for: result,
                        shouldRing: shouldRing,
                        ownsPlayback: self?.alarmActivityCenter.ownsPlayback(
                            alarmID: alarmID,
                            occurrenceID: occurrenceID
                        ) ?? false
                    )
                    switch action {
                    case .acknowledge:
                        self?.acknowledgeArrivalDelivery(
                            alarmID: alarmID,
                            occurrenceID: occurrenceID,
                            notifyChange: true
                        )
                    case .retry:
                        self?.scheduleArrivalDeliveryRetry(
                            alarmID: alarmID,
                            occurrenceID: occurrenceID
                        )
                    case .none:
                        break
                    }
                }
            }
        }
        if notifyChangeOnSuccess,
           let updatedAlarm = alarms.first(where: { $0.id == alarmID }) {
            delegate?.didUpdateAlarmStatus(updatedAlarm)
            NotificationCenter.default.post(
                name: .alarmUpdated,
                object: updatedAlarm
            )
        }
        return true
    }

    @discardableResult
    private func acknowledgeArrivalDelivery(
        alarmID: String,
        occurrenceID: String,
        notifyChange: Bool
    ) -> Bool {
        guard let index = alarms.firstIndex(where: {
            $0.id == alarmID
                && $0.arrivalDelivery(occurrenceID: occurrenceID) != nil
        }) else {
            return false
        }
        let alarmBeforeAcknowledgement = alarms[index]
        alarms[index].acknowledgeArrivalDelivery(
            occurrenceID: occurrenceID
        )
        guard case .success = saveAlarms() else {
            alarms[index] = alarmBeforeAcknowledgement
            return false
        }
        cancelArrivalDeliveryRetry(occurrenceID: occurrenceID)
        let alarm = alarms[index]
        if notifyChange {
            delegate?.didUpdateAlarmStatus(alarm)
            NotificationCenter.default.post(
                name: .alarmUpdated,
                object: alarm
            )
        }
        return true
    }

    static func shouldRetryArrivalDelivery(
        afterFailureCount failureCount: Int
    ) -> Bool {
        failureCount <= maximumArrivalDeliveryRetryAttempts
    }

    private func scheduleArrivalDeliveryRetry(
        alarmID: String,
        occurrenceID: String
    ) {
        guard alarms.contains(where: {
            $0.id == alarmID
                && $0.arrivalDelivery(occurrenceID: occurrenceID) != nil
        }) else {
            cancelArrivalDeliveryRetry(occurrenceID: occurrenceID)
            return
        }

        arrivalDeliveryRetryWorkItems[occurrenceID]?.cancel()
        let failureCount = arrivalDeliveryRetryCounts[
            occurrenceID,
            default: 0
        ] + 1
        arrivalDeliveryRetryCounts[occurrenceID] = failureCount
        guard Self.shouldRetryArrivalDelivery(
            afterFailureCount: failureCount
        ) else {
            arrivalDeliveryRetryWorkItems[occurrenceID] = nil
            arrivalDeliveryRetryTokens[occurrenceID] = nil
            return
        }

        let token = UUID()
        arrivalDeliveryRetryTokens[occurrenceID] = token
        let item = DispatchWorkItem { [weak self] in
            guard let self,
                  self.arrivalDeliveryRetryTokens[occurrenceID] == token else {
                return
            }
            self.arrivalDeliveryRetryWorkItems[occurrenceID] = nil
            self.arrivalDeliveryRetryTokens[occurrenceID] = nil
            self.deliverArrival(
                alarmID: alarmID,
                occurrenceID: occurrenceID,
                recoveringPendingDelivery: true,
                notifyChangeOnSuccess: true
            )
        }
        arrivalDeliveryRetryWorkItems[occurrenceID] = item
        let delay = pow(2.0, Double(failureCount - 1))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func cancelArrivalDeliveryRetry(occurrenceID: String) {
        arrivalDeliveryRetryWorkItems[occurrenceID]?.cancel()
        arrivalDeliveryRetryWorkItems[occurrenceID] = nil
        arrivalDeliveryRetryTokens[occurrenceID] = nil
        arrivalDeliveryRetryCounts[occurrenceID] = nil
    }

    private func persistAlarmStateChange(
        at index: Int,
        restoring previousAlarm: Alarm
    ) {
        let alarm = alarms[index]
        guard case .success = saveAlarms() else {
            alarms[index] = previousAlarm
            return
        }
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

    private func requestCurrentLocationForEnabledAlarms() {
        guard alarms.contains(where: {
            $0.isAlarmEnabled && $0.location != nil && $0.geofenceRadius != nil
        }) else {
            return
        }
        requestCurrentLocationIfAuthorized()
    }

    private func requestCurrentLocationIfAuthorized() {
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
        } else {
            defaults.removeObject(forKey: MonitoringDefaultsKey.failure(alarmID))
        }
        NotificationCenter.default.post(
            name: .alarmMonitoringStatusDidChange,
            object: alarmID
        )
    }

    @discardableResult
    func saveAlarms() -> Result<Void, AlarmStore.SaveError> {
        let normalized = Alarm.normalizedForPersistence(alarms)
        let result = alarmSaveHandler(normalized)
        if case .success = result {
            alarms = normalized
        }
        return result
    }

    func stopMonitoringForAlarm(alarm: Alarm) {
        for region in locationManager.monitoredRegions
        where region.identifier == alarm.id
            || Self.monitoringSessionID(
                fromRegionIdentifier: region.identifier
            ) == alarm.monitoringSessionID {
            retiredRegionIdentifiers.insert(region.identifier)
            locationManager.stopMonitoring(for: region)
        }

        let pendingRegionIDs = pendingRegionStarts.compactMap { regionID, pending in
            pending.alarmID == alarm.id ? regionID : nil
        }
        for regionID in pendingRegionIDs {
            if let pending = pendingRegionStarts[regionID] {
                retiredRegionIdentifiers.insert(regionID)
                locationManager.stopMonitoring(for: pending.region)
            }
            finishPendingStart(regionID: regionID)
            cancelRetry(regionID: regionID, clearCount: true)
        }
        let retryRegionIDs = retryAlarmIDs.compactMap { regionID, alarmID in
            alarmID == alarm.id ? regionID : nil
        }
        for regionID in retryRegionIDs {
            cancelRetry(regionID: regionID, clearCount: true)
        }
        currentRegionIdentifiersBySession[alarm.monitoringSessionID] = nil
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
        guard status == .authorizedAlways || status == .authorizedWhenInUse else {
            return false
        }
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
        for region in locationManager.monitoredRegions where
            currentRegionIdentifiersBySession[
                Self.monitoringSessionID(
                    fromRegionIdentifier: region.identifier
                )
            ] == region.identifier {
            locationManager.requestState(for: region)
        }
        if let location = locationManager.location {
            evaluateAlarms(at: location)
        }
        requestCurrentLocationForEnabledAlarms()
    }

    @objc private func handleSystemClockChange() {
        let now = Date()
        let alarmsBeforeClockChange = alarms
        var changedAlarmIDs = Set<String>()
        for index in alarms.indices {
            let beganAt = alarms[index].initialStateCheckBeganAt
            alarms[index].rebaseInitialStateCheckIfClockMovedBackward(
                now: now
            )
            if alarms[index].initialStateCheckBeganAt != beganAt {
                changedAlarmIDs.insert(alarms[index].id)
            }
        }
        if !changedAlarmIDs.isEmpty {
            guard case .success = saveAlarms() else {
                alarms = alarmsBeforeClockChange
                return
            }
            notifyAlarmUpdates(for: changedAlarmIDs)
        }
        handleCalendarDayChange()
    }
}

extension Notification.Name {
    static let locationAuthorizationDidChange = Notification.Name(
        "LocationAuthorizationDidChange"
    )
    static let alarmUpdated = Notification.Name("AlarmUpdated")
}
