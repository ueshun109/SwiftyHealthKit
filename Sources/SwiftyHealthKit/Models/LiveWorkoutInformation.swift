/// Information during workout.
public struct LiveWorkoutInformation: Equatable {
  public var activeCalories: Double = 0
  public var distance: Double = 0
  public var heartRate: Double = 0

  public init() {}

  public mutating func update(
    activeCalories: Double? = nil,
    distance: Double? = nil,
    heartRate: Double? = nil
  ) {
    self.activeCalories = activeCalories ?? self.activeCalories
    self.distance = distance ?? self.distance
    self.heartRate = heartRate ?? self.heartRate
  }
}
