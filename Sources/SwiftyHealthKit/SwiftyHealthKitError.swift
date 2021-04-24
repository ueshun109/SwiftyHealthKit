//
//  File.swift
//  
//
//  Created by uematsushun on 2021/04/25.
//

import Foundation

public enum SwiftyHealthKitError: Error {
    case denied
    case unavailable
    case queryError(Error)

    var message: String {
        switch self {
        case .denied: return "Access to health data is not allowed."
        case .unavailable: return "HealthKit is unavailable for your device."
        case .queryError: return "Failed to get the health data."
        }
    }
}
