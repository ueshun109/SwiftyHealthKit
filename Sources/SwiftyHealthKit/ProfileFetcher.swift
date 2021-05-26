import Combine
import HealthKit

public enum ProfileType {
  case birthDate
  case height
  case sex
  case weight

  var dataType: HKObjectType {
    switch self {
    case .birthDate: return HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!
    case .height: return HKObjectType.quantityType(forIdentifier: .height)!
    case .sex: return HKObjectType.characteristicType(forIdentifier: .biologicalSex)!
    case .weight: return HKObjectType.quantityType(forIdentifier: .bodyMass)!
    }
  }
}

public enum Sex: Int, Equatable {
  case notSet
  case female
  case male
  case other
}

public struct Profile: Equatable {
  var birthDate: DateComponents?
  var height: Double?
  var sex: Sex?
  var weight: Double?
}

public struct ProfileFetcher {
  public var birthDate: () -> Future<DateComponents?, SwiftyHealthKitError>
  public var height: () -> Future<Double?, SwiftyHealthKitError>
  public var sex: () -> Future<Sex?, SwiftyHealthKitError>
  public var weight: () -> Future<Double?, SwiftyHealthKitError>
}

public extension ProfileFetcher {
  static let live = Self(
    birthDate: {
      Future { completion in
        do {
          let dateOfBirth = try healthStore.dateOfBirthComponents()
          completion(.success(dateOfBirth))
        } catch {
          completion(.failure(.notFound))
        }
      }
    },
    height: {
      Future { completion in
        let dataType = HKObjectType.quantityType(forIdentifier: .height)!
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(
          sampleType: dataType,
          predicate: nil,
          limit: HKObjectQueryNoLimit,
          sortDescriptors: [sortDescriptor]
        ) { query, result, error in
          guard let sample = result?.last,
                let quantitySample = sample as? HKQuantitySample
          else { completion(.failure(.notFound)); return }
          let latestHeight = quantitySample.quantity.doubleValue(for: .meterUnit(with: .centi))
          completion(.success(latestHeight))
        }
        healthStore.execute(query)
      }
    },
    sex: {
      Future { completion in
        do {
          let sex = try healthStore.biologicalSex().biologicalSex
          completion(.success(Sex(rawValue: sex.rawValue)))
        } catch {
          completion(.failure(.notFound))
        }
      }
    },
    weight: {
      Future { completion in
        let dataType = HKObjectType.quantityType(forIdentifier: .bodyMass)!
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(
          sampleType: dataType,
          predicate: nil,
          limit: HKObjectQueryNoLimit,
          sortDescriptors: [sortDescriptor]
        ) { query, result, error in
          guard let sample = result?.last,
                let quantitySample = sample as? HKQuantitySample
          else { completion(.failure(.notFound)); return }
          let latestHeight = quantitySample.quantity.doubleValue(for: .gramUnit(with: .kilo))
          completion(.success(latestHeight))
        }
        healthStore.execute(query)
      }
    }
  )
}
