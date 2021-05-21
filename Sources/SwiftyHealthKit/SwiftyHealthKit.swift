import Combine
import Foundation
import HealthKit
import os

internal let logger = Logger(subsystem: "com.ueshun.SwiftyHealthKit", category: "log")

public class SwiftyHealthKit {
  private let healthStore: HKHealthStore!
  private var cancellables: [AnyCancellable] = []
  #if os(watchOS)
  private var liveWorkout: LiveWorkout!
  #endif
  
  /// Initialize SwiftyHealthKit. Returns nil if your device does not support HealthKit.
  public init?() {
    guard HKHealthStore.isHealthDataAvailable() else { return nil }
    self.healthStore = HKHealthStore()
  }

  /// Get heart rate during workout.
  /// - Parameters:
  ///   - startDate: start date
  ///   - endDate: end date
  ///   - statisticsOptions:
  ///   - activityType: The type of activity performed during a workout
  public func queryHeartRateDuringWorkout(
    startDate: Date,
    endDate: Date,
    statisticsOptions: HKStatisticsOptions,
    activityType: HKWorkoutActivityType
  ) -> AnyPublisher<[HeartRate.HeartRatePerWorkout], SwiftyHealthKitError> {
    let heartRate = HeartRate(startDate: startDate, endDate: endDate, healthStore: healthStore)
    let workout = Workout(healthStore: healthStore)
    let workoutType = HKWorkoutType.workoutType()
    let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)!
    return requestPermission(saveDataTypes: nil, readDataTypes: [workoutType, heartRateType])
      .mapError { error in SwiftyHealthKitError.denied }
      .flatMap { _ in workout.workouts(activityType: activityType, startDate: startDate, endDate: endDate) }
      .mapError { error in SwiftyHealthKitError.query(error as NSError) }
      .flatMap { workouts in heartRate.heartRate(during: workouts, statisticsOptions: statisticsOptions)}
      .mapError { error in SwiftyHealthKitError.query(error as NSError) }
      .eraseToAnyPublisher()
  }

  /// Get user's profile.(e.g. birthDate, height, sex, weight)
  /// - Parameter type: the profile data you want
  public func queryProfile(
    type: Set<ProfileType>
  ) -> AnyPublisher<Profile, SwiftyHealthKitError> {
    let getProfile = GetProfile(healthStore: healthStore)
    let readType = Set(type.map { $0.dataType })
    let saveType = Set(readType.compactMap { $0 as? HKSampleType })
    return requestPermission(saveDataTypes: saveType, readDataTypes: readType)
      .mapError { error in SwiftyHealthKitError.denied }
      .flatMap { _ in
        getProfile.birthDate
          .map { Profile(birthDate: $0) }
          .catch { _ in Just(Profile()) }
      }
      .flatMap { profile in
        getProfile.height
          .map { Profile(birthDate: profile.birthDate, height: $0) }
          .catch { _ in Just(profile) }
      }
      .flatMap { profile in
        getProfile.sex
          .map { Profile(birthDate: profile.birthDate, height: profile.height, sex: $0) }
          .catch { _ in Just(profile) }
      }
      .flatMap { profile in
        getProfile.weight
          .map { Profile(birthDate: profile.birthDate, height: profile.height, sex: profile.sex, weight: $0) }
          .catch { _ in Just(profile) }
      }
      .eraseToAnyPublisher()
  }

  /// Get workout data.
  /// - Parameters:
  ///   - startDate: start date
  ///   - endDate: end date
  ///   - statisticsOptions:
  ///   - activityType: The type of activity performed during a workout
  public func queryWorkout(
    startDate: Date,
    endDate: Date,
    statisticsOptions: HKStatisticsOptions,
    activityType: HKWorkoutActivityType
  ) -> AnyPublisher<[HKWorkout], SwiftyHealthKitError> {
    let workout = Workout(healthStore: healthStore)
    let workoutType = HKWorkoutType.workoutType()
    return requestPermission(saveDataTypes: nil, readDataTypes: [workoutType])
      .mapError { _ in SwiftyHealthKitError.denied }
      .flatMap { _ in workout.workouts(activityType: activityType, startDate: startDate, endDate: endDate) }
      .mapError { error in SwiftyHealthKitError.query(error as NSError) }
      .eraseToAnyPublisher()
  }

  /// Requests permission to save and read the specified data types.
  public func requestPermission(
    saveDataTypes: Set<HKSampleType>?,
    readDataTypes: Set<HKObjectType>?
  ) -> Future<Bool, Error> {
    Future { [weak self] completion in
      guard let self = self else { return }
      self.healthStore.requestAuthorization(toShare: saveDataTypes, read: readDataTypes) { result, error in
        guard let error = error else { completion(.success(result)); return }
        completion(.failure(error))
        logger.log("Denied access to health care data.")
      }
    }
  }
}

#if os(watchOS)
extension SwiftyHealthKit {
  /// - Parameters:
  ///   - activityType: `HKWorkoutActivityType`
  ///   - locationType: `HKWorkoutSessionLocationType`
  ///   - readDataTypes: Data type during the workout you want to monitor
  ///   - isMock: If true, mock data will be sent
  public func liveWorkout(
    activityType: HKWorkoutActivityType,
    locationType: HKWorkoutSessionLocationType,
    readDataTypes: Set<HKObjectType>,
    isMock: Bool = false
  ) -> AnyPublisher<LiveWorkoutProtocol?, SwiftyHealthKitError> {
    let saveDataType: Set = [HKWorkoutType.workoutType()]

    if isMock {
      return Just(LiveWorkoutMock())
        .setFailureType(to: SwiftyHealthKitError.self)
        .eraseToAnyPublisher()
    }

    return requestPermission(saveDataTypes: saveDataType, readDataTypes: readDataTypes)
      .mapError { _ in SwiftyHealthKitError.denied }
      .tryMap { [weak self] _ -> LiveWorkout? in
        guard let self = self else { return nil }
        self.liveWorkout = try LiveWorkout(
          activityType: activityType,
          healthStore: self.healthStore,
          locationType: locationType
        )
        return self.liveWorkout
      }
      .mapError { error in error as! SwiftyHealthKitError }
      .eraseToAnyPublisher()
  }
}
#endif
