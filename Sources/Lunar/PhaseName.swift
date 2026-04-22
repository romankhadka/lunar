import Foundation

enum PhaseName: String, CaseIterable {
    case new              = "new"
    case waxingCrescent   = "waxing_crescent"
    case firstQuarter     = "first_quarter"
    case waxingGibbous    = "waxing_gibbous"
    case full             = "full"
    case waningGibbous    = "waning_gibbous"
    case lastQuarter      = "last_quarter"
    case waningCrescent   = "waning_crescent"

    var displayName: String {
        switch self {
        case .new:             return "New Moon"
        case .waxingCrescent:  return "Waxing Crescent"
        case .firstQuarter:    return "First Quarter"
        case .waxingGibbous:   return "Waxing Gibbous"
        case .full:            return "Full Moon"
        case .waningGibbous:   return "Waning Gibbous"
        case .lastQuarter:     return "Last Quarter"
        case .waningCrescent:  return "Waning Crescent"
        }
    }
}
