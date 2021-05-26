import Combine
import HealthKit
import os

//public struct LiveWorkout2 {
//
//}
//
//public struct LiveWorkoutFetcher {
//  public var data: (HKWorkoutSession) -> CurrentValueSubject<LiveWorkout2, Never>
//  public var sessionState: (HKWorkoutSession) -> Future<HKWorkoutSessionState, SwiftyHealthKitError>
//}
//
//private struct Dependency {
//  var delegate: WorkoutSessionDelegate
//  var subscriber: CurrentValueSubject<LiveWorkout2, Never>
//}
//private var dependencies: [Dependency] = []
//
//public extension LiveWorkoutFetcher {
//  static let live = Self(
//    data: { session in
//      let value = CurrentValueSubject<LiveWorkout2, Never>(LiveWorkout2())
//
//    },
//    sessionState: { session in
//
//    }
//  )
//}
//
//class WorkoutSessionDelegate: NSObject, HKWorkoutSessionDelegate {
//  let didChangeState: (HKWorkoutSessionState) -> Void
//
//  init(didChangeState: @escaping (HKWorkoutSessionState) -> Void) {
//    self.didChangeState = didChangeState
//    super.init()
//  }
//}
#if os(watchOS)
public struct LiveWorkoutData: Equatable {
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

public protocol LiveWorkoutProtocol {
  var data: CurrentValueSubject<LiveWorkoutData, Never> { get }
  var sessionState: PassthroughSubject<HKWorkoutSessionState, Error> { get }
  func add(_ metaData: [String: Any]) -> Future<Bool, SwiftyHealthKitError>
  func end()
  func pause()
  func reset(
    activityType: HKWorkoutActivityType,
    locationType: HKWorkoutSessionLocationType,
    swimmingLocationType: HKWorkoutSwimmingLocationType?
  ) throws
  func resume()
  func start()
  func stop()
}

public class LiveWorkout: NSObject, LiveWorkoutProtocol {
  public private(set) var data = CurrentValueSubject<LiveWorkoutData, Never>(LiveWorkoutData())
  public private(set) var sessionState = PassthroughSubject<HKWorkoutSessionState, Error>()

  private let healthStore: HKHealthStore
  private var activityType: HKWorkoutActivityType
  private var liveWorkoutBuilder: HKLiveWorkoutBuilder
  private var locationType: HKWorkoutSessionLocationType
  private var swimmingLocationType: HKWorkoutSwimmingLocationType?
  private var workoutConfiguration: HKWorkoutConfiguration
  private var workoutSession: HKWorkoutSession

  public init(
    activityType: HKWorkoutActivityType,
    healthStore: HKHealthStore,
    locationType: HKWorkoutSessionLocationType,
    swimmingLocationType: HKWorkoutSwimmingLocationType? = nil
  ) throws {
    self.activityType = activityType
    self.healthStore = healthStore
    self.locationType = locationType
    self.swimmingLocationType = swimmingLocationType

    if activityType == .swimming && swimmingLocationType == nil { throw SwiftyHealthKitError.swimmingSession }

    workoutConfiguration = HKWorkoutConfiguration()
    workoutConfiguration.activityType = activityType
    workoutConfiguration.locationType = locationType
    if let swimmingLocationType = swimmingLocationType {
      workoutConfiguration.swimmingLocationType = swimmingLocationType
      workoutConfiguration.lapLength = HKQuantity(unit: .meter(), doubleValue: 25)
    }

    do {
      workoutSession = try HKWorkoutSession(
        healthStore: healthStore,
        configuration: workoutConfiguration
      )
      workoutSession.prepare()
      liveWorkoutBuilder = workoutSession.associatedWorkoutBuilder()
    } catch {
      throw SwiftyHealthKitError.session(error as NSError)
    }

    super.init()

    self.workoutSession.delegate = self
    self.liveWorkoutBuilder.delegate = self
    self.liveWorkoutBuilder.dataSource = HKLiveWorkoutDataSource(
      healthStore: healthStore,
      workoutConfiguration: workoutConfiguration
    )
  }

  public func add(_ metaData: [String: Any]) -> Future<Bool, SwiftyHealthKitError> {
    Future { [weak self] completion in
      self?.liveWorkoutBuilder.addMetadata(metaData) { success, error in
        if let error = error {
          completion(.failure(.liveWorkout(error as NSError)))
          return
        }
        completion(.success(success))
      }
    }
  }

  public func end() {
    data.value = LiveWorkoutData()
    workoutSession.end()
  }

  public func pause() {
    workoutSession.pause()
    logger.debug("Pause workout session.")
  }

  public func reset(
    activityType: HKWorkoutActivityType,
    locationType: HKWorkoutSessionLocationType,
    swimmingLocationType: HKWorkoutSwimmingLocationType? = nil
  ) throws {
    try configureWorkoutConfiguration(
      activityType: activityType,
      healthStore: healthStore,
      locationType: locationType,
      swimmingLocationType: swimmingLocationType
    )
    try configureWorkoutSession(
      configuration: workoutConfiguration,
      healthStore: healthStore
    )
  }

  public func resume() {
    workoutSession.resume()
    logger.debug("Resume workout session.")
  }

  public func start() {
    workoutSession.startActivity(with: Date())
    liveWorkoutBuilder.beginCollection(withStart: Date()) { [weak self] _, error in
      if let error = error {
        self?.sessionState.send(completion: .failure(error))
        logger.error("\(error.localizedDescription)")
      } else {
        logger.debug("Start collecting workout data.")
      }
    }
  }

  public func stop() {
    data.value = LiveWorkoutData()
    workoutSession.stopActivity(with: Date())
  }

