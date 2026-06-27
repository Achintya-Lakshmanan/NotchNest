import Foundation

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Fetches weather for State College, PA via Open-Meteo (no API key).
enum WeatherService {
    // State College, PA
    private static let latitude = 40.7934
    private static let longitude = -77.8600
    private static let city = "State College"

    private struct Forecast: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let weather_code: Int
            let is_day: Int
        }
        struct Daily: Decodable {
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
        }
        struct Hourly: Decodable {
            let time: [String]
            let temperature_2m: [Double]
            let weather_code: [Int]
            let precipitation_probability: [Int?]?
            let is_day: [Int]?
        }
        let current: Current
        let daily: Daily
        let hourly: Hourly
    }

    private static let hourParser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    private static let hourLabel: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h a"
        return f
    }()

    static func fetch(completion: @escaping (WeatherInfo?) -> Void) {
        let metric = Locale.current.measurementSystem == .metric
        let unitParam = metric ? "celsius" : "fahrenheit"
        let unitLabel = metric ? "°C" : "°F"

        let urlStr = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&current=temperature_2m,weather_code,is_day&daily=temperature_2m_max,temperature_2m_min&hourly=temperature_2m,weather_code,precipitation_probability,is_day&temperature_unit=\(unitParam)&timezone=auto&forecast_days=2"
        guard let url = URL(string: urlStr) else { completion(nil); return }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let f = try? JSONDecoder().decode(Forecast.self, from: data) else {
                DispatchQueue.main.async { completion(nil) }; return
            }
            let info = WeatherInfo(
                temp: Int(f.current.temperature_2m.rounded()),
                high: Int((f.daily.temperature_2m_max.first ?? f.current.temperature_2m).rounded()),
                low: Int((f.daily.temperature_2m_min.first ?? f.current.temperature_2m).rounded()),
                unit: unitLabel,
                code: f.current.weather_code,
                isDay: f.current.is_day == 1,
                city: city,
                hourly: hourlyForecasts(from: f.hourly)
            )
            DispatchQueue.main.async { completion(info) }
        }.resume()
    }

    /// Next 12 hours starting from the current hour.
    private static func hourlyForecasts(from h: Forecast.Hourly) -> [HourForecast] {
        let cal = Calendar.current
        let startOfHour = cal.date(from: cal.dateComponents([.year, .month, .day, .hour], from: Date())) ?? Date()

        var result: [HourForecast] = []
        for (i, timeStr) in h.time.enumerated() {
            guard let date = hourParser.date(from: timeStr), date >= startOfHour else { continue }
            let label = result.isEmpty ? "Now" : hourLabel.string(from: date)
            let isDay = (h.is_day?[safe: i] ?? 1) == 1
            let precip = (h.precipitation_probability?[safe: i] ?? nil) ?? 0
            result.append(HourForecast(
                id: timeStr,
                label: label,
                temp: Int((h.temperature_2m[safe: i] ?? 0).rounded()),
                code: h.weather_code[safe: i] ?? 0,
                isDay: isDay,
                precip: precip
            ))
            if result.count >= 12 { break }
        }
        return result
    }
}
