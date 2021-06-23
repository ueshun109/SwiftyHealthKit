import Combine
import HealthKit

public struct HeartRateFetcher {
  public typealias Arguments = (Date, Date, HKStatisticsOptions, HKWorkoutActivityType, Bool)
  public typealias Response = (value: Double?, startDate: Date, endDate: Date)

  /// Get bpm(beat per minutes) during workout.
  public var duringWorkout: ([HKWorkout], HKStatisticsOptions) -> Future<[Response], SwiftyHealthKitError>
  /// Monitor changes in heart rate.
  public var liveHeartRate: (Date, DateComponents, HKStatisticsOptions) -> PassthroughSubject<Double, Never>
}

public extension HeartRateFetcher {
  static let live = Self(
    duringWorkout: { workouts, option in
      var heartRates: [Response] = []
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
            options: option
          ) { _, statistics, error in
            guard let statistics = statistics, error == nil else { return }
            var value: Double?
            switch option {
            case .discreteAverage:
              value = statistics.averageQuantity()?.doubleValue(for: HKUnit(from: "count/min"))
            case .discreteMax:
              value = statistics.maximumQuantity()?.doubleValue(for: HKUnit(from: "count/min"))
            case .discreteMin:
              value = statistics.minimumQuantity()?.doubleValue(for: HKUnit(from: "count/min"))
            default: break
            }
            heartRates.append(
              Response(
                value: value,
                startDate: workout.startDate,
                endDate: workout.endDate
              )
            )
            count += 1
            if workouts.count == count {
              completion(.success(heartRates))
            }
          }
          healthStore.execute(query)
        }
      }
    },
    liveHeartRate: { anchorDate, timeInterval, options in
      let query = HKStatisticsCollectionQuery(
        quantityType: .quantityType(forIdentifier: .heartRate)!,
        quantitySamplePredicate: nil,
        options: options,
        anchorDate: anchorDate,
        intervalComponents: timeInterval
      )
      var startDate = anchorDate
      let subject = PassthroughSubject<Double, Never>()
      query.initialResultsHandler = { _, _, _ in }
      query.statisticsUpdateHandler = { query, statistics, collection, error in
        let endDate = Date()
        collection?.enumerateStatistics(from: startDate, to: endDate) { stats, stop in
          var value: Double?
          switch options {
          case .discreteAverage:
            value = stats.averageQuantity()?.doubleValue(for: HKUnit(from: "count/min"))
          case .discreteMax:
            value = stats.maximumQuantity()?.doubleValue(for: HKUnit(from: "count/min"))
          case .discreteMin:
            value = stats.minimumQuantity()?.doubleValue(for: HKUnit(from: "count/min"))
          default: break
          }
          guard let bpm = value else { return }
          subject.send(bpm)
          startDate = endDate
        }
      }
      healthStore.execute(query)
      return subject
    }
  )
}
