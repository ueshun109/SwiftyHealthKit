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
  public var profile: () -> AnyPublisher<Profile, SwiftyHealthKitError>
  public var saveProfile: (Profile) -> AnyPublisher<Bool, SwiftyHealthKitError>
  public var workout: (HKWorkoutActivityType, Date?, Date?, Bool) -> AnyPublisher<[HKWorkout], SwiftyHealthKitError>
  public var burnedActiveCalories: (Date, Date, Date, DateComponents, HKStatisticsOptions, Bool) -> AnyPublisher<[BurnedCalories], SwiftyHealthKitError>
}

public extension SwiftyHealthKit {
  static let live = Self(
    authorization: { saveDataType, readDataType in
      let authorization: Authorization = .live
      return authorization.request(saveDataType, readDataType)
        .mapError { $0 }
        .eraseToAnyPublisher()
    },
    heartRateDuringWorkout: { startDate, endDate, options, activityType, ownAppOnly in
      let heartRate: HeartRateFetcher = .live
      let workout: WorkoutFetcher = .live
      return workout.workouts(activityType, startDate, endDate, ownAppOnly)
        .mapError { error in SwiftyHealthKitError.query(error as NSError) }
        .flatMap { workouts in heartRate.duringWorkout(workouts, options) }
        .mapError { error in SwiftyHealthKitError.query(error as NSError) }
        .eraseToAnyPublisher()
    },
    isAvailable: {
      HKHealthStore.isHealthDataAvailable()
    },
    profile: {
      let profile: ProfileFetcher = .live
      return profile.birthDate()
        .replaceError(with: nil)
        .flatMap {
          Just(Profile(birthDate: $0))
            .eraseToAnyPublisher()
        }
        .setFailureType(to: SwiftyHealthKitError.self)
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
    saveProfile: { profile in
      let profileSaving: ProfileSaving = .live
      return profileSaving.save(profile)
        .mapError { $0 }
        .eraseToAnyPublisher()
    },
    workout: { activityType, startDate, endDate, ownAppOnly in
      let workout: WorkoutFetcher = .live
      return workout.workouts(activityType, startDate, endDate, ownAppOnly)
        .mapError { error in SwiftyHealthKitError.query(error as NSError) }
        .eraseToAnyPublisher()
    },
    burnedActiveCalories: { anchorDate, startDate, endDate, interval, options, ownAppOnly in
      let burnedCaloriesFetcher: BurnedCaloriesFetcher = .live
      return burnedCaloriesFetcher.burnedCalories(anchorDate, startDate, endDate, interval, options, ownAppOnly)
        .mapError { $0 }
        .eraseToAnyPublisher()
    }
  )
}
