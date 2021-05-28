import Combine
import HealthKit
import SwiftUI
import SwiftyHealthKit

struct ContentView: View {
  @ObservedObject var viewModel = ContentViewModel()
  @State var isStart = false
  private var cancellables: [AnyCancellable] = []
  var body: some View {
    Button("Start") {
      viewModel.start()
      isStart.toggle()
    }
    .disabled(isStart)

    Button("Add") {
//      viewModel.add([HKMetadataKeyAverageMETs: HKQuantity(unit: HKUnit(from: "kg*hr"), doubleValue: 40)])
      viewModel.add(["OriginalCalorie": 40])
    }

    Button("End") {
      viewModel.end()
      isStart.toggle()
    }
    .disabled(!isStart)
    Text("\(viewModel.data)")
  }
}

final class ContentViewModel: ObservableObject {
  private var cancellables: [AnyCancellable] = []
  private let healthStore = HKHealthStore()
  private let authorization: Authorization = .live
  private let liveWorkout: LiveWorkout
  private let workout: WorkoutFetcher = .live
  @Published var data: Double = 0

  init() {
    self.liveWorkout = try! LiveWorkout(activityType: .swimming, healthStore: healthStore, locationType: .indoor, swimmingLocationType: .pool)
    liveWorkout.data
      .receive(on: DispatchQueue.main)
      .sink { _ in
      } receiveValue: { data in
        self.data = data.heartRate
      }
      .store(in: &self.cancellables)
  }

  func start() {
    let sendType: Set<HKSampleType> = [.workoutType()]
    let readType: Set<HKObjectType> = [
      HKObjectType.quantityType(forIdentifier: .heartRate)!,
      HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!
    ]
    authorization.request(sendType, readType)
      .mapError { $0 }
      .sink { _ in
      } receiveValue: { _ in
        self.liveWorkout.start()
      }
      .store(in: &self.cancellables)
  }

  func end() {
    liveWorkout.end()
  }

  func add(_ metadata: [String: Any]) {
    liveWorkout.addEvent(metadata)
      .sink { result in
        switch result {
        case let .failure(error):
          print(error.message)
        default: break
        }
      } receiveValue: { result in
        print(result)
      }
      .store(in: &self.cancellables)
  }
}

class Test {
  private var cancellables: [AnyCancellable] = []
  func test() {
    let calendar = Calendar.current
    let workout: WorkoutFetcher = .live
    let now = Date()
    let lastWeek = calendar.date(byAdding: .weekOfMonth, value: -1, to: now)!
    workout.workouts(.swimming, now, lastWeek)
      .sink { _ in

      } receiveValue: { result in
        print(result.count)
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
