import Combine
import HealthKit

public class WorkoutObserver {
  public private(set) var newWorkouts = PassthroughSubject<([HKWorkout], HKQueryAnchor?), Never>()

  private var queries: [HKAnchoredObjectQuery] = []

  public var start: (HKWorkoutActivityType, HKQueryAnchor?, Date?, Date?, Bool) -> Void = { _, _, _, _, _ in
    fatalError("Must implementation")
  }
}

public extension WorkoutObserver {
  static let live: WorkoutObserver = { () -> WorkoutObserver in
    var me = WorkoutObserver()

    me.start = { activityType, myAnchor, startDate, endDate, ownAppOnly in
      guard me.queries.isEmpty else { return }

      let compoundPredicate: (NSPredicate, NSPredicate?, NSPredicate) -> NSCompoundPredicate = { sample, source, workout in
        guard let source = source else { return NSCompoundPredicate(andPredicateWithSubpredicates: [sample, workout]) }
        return NSCompoundPredicate(andPredicateWithSubpredicates: [sample, source, workout])
      }

      let samplePredicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
      let sourcePredicate: NSPredicate? = ownAppOnly ? HKQuery.predicateForObjects(from: .default()) : nil
      let workoutPredicate = HKQuery.predicateForWorkouts(with: activityType)
      let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

      let handler: (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, Error?) -> Void =
        { query, samples, deletedObjects, newAnchor, error in
          guard let workouts = samples as? [HKWorkout] else { return }
          me.newWorkouts.send((workouts, newAnchor))
        }

      let query = HKAnchoredObjectQuery(
        type: HKObjectType.workoutType(),
        predicate: compoundPredicate(samplePredicate, sourcePredicate, workoutPredicate),
        anchor: myAnchor,
        limit: HKObjectQueryNoLimit,
        resultsHandler: handler
      )
      query.updateHandler = handler
      healthStore.execute(query)
      me.queries.append(query)
    }
    return me
  }()
}
