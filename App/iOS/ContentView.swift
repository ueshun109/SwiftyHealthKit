import Combine
import HealthKit
import SwiftUI
import SwiftyHealthKit

struct ContentView: View {
  @ObservedObject private var viewModel = ContentViewModel()
  private var cancellables: [AnyCancellable] = []
  var body: some View {
    VStack {
      Text("\(viewModel.calorie)")
      Button("request") {
        viewModel.request()
      }
    }
  }
}

final class ContentViewModel: ObservableObject {
  private var cancellables: [AnyCancellable] = []
  private let auth: Authorization = .live
  private let workout: WorkoutFetcher = .live
  @Published var calorie: Double = 0

  func request() {
    let readType: Set<HKObjectType> = [
      HKObjectType.quantityType(forIdentifier: .heartRate)!,
      HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
      .workoutType()
    ]
    auth.request(nil, readType)
      .mapError { $0 }
      .flatMap { [unowned self] _ -> Future<[HKWorkout], Error> in
        let calendar = Calendar.current
        let current = calendar.date(byAdding: .hour, value: 9, to: Date())!
        let startToday = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: startToday)!
        return self.workout.workouts(.swimming, yesterday , startToday)
      }
      .mapError { $0 }
      .flatMap { [unowned self] workouts -> Just<[DateComponents: Double?]> in
        self.workout.metadataFromEvent(associatedWith: workouts, groupUnit: [.year, .month, .day], key: "OriginalCalorie")
      }
      .receive(on: DispatchQueue.main)
      .sink { result in
        switch result {
        case let .failure(error):
          print(error.localizedDescription)
        default: break
        }
      } receiveValue: { [unowned self] metadata in
        print(metadata)
        guard let key = metadata.first?.key,
              let value = metadata[key] as? Double
        else { return }
        self.calorie = value
      }
      .store(in: &self.cancellables)
  }
}

#if DEBUG
struct ContenView_Preview: PreviewProvider {
  static var previews: some View {
    ContentView()
  }
}
#endif
