import Combine
import HealthKit

public struct Authorization {
  public var request: (Set<HKSampleType>?, Set<HKObjectType>?) -> Future<Bool, SwiftyHealthKitError>
}

public extension Authorization {
  static let live = Self(
    request: { saveDataType, readDataType in
      Future { completion in
        healthStore.requestAuthorization(toShare: saveDataType, read: readDataType) { result, error in
          guard let error = error else { completion(.success(result)); return }
          logger.log("Permission request failed.")
          completion(.failure(SwiftyHealthKitError.requestAuthorized(error as NSError)))
        }
      }
    }
  )
}

public extension Authorization {
  static let mock = Self(
    request: { _, _ in
      Future { completion in
        completion(.success(true))
      }
    }
  )
}

public extension Authorization {
  static let failed = Self(
    request: { _, _ in
      Future { completion in
        completion(.failure(SwiftyHealthKitError.requestAuthorized(NSError(domain: "com.ueshun", code: 1))))
      }
    }
  )
}
