//
//  File.swift
//  
//
//  Created by uematsushun on 2021/05/01.
//

import Combine
import Foundation
import HealthKit

public struct HeartRate {
    public typealias HeartRatePerWorkout = (value: Double?, startDate: Date, endDate: Date)
    public private(set) var startDate: Date
    public private(set) var endDate: Date
    public private(set) var healthStore: HKHealthStore

    public init(startDate: Date, endDate: Date, healthStore: HKHealthStore) {
        self.startDate = startDate
        self.endDate = endDate
        self.healthStore = healthStore
    }

    /// Get bpm(beat per minutes)
    /// - Parameters:
    ///   - workouts: HKWorkout list
    ///   - quantityOptions: Options for statistics to calculate(e.g.: max, min, average etc.)
    /// - Returns: HeartRatePerWorkout list
    public func heartRate(
        during workouts: [HKWorkout],
        statisticsOptions: HKStatisticsOptions
    ) -> Future<[HeartRatePerWorkout], Error> {
        var heartRatePerWorkoutList: [HeartRatePerWorkout] = []
        return Future { completion in
            let type = HKObjectType.quantityType(forIdentifier: .heartRate)!
            var count = 0
            workouts.forEach { workout in
                let predicate = HKQuery.predicateForSamples(
                    withStart: workout.startDate,
                    end: workout.endDate,
                    options: .strictStartDate
                )
                let query = HKStatisticsQuery(
                    quantityType: type,
                    quantitySamplePredicate: predicate,
                    options: statisticsOptions
                ) { _, statistics, error in
                    guard let statistics = statistics, error == nil else { return }
                    var value: Double?
                    switch statisticsOptions {
                    case .discreteAverage:
                        value = statistics.averageQuantity()?.doubleValue(for: HKUnit(from: "count/min"))
                    case .discreteMax:
                        value = statistics.maximumQuantity()?.doubleValue(for: HKUnit(from: "count/min"))
                    case .discreteMin:
                        value = statistics.minimumQuantity()?.doubleValue(for: HKUnit(from: "count/min"))
                    default: break
                    }
                    heartRatePerWorkoutList.append(
                        HeartRatePerWorkout(
                            value: value,
                            startDate: workout.startDate,
                            endDate: workout.endDate
                        )
                    )
                    count += 1
                    if workouts.count == count {
                        completion(.success(heartRatePerWorkoutList))
                    }
                }
                healthStore.execute(query)
            }
        }
    }
}
