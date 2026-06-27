import Foundation

/// Fetches weather with no API key: IP geolocation (ipapi.co) + Open-Meteo.
enum WeatherService {
    private struct Geo: Decodable {
        let latitude: Double
        let longitude: Double
        let city: String?
    }
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
        let current: Current
        let daily: Daily
    }

    static func fetch(completion: @escaping (WeatherInfo?) -> Void) {
        let metric = Locale.current.measurementSystem == .metric
        let unitParam = metric ? "celsius" : "fahrenheit"
        let unitLabel = metric ? "°C" : "°F"

        geolocate { geo in
            guard let geo else { completion(nil); return }
            let urlStr = "https://api.open-meteo.com/v1/forecast?latitude=\(geo.latitude)&longitude=\(geo.longitude)&current=temperature_2m,weather_code,is_day&daily=temperature_2m_max,temperature_2m_min&temperature_unit=\(unitParam)&timezone=auto&forecast_days=1"
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
                    city: geo.city ?? "Weather"
                )
                DispatchQueue.main.async { completion(info) }
            }.resume()
        }
    }

    private static func geolocate(_ completion: @escaping (Geo?) -> Void) {
        guard let url = URL(string: "https://ipapi.co/json/") else { completion(nil); return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let geo = data.flatMap { try? JSONDecoder().decode(Geo.self, from: $0) }
            completion(geo)
        }.resume()
    }
}
