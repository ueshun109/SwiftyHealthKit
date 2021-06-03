import Combine
import HealthKit
import os

#if os(watchOS)
public struct LiveWorkout: Equatable {
  public var activeCalories: Double = 0
  public var distance: Double = 0
  public var heartRate: Double = 0

  public init() {}

  public mutating func update(
    activeCalories: Double? = nil,
    distance: Double? = nil,
    heartRate: Double? = nil
  ) {
    self.activeCalories = activeCalories ?? self.activeCalories
    self.distance = distance ?? self.distance
    self.heartRate = heartRate ?? self.heartRate
  }
}

public enum LiveWorkoutSessionState: Equatable {
  case notStarted(Date?)
  case prepared(Date?)
  case running(Date?)
  case paused(Date?)
  case stopped(Date?)
  case ended(Date?)

  init(state: HKWorkoutSessionState, date: Date?) {
    switch state {
    case .notStarted:
      self = .notStarted(date)
    case .prepared:
      self = .prepared(date)
    case .running:
      self = .running(date)
    case .paused:
      self = .running(date)
    case .stopped:
      self = .stopped(date)
    case .ended:
      self = .ended(date)
    @unknown default:
      fatalError()
    }
  }
}

/// To work with this class, enable the background mode of the capability of the Watch Extension target.
public class LiveWorkoutFetcher {
  public typealias StartArgs = (AnyHashable, HKWorkoutActivityType, HKWorkoutSessionLocationType) -> Void

  public private(set) var liveData: CurrentValueSubject<LiveWorkout, SwiftyHealthKitError>!
  public private(set) var sessionState = PassthroughSubject<LiveWorkoutSessionState, Never>()
  private var workoutSession: HKWorkoutSession!
  private var liveWorkoutBuilder: HKLiveWorkoutBuilder!

  public var add: ([String: Any]) -> Void = { _ in
    fatalError("Must implementation")
  }

  public var end: (AnyHashable) -> Void = { _ in
    fatalError("Must implementation")
  }

  public var start: StartArgs = { _, _, _ in
    fatalError("Must implementation")
  }
}

public extension LiveWorkoutFetcher {
  static let live: LiveWorkoutFetcher = { () -> LiveWorkoutFetcher in
    var me = LiveWorkoutFetcher()

    me.add = { metaData in
      me.liveWorkoutBuilder.addMetadata(metaData) { result, error in
        guard let error = error else { logger.log("Added metadata: \(result)"); return }
        logger.error("\(error.localizedDescription)")
      }
    }

    me.start = { id, activityType, locationType in
      me.liveData = CurrentValueSubject<LiveWorkout, SwiftyHealthKitError>(LiveWorkout())
      let configuration = HKWorkoutConfiguration()
      configuration.activityType = activityType
      configuration.locationType = locationType
      me.workoutSession = try? HKWorkoutSession(
        healthStore: healthStore,
        configuration: configuration
      )
      me.liveWorkoutBuilder = me.workoutSession.associatedWorkoutBuilder()

      let sessionSubscriber: (HKWorkoutSessionState) -> Void = { toState in
        switch toState {
        case .running:
          me.sessionState.send(LiveWorkoutSessionState(state: .running, date: me.workoutSession.startDate))
        case .ended:
          me.liveWorkoutBuilder.endCollection(withEnd: Date()) { _, error in
            if let error = error { logger.error("\(error.localizedDescription)"); return }
            me.liveWorkoutBuilder.finishWorkout { workout, error in
              guard let error = error else {
                logger.debug("End workout session.")
                me.liveData.send(completion: .finished)
                me.sessionState.send(LiveWorkoutSessionState(state: .ended, date: me.workoutSession.endDate))
                return
              }
              logger.error("\(error.localizedDescription)")
              me.liveData.send(completion: .failure(SwiftyHealthKitError.session(error as NSError)))
              dependencies[id] = nil
            }
          }
        default: break
        }
      }

      let builderSubscriber: (HKStatistics) -> Void = { statistics in
        let value = me.analyze(statistics: statistics)
        switch statistics.quantityType {
        case HKQuantityType.quantityType(forIdentifier: .heartRate):
          me.liveData.value.update(heartRate: value)
        case HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned):
          me.liveData.value.update(activeCalories: value)
        case HKQuantityType.quantityType(forIdentifier: .distanceSwimming),
             HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning):
          me.liveData.value.update(distance: value)
        default: break
        }
      }

