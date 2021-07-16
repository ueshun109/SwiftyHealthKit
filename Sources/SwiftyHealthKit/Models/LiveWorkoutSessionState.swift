import HealthKit

#if os(watchOS)
public enum LiveWorkoutSessionState: Equatable {
  case notStarted(Date?)
  case prepared(Date?)
  case running(Date?)
  case paused(Date?)
  case stopped(Date?)
  case ended(Date?)

  init(state: HKWorkoutSessionState, date: Date?) {
    switch state {
    case .notStarted:
      self = .notStarted(date)
    case .prepared:
      self = .prepared(date)
    case .running:
      self = .running(date)
    case .paused:
      self = .running(date)
    case .stopped:
      self = .stopped(date)
    case .ended:
      self = .ended(date)
    @unknown default:
      fatalError()
    }
  }
}
#endif
