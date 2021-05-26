import Combine
import Foundation
import HealthKit
import os

internal let logger = Logger(subsystem: "com.ueshun.SwiftyHealthKit", category: "log")
internal let healthStore = HKHealthStore()

public struct SwiftyHealthKit {
  public typealias HeartRateArg = (Date, Date, HKStatisticsOptions, HKWorkoutActivityType)

  /// Request authorization. Pass save data type and read data type as argument.
  public var authorization: (Set<HKSampleType>?, Set<HKObjectType>?) -> AnyPublisher<Bool, SwiftyHealthKitError>
  public var heartRateDuringWorkout: (HeartRateFetcher.Arguments) -> AnyPublisher<[HeartRateFetcher.Response], SwiftyHealthKitError>
  public var isAvailable: () -> Bool
  public var profile: (Set<ProfileType>) -> AnyPublisher<Profile, SwiftyHealthKitError>
  public var workout: (Date, Date, HKWorkoutActivityType) -> AnyPublisher<[HKWorkout], SwiftyHealthKitError>
}

public extension SwiftyHealthKit {
  static let live = Self(
    authorization: { saveDataType, readDataType in
      let authorization: Authorization = .live
      return authorization.request(saveDataType, readDataType)
        .mapError { $0 }
        .eraseToAnyPublisher()
    },
    heartRateDuringWorkout: { startDate, endDate, options, activityType in
      let authorization: Authorization = .live
      let heartRate: HeartRateFetcher = .live
      let workout: WorkoutFetcher = .live
      let workoutType = HKWorkoutType.workoutType()
      let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)!
      return authorization.request(nil, [workoutType, heartRateType])
        .mapError { $0 }
        .flatMap { _ in workout.workouts(activityType, startDate, endDate) }
        .mapError { error in SwiftyHealthKitError.query(error as NSError) }
        .flatMap { workouts in heartRate.duringWorkout(workouts, options)}
        .mapError { error in SwiftyHealthKitError.query(error as NSError) }
        .eraseToAnyPublisher()
    },
    isAvailable: {
      HKHealthStore.isHealthDataAvailable()
    },
    profile: { type in
      let authorization: Authorization = .live
      let profile: ProfileFetcher = .live
      let readType = Set(type.map { $0.dataType })
      let saveType = Set(readType.compactMap { $0 as? HKSampleType })
      return authorization.request(saveType, readType)
        .mapError { $0 }
        .flatMap { _ in
          profile.birthDate()
            .map { Profile(birthDate: $0) }
            .catch { _ in Just(Profile()) }
        }
        .flatMap { info in
          profile.height()
            .map { Profile(birthDate: info.birthDate, height: $0) }
            .catch { _ in Just(info) }
        }
        .flatMap { info in
          profile.sex()
            .map { Profile(birthDate: info.birthDate, height: info.height, sex: $0) }
            .catch { _ in Just(info) }
        }
        .flatMap { info in
          profile.weight()
            .map { Profile(birthDate: info.birthDate, height: info.height, sex: info.sex, weight: $0) }
            .catch { _ in Just(info) }
        }
        .eraseToAnyPublisher()
    },
    workout: { startDate, endDate, activityType in
      let authorization: Authorization = .live
      let workout: WorkoutFetcher = .live
      let workoutType = HKWorkoutType.workoutType()
      return authorization.request(nil, [workoutType])
        .mapError { $0 }
        .flatMap { _ in workout.workouts(activityType, startDate, endDate) }
        .mapError { error in SwiftyHealthKitError.query(error as NSError) }
        .eraseToAnyPublisher()
    }
  )
}