      let sessionDelegate = LiveWorkoutSessionDelegate(sessionSubscriber)
      let builderDelegate = LiveWorkoutBuilderDelegate(builderSubscriber)
      dependencies[id] = Dependencies(sessionDelegate: sessionDelegate, builderDelegate: builderDelegate)
      me.workoutSession.delegate = sessionDelegate
      me.liveWorkoutBuilder.delegate = builderDelegate
      me.liveWorkoutBuilder.dataSource = .init(healthStore: healthStore, workoutConfiguration: configuration)

      me.workoutSession.startActivity(with: Date())
      me.liveWorkoutBuilder.beginCollection(withStart: Date()) { _, error in
        if let error = error { logger.error("\(error.localizedDescription)"); return }
        logger.debug("Start collecting workout data.")
      }
    }

    me.end = { id in
      me.workoutSession.end()
    }

    return me
  }()
}

private extension LiveWorkoutFetcher {
  func analyze(statistics: HKStatistics) -> Double {
    switch statistics.quantityType {
    case HKQuantityType.quantityType(forIdentifier: .heartRate):
      let heartRateUnit = HKUnit.count().unitDivided(by: HKUnit.minute())
      let value = statistics.mostRecentQuantity()?.doubleValue(for: heartRateUnit)
      return Double(round( 1 * value! ) / 1 )

    case HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned):
      let energyUnit = HKUnit.kilocalorie()
      let value = statistics.sumQuantity()?.doubleValue(for: energyUnit)
      return Double(round( 1 * value! ) / 1 )

    case HKQuantityType.quantityType(forIdentifier: .distanceSwimming),
         HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning):
      let meterUnit = HKUnit.meter()
      let value = statistics.sumQuantity()?.doubleValue(for: meterUnit)
      return Double(round( 1 * value! ) / 1 )

    default:
      return 0
    }
  }

}

private struct Dependencies {
  let sessionDelegate: LiveWorkoutSessionDelegate
  let builderDelegate: LiveWorkoutBuilderDelegate
}

private var dependencies: [AnyHashable: Dependencies] = [:]

// MARK: - HKWorkoutSessionDelegate

private class LiveWorkoutSessionDelegate: NSObject, HKWorkoutSessionDelegate {
  let subscriber: (HKWorkoutSessionState) -> Void

  init(_ subscriber: @escaping (HKWorkoutSessionState) -> Void) {
    self.subscriber = subscriber
  }

  func workoutSession(
    _ workoutSession: HKWorkoutSession,
    didChangeTo toState: HKWorkoutSessionState,
    from fromState: HKWorkoutSessionState,
    date: Date
  ) {
    logger.log("Workout session state changed from \(fromState.rawValue) to \(toState.rawValue)")
    subscriber(toState)
  }

  func workoutSession(
    _ workoutSession: HKWorkoutSession,
    didFailWithError error: Error
  ) {
    logger.error("\(error.localizedDescription)")
  }
}

// MARK: - HKLiveWorkoutBuilderDelegate

private class LiveWorkoutBuilderDelegate: NSObject, HKLiveWorkoutBuilderDelegate {
  let subscriber: (HKStatistics) -> Void

  init(_ subscriber: @escaping (HKStatistics) -> Void) {
    self.subscriber = subscriber
  }

  func workoutBuilder(
    _ workoutBuilder: HKLiveWorkoutBuilder,
    didCollectDataOf collectedTypes: Set<HKSampleType>
  ) {
    for type in collectedTypes {
      guard let quantityType = type as? HKQuantityType,
            let statistics = workoutBuilder.statistics(for: quantityType)
      else { return }
      subscriber(statistics)
    }
  }

  func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
  }
}
#endif