  private func analyze(statistics: HKStatistics) {
    switch statistics.quantityType {
    case HKQuantityType.quantityType(forIdentifier: .heartRate):
      let heartRateUnit = HKUnit.count().unitDivided(by: HKUnit.minute())
      let value = statistics.mostRecentQuantity()?.doubleValue(for: heartRateUnit)
      data.value.update(heartRate: Double( round( 1 * value! ) / 1 ))

    case HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned):
      let energyUnit = HKUnit.kilocalorie()
      let value = statistics.sumQuantity()?.doubleValue(for: energyUnit)
      data.value.update(activeCalories: Double( round( 1 * value! ) / 1 ))

    case HKQuantityType.quantityType(forIdentifier: .distanceSwimming),
         HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning):
      let meterUnit = HKUnit.meter()
      let value = statistics.sumQuantity()?.doubleValue(for: meterUnit)
      data.value.update(distance: Double( round( 1 * value! ) / 1 ))

    default:
      break
    }
  }

  private func configureWorkoutConfiguration(
    activityType: HKWorkoutActivityType,
    healthStore: HKHealthStore,
    locationType: HKWorkoutSessionLocationType,
    swimmingLocationType: HKWorkoutSwimmingLocationType? = nil
  ) throws {
    self.activityType = activityType
    self.locationType = locationType
    self.swimmingLocationType = swimmingLocationType

    if activityType == .swimming && swimmingLocationType == nil { throw SwiftyHealthKitError.swimmingSession }

    workoutConfiguration = HKWorkoutConfiguration()
    workoutConfiguration.activityType = activityType
    workoutConfiguration.locationType = locationType
    if let swimmingLocationType = swimmingLocationType {
      workoutConfiguration.swimmingLocationType = swimmingLocationType
      workoutConfiguration.lapLength = HKQuantity(unit: .meter(), doubleValue: 25)
    }
  }

  private func configureWorkoutSession(
    configuration: HKWorkoutConfiguration,
    healthStore: HKHealthStore
  ) throws {
    do {
      workoutSession = try HKWorkoutSession(
        healthStore: healthStore,
        configuration: configuration
      )
      workoutSession.prepare()
      liveWorkoutBuilder = workoutSession.associatedWorkoutBuilder()
    } catch {
      throw SwiftyHealthKitError.session(error as NSError)
    }

    self.workoutSession.delegate = self
    self.liveWorkoutBuilder.delegate = self
    self.liveWorkoutBuilder.dataSource = HKLiveWorkoutDataSource(
      healthStore: healthStore,
      workoutConfiguration: configuration
    )
  }
}

extension LiveWorkout: HKWorkoutSessionDelegate {
  public func workoutSession(
    _ workoutSession: HKWorkoutSession,
    didFailWithError error: Error
  ) {
    sessionState.send(completion: .failure(error))
    logger.error("\(error.localizedDescription)")
  }

  public func workoutSession(
    _ workoutSession: HKWorkoutSession,
    didChangeTo toState: HKWorkoutSessionState,
    from fromState: HKWorkoutSessionState,
    date: Date
  ) {
    sessionState.send(toState)
    if toState == .ended {
      liveWorkoutBuilder.endCollection(withEnd: Date()) { [weak self] _, error in
        if let error = error {
          self?.sessionState.send(completion: .failure(error))
          logger.error("\(error.localizedDescription)")
          return
        }
        self?.liveWorkoutBuilder.finishWorkout { workout, error in
          if let error = error {
            self?.sessionState.send(completion: .failure(error))
            logger.error("\(error.localizedDescription)")
          } else {
            logger.debug("End workout session.")
          }
        }
      }
    }
    let logMessage = "Workout session state changed from \(fromState.rawValue) to \(toState.rawValue)"
    logger.debug("\(logMessage)")
  }
}

extension LiveWorkout: HKLiveWorkoutBuilderDelegate {
  public func workoutBuilder(
    _ workoutBuilder: HKLiveWorkoutBuilder,
    didCollectDataOf collectedTypes: Set<HKSampleType>
  ) {
    for type in collectedTypes {
      guard let quantityType = type as? HKQuantityType,
            let statistics = workoutBuilder.statistics(for: quantityType)
      else { return }
      analyze(statistics: statistics)
    }
  }

  public func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
  }
}

public class LiveWorkoutMock: NSObject, LiveWorkoutProtocol {
  public var data = CurrentValueSubject<LiveWorkoutData, Never>(LiveWorkoutData())
  public var sessionState = PassthroughSubject<HKWorkoutSessionState, Error>()
  private var timer: Timer?

  public func add(_ metaData: [String : Any]) -> Future<Bool, SwiftyHealthKitError> {
    Future { completion in
      completion(.failure(.unavailable))
    }
  }

  public func end() {
    stopTimer()
  }

  public func pause() {
    stopTimer()
  }

  public func reset(
    activityType: HKWorkoutActivityType,
    locationType: HKWorkoutSessionLocationType,
    swimmingLocationType: HKWorkoutSwimmingLocationType?
  ) throws {
    // NOP
  }

  public func resume() {
    startTimer()
  }

  public func start() {
    startTimer()
  }

  public func stop() {
    stopTimer()
  }

  private func startTimer() {
    timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] timer in
      guard let self = self else { return }
      let activeEnergyBurned = self.data.value.activeCalories + 1
      let distance = self.data.value.distance + 3
      let heartRate = Double.random(in: 60...100)
      self.data.value.update(
        activeCalories: activeEnergyBurned,
        distance: distance,
        heartRate: heartRate
      )
    }
    timer?.fire()
  }

  private func stopTimer() {
    timer?.invalidate()
  }
}
#endif
