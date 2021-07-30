import Foundation

public enum SwiftyHealthKitError: Equatable, LocalizedError {
  case denied
  case failedToSave(NSError)
  case liveWorkout(NSError)
  case notFound
  case query(NSError)
  case requestAuthorized(NSError)
  case session(NSError)
  case swimmingSession
  case unavailable

  public var message: String {
    switch self {
    case .denied:
      return "Access to health data is not allowed."
    case let .failedToSave(error):
      return error.localizedDescription
    case let .liveWorkout(error):
      return error.localizedDescription
    case .notFound:
      return "Not found"
    case let .query(error):
      return error.localizedDescription
    case let .requestAuthorized(error):
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
