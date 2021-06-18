import Combine
import HealthKit

public struct BurnedCaloriesFetcher {
  /// Get burned calories.
  public var burnedCalories: (Date, Date, Date, DateComponents, HKStatisticsOptions, Bool) -> Future<[Double], SwiftyHealthKitError>
}

public extension BurnedCaloriesFetcher {
  static let live = Self(
    burnedCalories: { anchorDate, startDate, endDate, interval, options, ownAppOnly in
      Future { completion in
        let sourcePredicate: NSPredicate? = ownAppOnly ? HKQuery.predicateForObjects(from: .default()) : nil
        let query = HKStatisticsCollectionQuery(
          quantityType: .quantityType(forIdentifier: .activeEnergyBurned)!,
          quantitySamplePredicate: sourcePredicate,
          options: options,
          anchorDate: anchorDate,
          intervalComponents: interval
        )
        query.initialResultsHandler = { query, collection, error in
          if let error = error {
            completion(.failure(.query(error as NSError))); return
          }
          var caloriesPerUnit: [Double] = []
          collection?.enumerateStatistics(from: startDate, to: endDate) { statistics, stop in
            guard let calories = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) else { return }
            caloriesPerUnit.append(calories)
          }
          completion(.success(caloriesPerUnit))
        }
        healthStore.execute(query)
      }
    }
  )
}
