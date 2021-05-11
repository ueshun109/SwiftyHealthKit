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

public struct Profile: Equatable {
  public enum Sex: Int, Equatable {
    case notSet
    case female
    case male
    case other
  }

  public var birthDate: DateComponents?
  public var height: Double?
  public var sex: Profile.Sex?
  public var weight: Double?

  public init(
    birthDate: DateComponents? = nil,
    height: Double? = nil,
    sex: Profile.Sex? = nil,
    weight: Double? = nil
  ) {
    self.birthDate = birthDate
    self.height = height
    self.sex = sex
    self.weight = weight
  }
}

public struct GetProfile {
  public private(set) var healthStore: HKHealthStore

  public init(healthStore: HKHealthStore) {
    self.healthStore = healthStore
  }

  public var birthDate: Future<DateComponents?, Error> {
    Future { completion in
      do {
        let dateOfBirth = try healthStore.dateOfBirthComponents()
        completion(.success(dateOfBirth))
      } catch {
        completion(.success(nil))
      }
    }
  }

  public var height: Future<Double?, Error> {
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
        else { completion(.success(nil)); return }
        let latestHeight = quantitySample.quantity.doubleValue(for: .meterUnit(with: .centi))
        completion(.success(latestHeight))
      }
      healthStore.execute(query)
    }
  }

  public var sex: Future<Profile.Sex?, Error> {
    Future { completion in
      do {
        let sex = try healthStore.biologicalSex().biologicalSex
        completion(.success(Profile.Sex(rawValue: sex.rawValue)))
      } catch {
        completion(.success(nil))
      }
    }
  }

  public var weight: Future<Double?, Error> {
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
        else { completion(.success(nil)); return }
        let latestHeight = quantitySample.quantity.doubleValue(for: .gramUnit(with: .kilo))
        completion(.success(latestHeight))
      }
      healthStore.execute(query)
    }
  }
}
