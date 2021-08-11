import Combine
import HealthKit

public enum ProfileType: CaseIterable {
  case birthDate
  case height
  case sex
  case weight

  public var dataType: HKObjectType {
    switch self {
    case .birthDate: return HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!
    case .height: return HKObjectType.quantityType(forIdentifier: .height)!
    case .sex: return HKObjectType.characteristicType(forIdentifier: .biologicalSex)!
    case .weight: return HKObjectType.quantityType(forIdentifier: .bodyMass)!
    }
  }

  public var unit: HKUnit? {
    switch self {
    case .height: return .meterUnit(with: .centi)
    case .weight: return .gramUnit(with: .kilo)
    default: return nil
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
  public var birthDate: DateComponents?
  public var height: Double?
  public var sex: Sex?
  public var weight: Double?

  public init(
    birthDate: DateComponents? = nil,
    height: Double? = nil,
    sex: Sex? = nil,
    weight: Double? = nil
  ) {
    self.birthDate = birthDate
    self.height = height
    self.sex = sex
    self.weight = weight
  }
}

public struct ProfileSaving {
  /// Save profile. However  you can't save birthDate and sex.
  /// see: https://developer.apple.com/documentation/healthkit/hkcharacteristictype
  public var save: (Profile) -> Future<Bool, SwiftyHealthKitError>
}

extension ProfileSaving {
  static let live = Self(
    save: { profile in
      Future { completion in
        let weightType: (Double?) -> (ProfileType, Double)? = { weight in
          guard let weight = weight else { return nil }
          return (ProfileType.weight, weight)
        }

        let heightType: (Double?) -> (ProfileType, Double)? = { height in
          guard let height = height else { return nil }
          return (ProfileType.height, height)
        }

        let samples: [HKObject] =
          [weightType(profile.weight),
           heightType(profile.height)
          ]
          .compactMap { tuple in
            guard let tuple = tuple,
                  let unit = tuple.0.unit,
                  let quantityType = tuple.0.dataType as? HKQuantityType
            else { return nil }
            return HKQuantitySample(
              type: quantityType,
              quantity: .init(unit: unit, doubleValue: tuple.1),
              start: Date(),
              end: Date()
            )
        }
        healthStore.save(samples) { result, error in
          if let error = error {
            completion(.failure(.failedToSave(error as NSError))); return
          }
          completion(.success(result))
        }
      }
    }
  )
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
          let latestWeight = quantitySample.quantity.doubleValue(for: .gramUnit(with: .kilo))
          completion(.success(latestWeight))
        }
        healthStore.execute(query)
      }
    }
  )
}
