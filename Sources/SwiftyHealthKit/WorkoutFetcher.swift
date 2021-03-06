import Combine
import HealthKit

public struct WorkoutFetcher {
  /// Get workout data.
  public var workouts: (HKWorkoutActivityType, Date?, Date?, Bool) -> Future<[HKWorkout], SwiftyHealthKitError>

  /// Get metadata for workouts related to addition
  /// - Parameters:
  ///   - workouts: HKWorkout collection
  ///   - groupUnit: A unit that organizes data with DateComponent
  ///   - key: Dictionary key where metadata is stored
  /// - Returns: Dictionary
  public func metadataFromEvent<T: AdditiveArithmetic>(
    associatedWith workouts: [HKWorkout],
    groupUnit: Set<Calendar.Component>,
    key: String
  ) -> Just<[DateComponents: T?]> {
    let calendar = Calendar.current
    var collections: [DateComponents: T?] = [:]
    workouts.forEach { workout in
      guard let events = workout.workoutEvents else { return }
      events.forEach { event in
        guard let metadata = event.metadata else { return }
        let date = workout.startDate
        let unit = calendar.dateComponents(groupUnit, from: date)
        if let value1 = collections[unit] as? T, let value2 = metadata[key] as? T {
          collections[unit] = value1 + value2
        } else {
          collections[unit] = metadata[key] as? T
        }
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
    workouts: { activityType, startDate, endDate, ownAppOnly in
      Future { completion in
        let compoundPredicate: (NSPredicate, NSPredicate?, NSPredicate) -> NSCompoundPredicate = { sample, source, workout in
          guard let source = source else { return NSCompoundPredicate(andPredicateWithSubpredicates: [sample, workout]) }
          return NSCompoundPredicate(andPredicateWithSubpredicates: [sample, source, workout])
        }
        let samplePredicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sourcePredicate: NSPredicate? = ownAppOnly ? HKQuery.predicateForObjects(from: .default()) : nil
        let workoutPredicate = HKQuery.predicateForWorkouts(with: activityType)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(
          sampleType: .workoutType(),
          predicate: compoundPredicate(samplePredicate, sourcePredicate, workoutPredicate),
          limit: HKObjectQueryNoLimit,
          sortDescriptors: [sortDescriptor]
        ) { query, samples, error in
          guard let workouts = samples as? [HKWorkout], error == nil else {
            completion(.failure(.query(error! as NSError)))
            return
          }
          completion(.success(workouts))
        }
        healthStore.execute(query)
      }
    }
  )
}

public extension WorkoutFetcher {
  static let mock = Self(
    workouts: { _, _, _, _ in
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
