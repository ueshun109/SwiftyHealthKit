import Combine
import HealthKit
import os

#if os(watchOS)
/// To work with this class, enable the background mode of the capability of the Watch Extension target.
public class LiveWorkoutFetcher {
  public typealias StartArgs = (
    AnyHashable,
    HKWorkoutActivityType,
    HKWorkoutSessionLocationType,
    HKWorkoutSwimmingLocationType?,
    HKQuantity?
  ) -> Void

  /// Publish real-time workout information.
  public private(set) var liveData: CurrentValueSubject<LiveWorkoutInformation, SwiftyHealthKitError>!
  /// Publish workout session state.
  public private(set) var sessionState = PassthroughSubject<LiveWorkoutSessionState, Never>()
  /// Add metadata to `HKLiveWorkoutBuilder`.
  public var add: ([String: Any]) -> Void = { _ in
    fatalError("Must implementation")
  }
  /// End workout session.
  public var end: (AnyHashable) -> Void = { _ in
    fatalError("Must implementation")
  }
  /// Start workout session.
  public var start: StartArgs = { _, _, _, _, _ in
    fatalError("Must implementation")
  }

  private var workoutSession: HKWorkoutSession!
  private var liveWorkoutBuilder: HKLiveWorkoutBuilder!
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

    me.start = { id, activityType, locationType, swimmingLocationType, lapLength in
      /// Receive statistics data.
      let statsReceiver: (HKStatistics) -> Void = { statistics in
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
      /// Receive session state changes.
      let sessionStateReceiver: (HKWorkoutSessionState) -> Void = { toState in
        switch toState {
        case .running:
          me.sessionState.send(.init(state: .running, date: me.workoutSession.startDate))
        case .ended:
          me.liveWorkoutBuilder.endCollection(withEnd: Date()) { _, error in
            if let error = error { logger.error("\(error.localizedDescription)"); return }
            me.liveWorkoutBuilder.finishWorkout { workout, error in
              guard let error = error else {
                logger.debug("End workout session.")
                me.liveData.send(completion: .finished)
                me.sessionState.send(.init(state: .ended, date: me.workoutSession.endDate))
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
      let builderDelegate = LiveWorkoutBuilderDelegate(statsReceiver)
      let sessionDelegate = LiveWorkoutSessionDelegate(sessionStateReceiver)
      let configuration = HKWorkoutConfiguration()

      switch activityType {
      case .swimming:
        guard let swimmingLocationType = swimmingLocationType,
              let lapLength = lapLength
        else { fatalError("When activityType is swimming, must configure swimmingLocationType and lapLength.")  }
        configuration.swimmingLocationType = swimmingLocationType
        configuration.lapLength = lapLength
      default:
        break
      }
      configuration.activityType = activityType
      configuration.locationType = locationType

      me.liveData = CurrentValueSubject<LiveWorkoutInformation, SwiftyHealthKitError>(LiveWorkoutInformation())
      me.liveWorkoutBuilder = me.workoutSession.associatedWorkoutBuilder()
      me.liveWorkoutBuilder.delegate = builderDelegate
      me.liveWorkoutBuilder.dataSource = .init(healthStore: healthStore, workoutConfiguration: configuration)

      me.workoutSession = try? HKWorkoutSession(
        healthStore: healthStore,
        configuration: configuration
      )
      me.workoutSession.delegate = sessionDelegate
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
      else { continue }
      subscriber(statistics)
    }
  }

  func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
  }
}
#endif
