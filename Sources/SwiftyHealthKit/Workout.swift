//
//  File.swift
//  
//
//  Created by uematsushun on 2021/05/01.
//

import Combine
import Foundation
import HealthKit

public struct Workout {
  public private(set) var startDate: Date
  public private(set) var endDate: Date
  public private(set) var healthStore: HKHealthStore

  public init(startDate: Date, endDate: Date, healthStore: HKHealthStore) {
    self.startDate = startDate
    self.endDate = endDate
    self.healthStore = healthStore
  }

  public func workouts(activityType: HKWorkoutActivityType) -> Future<[HKWorkout], Error> {
    Future { completion in
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
}
