import Combine
import HealthKit

public struct WorkoutFetcher {
  var workouts: (HKWorkoutActivityType, Date, Date) -> Future<[HKWorkout], Error>

  /// Get metadata for workouts related to addition
  /// - Parameters:
  ///   - workouts: HKWorkout collection
  ///   - groupUnit: A unit that organizes data with DateComponent
  ///   - key: Dictionary key where metadata is stored
  /// - Returns: Dictionary
  public func metadata<T: AdditiveArithmetic>(
    associatedWith workouts: [HKWorkout],
    groupUnit: Set<Calendar.Component>,
    key: String
  ) -> Just<[DateComponents: T?]> {
    let calendar = Calendar.current
    var collections: [DateComponents: T?] = [:]
    workouts.forEach { workout in
      guard let metadata = workout.metadata else { return }
      let date = workout.startDate
      let unit = calendar.dateComponents(groupUnit, from: date)
      if let value1 = collections[unit] as? T, let value2 = metadata[key] as? T {
        collections[unit] = value1 + value2
      } else {
        collections[unit] = metadata[key] as? T
      }
    }
    return Just(collections)
  }

  /// Get time interval for workout
  /// - Parameters:
  ///   - workouts: HKWorkout collection
  ///   - groupUnit: A unit that organizes data with DateComponent
  /// - Returns: Dictionary
  public func timeInterval(
    associatedWith workouts: [HKWorkout],
    groupUnit: Set<Calendar.Component>
  ) -> Just<[DateComponents: TimeInterval]> {
    let calendar = Calendar.current
    var collections: [DateComponents: TimeInterval] = [:]
    workouts.forEach { workout in
      let date = workout.startDate
      let unit = calendar.dateComponents(groupUnit, from: date)
      if let value1 = collections[unit] {
        collections[unit] = value1 + workout.duration
      } else {
        collections[unit] = workout.duration
      }
    }
    return Just(collections)
  }
}

public extension WorkoutFetcher {
  static let live = Self(
    workouts: { activityType, startDate, endDate in
      Future { completion in
        let healthStore = HKHealthStore()
        let workoutPredicate = HKQuery.predicateForWorkouts(with: activityType)
        let samplePredicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let compoundPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [workoutPredicate, samplePredicate])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(
          sampleType: .workoutType(),
          predicate: compoundPredicate,
          limit: HKObjectQueryNoLimit,
          sortDescriptors: [sortDescriptor]
        ) { query, samples, error in
          guard let workouts = samples as? [HKWorkout], error == nil else { completion(.failure(error!)); return }
          completion(.success(workouts))
        }
        healthStore.execute(query)
      }
    }
  )
}

public extension WorkoutFetcher {
  static let mock = Self(
    workouts: { _, _, _ in
      Future { completion in
        let calendar = Calendar.current
        let workouts: [HKWorkout] = [
          .init(
            activityType: .running,
            start: Date(),
            end: Date(),
            duration: 30,
            totalEnergyBurned: .init(unit: HKUnit.kilocalorie(), doubleValue: 29),
            totalDistance: nil,
            metadata: ["ORIGINAL_CALORIES": 130]
          )
        ]
        completion(.success(workouts))
      }
    }
  )
}
