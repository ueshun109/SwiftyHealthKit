import Foundation

public enum SwiftyHealthKitError: Equatable, LocalizedError {
  case denied
  case liveWorkout(NSError)
  case query(NSError)
  case session(NSError)
  case swimmingSession
  case unavailable

  public var message: String {
    switch self {
    case .denied:
      return "Access to health data is not allowed."
    case let .liveWorkout(error):
      return error.localizedDescription
    case let .query(error):
      return error.localizedDescription
    case let .session(error):
      return error.localizedDescription
    case .swimmingSession:
      return "When activityType is swimming, please set also swimmingLocationType."
    case .unavailable:
      return "HealthKit is unavailable for your device."
    }
  }
}
