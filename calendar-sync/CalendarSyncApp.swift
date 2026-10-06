import Foundation
import Network
import Security
import CryptoKit
import AppKit
import EventKit

@main
struct CalendarSync {
    static func main() {
        let arguments = CommandLine.arguments
        let hasArgument = { (arg: String) in arguments.contains(arg) }

        do {
            try CalendarSync().run(clearAll: hasArgument("--clear-all"), showHelp: hasArgument("--help"))
        } catch {
            print("Error: \(error)")
            exit(1)
        }
    }

    func run(clearAll: Bool = false, showHelp: Bool = false) throws {
        // Load .env file
        func loadEnvFile() {
            var envPaths: [String] = []

            // Look in directory where binary is located
            if let execPath = ProcessInfo.processInfo.arguments.first {
                let binaryDir = (execPath as NSString).deletingLastPathComponent
                envPaths.append(binaryDir + "/.env")
                envPaths.append((binaryDir as NSString).deletingLastPathComponent + "/.env")
            }

            // Look in standard locations
            envPaths.append(FileManager.default.currentDirectoryPath + "/.env")
            envPaths.append(FileManager.default.homeDirectoryForCurrentUser.path + "/.calendar-sync/.env")

            for envPath in envPaths {
                guard FileManager.default.fileExists(atPath: envPath) else { continue }

                do {
                    let content = try String(contentsOfFile: envPath, encoding: .utf8)
                    for line in content.components(separatedBy: .newlines) {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty && !trimmed.hasPrefix("#") else { continue }

                        let parts = trimmed.components(separatedBy: "=")
                        guard parts.count == 2 else { continue }

                        let key = parts[0].trimmingCharacters(in: .whitespaces)
                        let value = parts[1].trimmingCharacters(in: .whitespaces)
                        setenv(key, value, 1)
                    }
                    return
                } catch {
                    continue
                }
            }
        }

        loadEnvFile()

        if showHelp {
            print("""
            Calendar Sync - Sync events from macOS Calendar to Google Calendar

            Usage:
              calendar-sync                 Start syncing (or resume if already configured)
              calendar-sync --clear-all     Delete all synced events from Google Calendar
              calendar-sync --help          Show this help message

            Notes:
              - Events you create manually in Google Calendar are never touched
              - Only events synced by this tool (marked with sync ID) can be deleted
              - First run will prompt you to select which local calendar to sync
            """)
            return
        }

        // MARK: - Constants

        guard let clientID = ProcessInfo.processInfo.environment["CALENDAR_SYNC_CLIENT_ID"] else {
            print("ERROR: CALENDAR_SYNC_CLIENT_ID environment variable is required")
            exit(1)
        }

        guard let clientSecret = ProcessInfo.processInfo.environment["CALENDAR_SYNC_CLIENT_SECRET"] else {
            print("ERROR: CALENDAR_SYNC_CLIENT_SECRET environment variable is required")
            exit(1)
        }

        let scope =
            "https://www.googleapis.com/auth/calendar.calendarlist.readonly " +
            "https://www.googleapis.com/auth/calendar.app.created"

        // MARK: - Helpers

        func base64URL(_ data: Data) -> String {
            data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }

        func randomString(_ length: Int) -> String {
            var bytes = [UInt8](repeating: 0, count: length)

            for i in 0..<length {
                bytes[i] = UInt8.random(in: 0...255)
            }

            return base64URL(Data(bytes))
        }

        func urlEncode(_ value: String) -> String {
            value.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed
            )!
        }

        // MARK: - Settings Management

        // Must be run from inside the .app bundle (./bin/calendar-sync.app/Contents/MacOS/calendar-sync),
        // not as a bare copied executable, so Bundle.main resolves the real bundle identifier and
        // .standard consistently maps to the com.jondaley.calendar-sync domain.
        let settingsDomain = Bundle.main.bundleIdentifier ?? "com.jondaley.calendar-sync"
        let appDefaults = UserDefaults.standard
        let settingsKey = "settings"
        let sourceCalendarIDKey = "sourceCalendarID"
        let destCalendarIDKey = "destCalendarID"

        func loadSettings() -> [String: String]? {
            guard let data = appDefaults.data(forKey: settingsKey),
                  let settings = try? JSONDecoder().decode([String: String].self, from: data) else {
                return nil
            }
            return settings
        }

        func saveSettings(_ settings: [String: String]) throws {
            let data = try JSONEncoder().encode(settings)
            appDefaults.set(data, forKey: settingsKey)
        }

        // MARK: - EventKit Helpers

        func listLocalCalendars() -> [(id: String, name: String)] {
            let eventStore = EKEventStore()
            var calendars: [(id: String, name: String)] = []

            let authStatus = EKEventStore.authorizationStatus(for: .event)
            print("DEBUG: EventKit authorization status: \(authStatus.rawValue)")

            if authStatus == .notDetermined {
                print("DEBUG: Requesting EventKit permission...")
                let semaphore = DispatchSemaphore(value: 0)
                var granted = false

                Task {
                    do {
                        granted = try await eventStore.requestFullAccessToEvents()
                        semaphore.signal()
                    } catch {
                        print("ERROR: Failed to request permission: \(error)")
                        semaphore.signal()
                    }
                }

                semaphore.wait()
                print("DEBUG: Permission granted: \(granted)")
                if !granted {
                    print("ERROR: Calendar permission denied")
                    return []
                }
            } else if authStatus == .denied || authStatus == .restricted {
                print("ERROR: Calendar access is denied. Please enable in System Settings > Privacy & Security > Calendar")
                return []
            }

            let allCalendars = eventStore.calendars(for: .event)
            print("DEBUG: Found \(allCalendars.count) calendars total")

            for calendar in allCalendars {
                let typeString: String
                switch calendar.type {
                case .local:
                    typeString = "local"
                case .calDAV:
                    typeString = "CalDAV"
                case .exchange:
                    typeString = "Exchange"
                case .subscription:
                    typeString = "Subscription"
                case .birthday:
                    typeString = "Birthday"
                @unknown default:
                    typeString = "Unknown"
                }

                print("DEBUG: Calendar: '\(calendar.title)' (type: \(typeString), writable: \(calendar.allowsContentModifications))")

                if calendar.allowsContentModifications {
                    calendars.append((id: calendar.calendarIdentifier, name: calendar.title))
                }
            }

            return calendars.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }

        func getUserCalendarSelection(_ calendars: [(id: String, name: String)]) -> String? {
            print("")
            print("Available local calendars:")
            for (index, calendar) in calendars.enumerated() {
                print("  \(index + 1). \(calendar.name)")
            }
            print("")
            print("Which calendar would you like to sync from?")

            if let input = readLine(), let index = Int(input), index > 0, index <= calendars.count {
                return calendars[index - 1].id
            }

            print("Invalid selection.")
            return nil
        }

        func chooseOrCreateDestinationCalendar(accessToken: String, calendarID: String) throws -> String {
            print("")
            print("Fetching your Google Calendars...")

            var existingCalendars: [[String: Any]] = []
            do {
                let allCalendars = try listGoogleCalendars(accessToken: accessToken)
                print("Checking which calendars this app can access...")
                existingCalendars = allCalendars.filter { cal in
                    guard let id = cal["id"] as? String else { return false }
                    if case .exists = checkGoogleCalendarExists(accessToken: accessToken, calendarID: id) {
                        return true
                    }
                    return false
                }.sorted {
                    let lhs = $0["summary"] as? String ?? ""
                    let rhs = $1["summary"] as? String ?? ""
                    return lhs.localizedStandardCompare(rhs) == .orderedAscending
                }
            } catch {
                print("Could not fetch existing calendars (API may not be enabled).")
            }

            print("")
            print("What would you like to do?")

            if !existingCalendars.isEmpty {
                print("Your existing calendars (created by this app):")
                for (index, cal) in existingCalendars.enumerated() {
                    let name = cal["summary"] as? String ?? "Unknown"
                    print("  \(index + 1). \(name)")
                }
                print("  \(existingCalendars.count + 1). Create new 'Corporate Calendar' calendar")
                print("")
                print("Choose an option:")

                if let input = readLine(), let choice = Int(input), choice > 0 {
                    if choice <= existingCalendars.count {
                        if let id = existingCalendars[choice - 1]["id"] as? String,
                           let name = existingCalendars[choice - 1]["summary"] as? String {
                            print("Using existing calendar: \(name)")
                            return id
                        }
                    } else if choice == existingCalendars.count + 1 {
                        print("Creating new 'Corporate Calendar' calendar...")
                        return try createGoogleCalendar(accessToken: accessToken, calendarID: calendarID)
                    }
                }
            } else {
                print("Creating new 'Corporate Calendar' calendar...")
                return try createGoogleCalendar(accessToken: accessToken, calendarID: calendarID)
            }

            throw NSError(domain: "Setup", code: -1, userInfo: [NSLocalizedDescriptionKey: "No calendar selected"])
        }

        func createGoogleCalendar(accessToken: String, calendarID: String) throws -> String {
            var calendarRequest = URLRequest(
                url: URL(string: "https://www.googleapis.com/calendar/v3/calendars")!
            )

            calendarRequest.httpMethod = "POST"
            calendarRequest.setValue(
                "Bearer \(accessToken)",
                forHTTPHeaderField: "Authorization"
            )
            calendarRequest.setValue(
                "application/json",
                forHTTPHeaderField: "Content-Type"
            )

            let calendarBody: [String: Any] = [
                "summary": "Corporate Calendar",
                "description": "One-way copy of corporate work calendar"
            ]

            calendarRequest.httpBody =
                try JSONSerialization.data(withJSONObject: calendarBody)

            let calendarSemaphore = DispatchSemaphore(value: 0)

            var calendarData: Data?
            var calendarRequestError: Error?

            URLSession.shared.dataTask(with: calendarRequest) {
                data, response, error in

                calendarData = data
                calendarRequestError = error

                calendarSemaphore.signal()

            }.resume()

            calendarSemaphore.wait()

            if let error = calendarRequestError {
                throw error
            }

            guard let calendarData else {
                throw NSError(domain: "GoogleCalendar", code: -1, userInfo: [NSLocalizedDescriptionKey: "No Calendar API response"])
            }

            guard let calendarJSON =
                try? JSONSerialization.jsonObject(with: calendarData)
                as? [String: Any]
            else {
                throw NSError(domain: "GoogleCalendar", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse calendar response"])
            }

            if let error = calendarJSON["error"] {
                if let errorObject = error as? [String: Any] {
                    let message = errorObject["message"] as? String ?? "Unknown error"
                    throw NSError(domain: "GoogleCalendar", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
                }
                throw NSError(domain: "GoogleCalendar", code: -1, userInfo: [NSLocalizedDescriptionKey: "Google Calendar API error"])
            }

            guard let id = calendarJSON["id"] as? String else {
                throw NSError(domain: "GoogleCalendar", code: -1, userInfo: [NSLocalizedDescriptionKey: "No calendar ID in response"])
            }

            print("Created calendar: \(calendarJSON["summary"] as? String ?? id)")
            return id
        }

        func getEventsFromCalendar(calendarID: String, eventStore: EKEventStore) -> [EKEvent] {
            guard let calendar = eventStore.calendar(withIdentifier: calendarID) else {
                print("Calendar not found: \(calendarID)")
                return []
            }

            let startDate = Date()
            let endDate = Date(timeIntervalSinceNow: 90 * 24 * 60 * 60)

            let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: [calendar])
            return eventStore.events(matching: predicate)
        }

        func getAccessToken(clientID: String, clientSecret: String, refreshToken: String) throws -> String {
            var request = URLRequest(
                url: URL(string: "https://oauth2.googleapis.com/token")!
            )

            request.httpMethod = "POST"
            request.setValue(
                "application/x-www-form-urlencoded",
                forHTTPHeaderField: "Content-Type"
            )

            let parameters: [String: String] = [
                "client_id": clientID,
                "client_secret": clientSecret,
                "refresh_token": refreshToken,
                "grant_type": "refresh_token"
            ]

            request.httpBody = parameters
                .map { "\(urlEncode($0.key))=\(urlEncode($0.value))" }
                .joined(separator: "&")
                .data(using: .utf8)

            let semaphore = DispatchSemaphore(value: 0)
            var tokenData: Data?
            var tokenError: Error?
            var httpStatus: Int = 0

            URLSession.shared.dataTask(with: request) { data, response, error in
                tokenData = data
                tokenError = error
                if let httpResponse = response as? HTTPURLResponse {
                    httpStatus = httpResponse.statusCode
                }
                semaphore.signal()
            }.resume()

            semaphore.wait()

            if let error = tokenError {
                throw error
            }

            let json = tokenData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }

            if let accessToken = json?["access_token"] as? String {
                return accessToken
            }

            var errorMessage = "Failed to refresh token (HTTP \(httpStatus))"
            if let json {
                let code = json["error"] as? String ?? "unknown_error"
                let description = json["error_description"] as? String ?? ""
                errorMessage = "Failed to refresh token: \(code) - \(description)"
            }
            throw NSError(domain: "OAuth", code: httpStatus, userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }

        func getSyncMarker(event: EKEvent) -> String {
            let dateFormatter = ISO8601DateFormatter()
            let title = event.title ?? "Untitled"
            let startDate = dateFormatter.string(from: event.startDate)
            return "sync:\(title):\(startDate)"
        }

        func formatEventDisplay(title: String, startDate: Date) -> String {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .short
            dateFormatter.timeStyle = .short
            let dateStr = dateFormatter.string(from: startDate)
            return "\(title) (\(dateStr))"
        }

        func googleEventStartDate(_ event: [String: Any]) -> Date? {
            guard let startObj = event["start"] as? [String: Any] else { return nil }

            if let dateTime = startObj["dateTime"] as? String {
                return ISO8601DateFormatter().date(from: dateTime)
            }
            if let date = startObj["date"] as? String {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                dateFormatter.timeZone = TimeZone(identifier: "UTC")
                return dateFormatter.date(from: date)
            }
            return nil
        }

        func formatGoogleEventDisplay(event: [String: Any]) -> String {
            let title = event["summary"] as? String ?? "Untitled"
            var dateStr = ""

            if let startObj = event["start"] as? [String: Any] {
                if let dateTime = startObj["dateTime"] as? String {
                    dateStr = String(dateTime.prefix(16))
                } else if let date = startObj["date"] as? String {
                    dateStr = date
                }
            }

            if dateStr.isEmpty {
                return title
            }
            return "\(title) (\(dateStr))"
        }

        func listGoogleCalendars(accessToken: String) throws -> [[String: Any]] {
            var request = URLRequest(
                url: URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")!
            )

            request.httpMethod = "GET"
            request.setValue(
                "Bearer \(accessToken)",
                forHTTPHeaderField: "Authorization"
            )

            let semaphore = DispatchSemaphore(value: 0)
            var responseData: Data?
            var resultError: Error?
            var httpStatus: Int = 0

            URLSession.shared.dataTask(with: request) { data, response, error in
                responseData = data
                resultError = error
                if let httpResponse = response as? HTTPURLResponse {
                    httpStatus = httpResponse.statusCode
                }
                semaphore.signal()
            }.resume()

            semaphore.wait()

            if let error = resultError {
                throw error
            }

            guard let data = responseData else {
                throw NSError(domain: "GoogleCalendar", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response data"])
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                let responseStr = String(data: data, encoding: .utf8) ?? "<unable to decode>"
                print("DEBUG: Calendar list response: \(responseStr)")
                throw NSError(domain: "GoogleCalendar", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse calendars"])
            }

            if let error = json["error"] {
                if let errorObj = error as? [String: Any], let msg = errorObj["message"] as? String {
                    throw NSError(domain: "GoogleCalendar", code: httpStatus, userInfo: [NSLocalizedDescriptionKey: msg])
                }
                throw NSError(domain: "GoogleCalendar", code: httpStatus, userInfo: [NSLocalizedDescriptionKey: "Google API error"])
            }

            let items = json["items"] as? [[String: Any]] ?? []
            return items
        }

        enum CalendarCheckResult {
            case exists
            case notFound
            case error(String)
        }

        func checkGoogleCalendarExists(accessToken: String, calendarID: String) -> CalendarCheckResult {
            var request = URLRequest(
                url: URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(calendarID)")!
            )

            request.httpMethod = "GET"
            request.setValue(
                "Bearer \(accessToken)",
                forHTTPHeaderField: "Authorization"
            )

            let semaphore = DispatchSemaphore(value: 0)
            var httpStatus: Int = 0
            var resultError: Error?

            URLSession.shared.dataTask(with: request) { _, response, error in
                resultError = error
                if let httpResponse = response as? HTTPURLResponse {
                    httpStatus = httpResponse.statusCode
                }
                semaphore.signal()
            }.resume()

            semaphore.wait()

            if let error = resultError {
                return .error(error.localizedDescription)
            }

            switch httpStatus {
            case 200:
                return .exists
            case 404:
                return .notFound
            default:
                return .error("HTTP \(httpStatus)")
            }
        }

        func listGoogleCalendarEvents(accessToken: String, calendarID: String) throws -> [String: Any] {
            var request = URLRequest(
                url: URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(calendarID)/events?maxResults=2500")!
            )

            request.httpMethod = "GET"
            request.setValue(
                "Bearer \(accessToken)",
                forHTTPHeaderField: "Authorization"
            )

            let semaphore = DispatchSemaphore(value: 0)
            var responseData: Data?
            var resultError: Error?
            var httpStatus: Int = 0

            URLSession.shared.dataTask(with: request) { data, response, error in
                responseData = data
                resultError = error
                if let httpResponse = response as? HTTPURLResponse {
                    httpStatus = httpResponse.statusCode
                }
                semaphore.signal()
            }.resume()

            semaphore.wait()

            if let error = resultError {
                throw error
            }

            guard let data = responseData,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NSError(domain: "GoogleCalendar", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse events"])
            }

            if let error = json["error"] {
                if let errorObj = error as? [String: Any], let msg = errorObj["message"] as? String {
                    throw NSError(domain: "GoogleCalendar", code: httpStatus, userInfo: [NSLocalizedDescriptionKey: msg])
                }
                throw NSError(domain: "GoogleCalendar", code: httpStatus, userInfo: [NSLocalizedDescriptionKey: "Google API error"])
            }

            return json
        }

        func findGoogleEventWithMarker(events: [[String: Any]], marker: String) -> [String: Any]? {
            for event in events {
                if let description = event["description"] as? String, description.contains(marker) {
                    return event
                }
            }
            return nil
        }

        func updateGoogleCalendarEvent(eventID: String, event: EKEvent, accessToken: String, calendarID: String, marker: String) throws {
            let rfc3339DateFormatter = ISO8601DateFormatter()

            var description = ""
            if let notes = event.notes, !notes.isEmpty {
                description = notes + "\n\n"
            }
            description += marker

            var eventBody: [String: Any] = [
                "summary": event.title ?? "No Title",
                "description": description
            ]

            if event.isAllDay {
                eventBody["start"] = ["date": String(rfc3339DateFormatter.string(from: event.startDate).prefix(10))]
                eventBody["end"] = ["date": String(rfc3339DateFormatter.string(from: event.endDate).prefix(10))]
            } else {
                eventBody["start"] = ["dateTime": rfc3339DateFormatter.string(from: event.startDate)]
                eventBody["end"] = ["dateTime": rfc3339DateFormatter.string(from: event.endDate)]
            }

            eventBody["reminders"] = ["useDefault": true]

            var request = URLRequest(
                url: URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(calendarID)/events/\(eventID)")!
            )

            request.httpMethod = "PATCH"
            request.setValue(
                "Bearer \(accessToken)",
                forHTTPHeaderField: "Authorization"
            )
            request.setValue(
                "application/json",
                forHTTPHeaderField: "Content-Type"
            )

            request.httpBody = try JSONSerialization.data(withJSONObject: eventBody)

            let semaphore = DispatchSemaphore(value: 0)
            var httpStatus: Int = 0
            var resultError: Error?

            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    resultError = error
                }
                if let httpResponse = response as? HTTPURLResponse {
                    httpStatus = httpResponse.statusCode
                }
                semaphore.signal()
            }.resume()

            semaphore.wait()

            if let error = resultError {
                throw error
            }

            if httpStatus != 200 {
                throw NSError(domain: "GoogleCalendar", code: httpStatus, userInfo: [NSLocalizedDescriptionKey: "Failed to update event"])
            }
        }

        func deleteGoogleCalendarEvent(eventID: String, accessToken: String, calendarID: String) throws {
            var request = URLRequest(
                url: URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(calendarID)/events/\(eventID)")!
            )

            request.httpMethod = "DELETE"
            request.setValue(
                "Bearer \(accessToken)",
                forHTTPHeaderField: "Authorization"
            )

            let semaphore = DispatchSemaphore(value: 0)
            var resultError: Error?

            URLSession.shared.dataTask(with: request) { _, _, error in
                resultError = error
                semaphore.signal()
            }.resume()

            semaphore.wait()

            if let error = resultError {
                throw error
            }
        }

        func createGoogleCalendarEvent(event: EKEvent, accessToken: String, calendarID: String) throws {
            let rfc3339DateFormatter = ISO8601DateFormatter()
            let marker = getSyncMarker(event: event)

            var description = ""
            if let notes = event.notes, !notes.isEmpty {
                description = notes + "\n\n"
            }
            description += marker

            var eventBody: [String: Any] = [
                "summary": event.title ?? "No Title",
                "description": description
            ]

            if event.isAllDay {
                eventBody["start"] = ["date": String(rfc3339DateFormatter.string(from: event.startDate).prefix(10))]
                eventBody["end"] = ["date": String(rfc3339DateFormatter.string(from: event.endDate).prefix(10))]
            } else {
                eventBody["start"] = ["dateTime": rfc3339DateFormatter.string(from: event.startDate)]
                eventBody["end"] = ["dateTime": rfc3339DateFormatter.string(from: event.endDate)]
            }

            eventBody["reminders"] = ["useDefault": true]

            var request = URLRequest(
                url: URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(calendarID)/events")!
            )

            request.httpMethod = "POST"
            request.setValue(
                "Bearer \(accessToken)",
                forHTTPHeaderField: "Authorization"
            )
            request.setValue(
                "application/json",
                forHTTPHeaderField: "Content-Type"
            )

            request.httpBody = try JSONSerialization.data(withJSONObject: eventBody)

            let semaphore = DispatchSemaphore(value: 0)
            var resultError: Error?
            var responseData: Data?
            var httpStatus: Int = 0

            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    resultError = error
                }
                responseData = data
                if let httpResponse = response as? HTTPURLResponse {
                    httpStatus = httpResponse.statusCode
                }
                semaphore.signal()
            }.resume()

            semaphore.wait()

            if let error = resultError {
                throw error
            }

            if httpStatus != 200 && httpStatus != 201 {
                var errorMessage = "HTTP \(httpStatus)"
                if let data = responseData,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? [String: Any] {
                    if let message = error["message"] as? String {
                        errorMessage = message
                    }
                }
                throw NSError(domain: "GoogleCalendar", code: httpStatus, userInfo: [NSLocalizedDescriptionKey: errorMessage])
            }
        }

        // MARK: - First Run Setup

        let settings = loadSettings()
        var sourceCalendarID: String
        var destCalendarID: String?

        if settings == nil {
            print("=== Calendar Sync - First Run Setup ===")
            print("")

            let localCalendars = listLocalCalendars()
            if localCalendars.isEmpty {
                print("No local calendars found.")
                exit(1)
            }

            guard let selectedID = getUserCalendarSelection(localCalendars) else {
                exit(1)
            }

            sourceCalendarID = selectedID

            if let selectedCalendar = localCalendars.first(where: { $0.id == selectedID }) {
                print("Selected: \(selectedCalendar.name)")
            }
        } else {
            guard let id = settings?[sourceCalendarIDKey],
                  let destID = settings?[destCalendarIDKey] else {
                print("ERROR: Settings corrupted. Please delete saved settings to reset.")
                exit(1)
            }
            sourceCalendarID = id
            destCalendarID = destID
        }

        // MARK: - Clear All Mode

        if clearAll {
            guard let destID = destCalendarID else {
                print("ERROR: Calendar not configured. Run without --clear-all first.")
                exit(1)
            }

            print("Clearing all synced events from Google Calendar...")
            print("(Events with sync markers only - personal events are safe)")
            print("")

            do {
                let refreshToken = try Keychain.load()
                let accessToken = try getAccessToken(clientID: clientID, clientSecret: clientSecret, refreshToken: refreshToken)
                let googleCalendarJSON = try listGoogleCalendarEvents(accessToken: accessToken, calendarID: destID)
                let googleEvents = (googleCalendarJSON["items"] as? [[String: Any]]) ?? []

                var deletedCount = 0

                for googleEvent in googleEvents {
                    // Only delete events with our sync marker
                    if let description = googleEvent["description"] as? String, description.contains("sync:") {
                        if let eventID = googleEvent["id"] as? String {
                            try deleteGoogleCalendarEvent(eventID: eventID, accessToken: accessToken, calendarID: destID)
                            print("  Deleted: \(formatGoogleEventDisplay(event: googleEvent))")
                            deletedCount += 1
                        }
                    }
                }

                print("")
                print("Cleared \(deletedCount) synced events.")
                let personalCount = googleEvents.count - deletedCount
                if personalCount > 0 {
                    print("\(personalCount) personal events were left untouched.")
                }
                return
            } catch {
                print("Error clearing events: \(error)")
                exit(1)
            }
        }

        guard settings == nil else {
            print("Calendar sync already configured. Starting sync loop...")
            print("Source calendar: \(sourceCalendarID)")
            print("Destination calendar: \(destCalendarID ?? "unknown")")
            print("")

            // Load the refresh token once (the only Touch ID prompt for this process's lifetime)
            // and hold it in memory rather than re-reading Keychain on every access-token renewal.
            let refreshToken: String
            do {
                refreshToken = try Keychain.load()
            } catch {
                print("ERROR: Refresh token not found in keychain.")
                print("")
                print("To fix this, reset and re-run setup:")
                print("  defaults delete \(settingsDomain)")
                print("  security delete-generic-password -s com.jondaley.calendar-sync -a google-refresh-token")
                print("")
                print("Then run the app again to re-authenticate with Google.")
                exit(1)
            }

            let eventStore = EKEventStore()

            if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
                eventStore.requestFullAccessToEvents { granted, error in
                    if !granted {
                        print("EventKit access denied")
                        exit(1)
                    }
                }
            }

            let syncInterval: TimeInterval = 5 * 60
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .short
            dateFormatter.timeStyle = .short

            var cachedAccessToken: String?
            var tokenExpiryTime: Date?

            while true {
                do {
                    print("")
                    print("Syncing events...")

                    var accessToken: String

                    // Use cached token if still valid (cache for 55 minutes, refresh token expires in 60)
                    if let cached = cachedAccessToken, let expiry = tokenExpiryTime, Date() < expiry {
                        accessToken = cached
                    } else {
                        accessToken = try getAccessToken(clientID: clientID, clientSecret: clientSecret, refreshToken: refreshToken)
                        cachedAccessToken = accessToken
                        tokenExpiryTime = Date(timeIntervalSinceNow: 55 * 60)
                    }
                    switch checkGoogleCalendarExists(accessToken: accessToken, calendarID: destCalendarID!) {
                    case .exists:
                        break
                    case .notFound:
                        print("Destination calendar '\(destCalendarID!)' no longer exists on Google (it may have been deleted).")
                        print("Let's pick or create a new destination calendar.")
                        let newDestID = try chooseOrCreateDestinationCalendar(accessToken: accessToken, calendarID: sourceCalendarID)
                        destCalendarID = newDestID
                        try saveSettings([sourceCalendarIDKey: sourceCalendarID, destCalendarIDKey: newDestID])
                        print("Updated settings saved. Destination calendar: \(newDestID)")
                    case .error(let message):
                        print("Warning: could not verify destination calendar (\(message)). Will attempt sync anyway.")
                    }

                    // Use a fresh EKEventStore each cycle: this process has no run loop pumping
                    // EKEventStoreChanged notifications, so a long-lived store's internal cache
                    // never invalidates and keeps reporting events the source calendar deleted.
                    let eventStore = EKEventStore()
                    let localEvents = getEventsFromCalendar(calendarID: sourceCalendarID, eventStore: eventStore)

                    print("Found \(localEvents.count) local events")

                    // Get all Google Calendar events
                    let googleCalendarJSON = try listGoogleCalendarEvents(accessToken: accessToken, calendarID: destCalendarID!)
                    let googleEvents = (googleCalendarJSON["items"] as? [[String: Any]]) ?? []

                    print("Found \(googleEvents.count) Google Calendar events")

                    var createdCount = 0
                    var updatedCount = 0
                    var skippedCount = 0

                    // Process local events
                    for localEvent in localEvents {
                        let marker = getSyncMarker(event: localEvent)

                        if let googleEvent = findGoogleEventWithMarker(events: googleEvents, marker: marker) {
                            // Event already synced, check if modified
                            let googleTitle = googleEvent["summary"] as? String ?? ""
                            if googleTitle != (localEvent.title ?? "No Title") {
                                // Title changed, update it
                                if let eventID = googleEvent["id"] as? String {
                                    try updateGoogleCalendarEvent(eventID: eventID, event: localEvent, accessToken: accessToken, calendarID: destCalendarID!, marker: marker)
                                    print("  Updated: \(formatEventDisplay(title: localEvent.title ?? "Untitled", startDate: localEvent.startDate))")
                                    updatedCount += 1
                                }
                            } else {
                                skippedCount += 1
                            }
                        } else {
                            // New event, create it
                            do {
                                try createGoogleCalendarEvent(event: localEvent, accessToken: accessToken, calendarID: destCalendarID!)
                                print("  Created: \(formatEventDisplay(title: localEvent.title ?? "Untitled", startDate: localEvent.startDate))")
                                createdCount += 1
                            } catch {
                                print("  Error creating '\(formatEventDisplay(title: localEvent.title ?? "Untitled", startDate: localEvent.startDate))': \(error)")
                            }
                        }
                    }

                    // Check for deleted events
                    let localEventMarkers = Set(localEvents.map { getSyncMarker(event: $0) })
                    var deletedCount = 0

                    let now = Date()
                    for googleEvent in googleEvents {
                        // Local events are only fetched from "now" forward (see getEventsFromCalendar),
                        // so a synced event whose start has already passed will never appear in
                        // localEventMarkers even though it's still on the source calendar. Only treat
                        // events still in the sync window as deletion candidates; leave past events alone.
                        if let startDate = googleEventStartDate(googleEvent), startDate < now {
                            continue
                        }

                        if let description = googleEvent["description"] as? String, description.contains("sync:") {
                            // This is an event we synced
                            var found = false
                            for marker in localEventMarkers {
                                if description.contains(marker) {
                                    found = true
                                    break
                                }
                            }

                            if !found {
                                // Event was deleted locally, remove from Google
                                if let eventID = googleEvent["id"] as? String {
                                    try deleteGoogleCalendarEvent(eventID: eventID, accessToken: accessToken, calendarID: destCalendarID!)
                                    print("  Deleted: \(formatGoogleEventDisplay(event: googleEvent))")
                                    deletedCount += 1
                                }
                            }
                        }
                    }

                    print("Sync summary: \(createdCount) created, \(updatedCount) updated, \(skippedCount) skipped, \(deletedCount) deleted")
                    print("Next sync in \(Int(syncInterval / 60)) minutes.")
                } catch {
                    print("Sync error: \(error)")
                }

                Thread.sleep(forTimeInterval: syncInterval)
            }
        }

        print("")
        print("Running first-time OAuth setup...")

        // MARK: - PKCE

        let codeVerifier = randomString(64)

        let hash = SHA256.hash(data: Data(codeVerifier.utf8))
        let codeChallenge = base64URL(Data(hash))

        // MARK: - Callback state

        let callbackSemaphore = DispatchSemaphore(value: 0)

        var authorizationCode: String?
        var authorizationError: String?

        // MARK: - Local HTTP server

        let listener = try NWListener(using: .tcp, on: .any)

        listener.stateUpdateHandler = { state in
            switch state {

            case .ready:
                guard let port = listener.port else {
                    print("ERROR: listener has no port")
                    exit(1)
                }

                let portNumber = port.rawValue

                let redirectURI =
                    "http://127.0.0.1:\(portNumber)/oauth2callback"

                print("")
                print("Local OAuth server listening on port \(portNumber)")
                print("Redirect URI: \(redirectURI)")
                print("")
                print("Opening Google authorization...")
                print("")
                print("Choose your PERSONAL Gmail account.")
                print("")

                var components = URLComponents(
                    string: "https://accounts.google.com/o/oauth2/v2/auth"
                )!

                components.queryItems = [
                    URLQueryItem(name: "client_id", value: clientID),
                    URLQueryItem(name: "redirect_uri", value: redirectURI),
                    URLQueryItem(name: "response_type", value: "code"),
                    URLQueryItem(name: "scope", value: scope),
                    URLQueryItem(name: "access_type", value: "offline"),
                    URLQueryItem(name: "prompt", value: "consent"),
                    URLQueryItem(name: "code_challenge", value: codeChallenge),
                    URLQueryItem(name: "code_challenge_method", value: "S256")
                ]

                guard let url = components.url else {
                    print("ERROR: Could not construct Google URL")
                    exit(1)
                }

                NSWorkspace.shared.open(url)

            case .failed(let error):
                print("Listener failed: \(error)")
                exit(1)

            default:
                break
            }
        }

        listener.newConnectionHandler = { connection in

            print("Incoming browser connection...")

            connection.stateUpdateHandler = { state in

                switch state {

                case .ready:

                    print("Browser connection ready; waiting for HTTP request...")

                    connection.receive(
                        minimumIncompleteLength: 1,
                        maximumLength: 65536
                    ) { data, _, _, error in

                        if let error {
                            print("Receive error: \(error)")
                            callbackSemaphore.signal()
                            return
                        }

                        guard let data,
                              let request = String(
                                data: data,
                                encoding: .utf8
                              )
                        else {
                            print("Could not decode browser request")
                            callbackSemaphore.signal()
                            return
                        }

                        print("Received browser callback.")

                        guard let firstLine =
                            request.components(separatedBy: "\r\n").first
                        else {
                            print("Could not parse HTTP request")
                            callbackSemaphore.signal()
                            return
                        }

                        print("HTTP: \(firstLine)")

                        let pieces = firstLine.components(separatedBy: " ")

                        if pieces.count >= 2 {

                            let path = pieces[1]

                            if let callbackURL = URLComponents(
                                string: "http://127.0.0.1" + path
                            ) {

                                for item in callbackURL.queryItems ?? [] {

                                    if item.name == "code" {
                                        authorizationCode = item.value
                                    }

                                    if item.name == "error" {
                                        authorizationError = item.value
                                    }
                                }
                            }
                        }

                        let body = """
                        <html>
                        <body>
                        <h2>Authorization received.</h2>
                        <p>You can close this browser window and return to the terminal.</p>
                        </body>
                        </html>
                        """

                        let response =
                            "HTTP/1.1 200 OK\r\n" +
                            "Content-Type: text/html; charset=utf-8\r\n" +
                            "Content-Length: \(body.utf8.count)\r\n" +
                            "Connection: close\r\n" +
                            "\r\n" +
                            body

                        connection.send(
                            content: Data(response.utf8),
                            completion: .contentProcessed { error in

                                if let error {
                                    print("HTTP response error: \(error)")
                                }

                                connection.cancel()
                                callbackSemaphore.signal()
                            }
                        )
                    }

                case .failed(let error):
                    print("Connection failed: \(error)")
                    callbackSemaphore.signal()

                default:
                    break
                }
            }

            connection.start(queue: DispatchQueue.global())
        }

        listener.start(queue: DispatchQueue.global())

        // Wait for Google to redirect the browser back to us.

        print("Waiting for Google callback...")

        callbackSemaphore.wait()

        print("Google callback received.")

        if let error = authorizationError {
            print("Google OAuth error: \(error)")
            listener.cancel()
            exit(1)
        }

        guard let code = authorizationCode else {
            print("ERROR: Google callback contained no authorization code.")
            listener.cancel()
            exit(1)
        }

        // Save the port BEFORE shutting down the listener.

        guard let port = listener.port else {
            print("ERROR: Could not determine callback port.")
            listener.cancel()
            exit(1)
        }

        let redirectURI =
            "http://127.0.0.1:\(port.rawValue)/oauth2callback"

        listener.cancel()

        print("Authorization code received.")
        print("Exchanging code for tokens...")

        // MARK: - Token exchange

        var request = URLRequest(
            url: URL(string: "https://oauth2.googleapis.com/token")!
        )

        request.httpMethod = "POST"

        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )

        let parameters: [String: String] = [
            "client_id": clientID,
            "client_secret": clientSecret,
            "code": code,
            "code_verifier": codeVerifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ]

        request.httpBody = parameters
            .map {
                "\(urlEncode($0.key))=\(urlEncode($0.value))"
            }
            .joined(separator: "&")
            .data(using: .utf8)

        let tokenSemaphore = DispatchSemaphore(value: 0)

        var tokenData: Data?
        var tokenError: Error?

        URLSession.shared.dataTask(with: request) {
            data, _, error in

            tokenData = data
            tokenError = error

            tokenSemaphore.signal()

        }.resume()

        tokenSemaphore.wait()

        if let error = tokenError {
            print("Token request failed: \(error)")
            exit(1)
        }

        guard let tokenData else {
            print("No token response.")
            exit(1)
        }

        guard let json =
            try? JSONSerialization.jsonObject(with: tokenData)
            as? [String: Any]
        else {
            print("Unexpected Google response:")
            print(String(data: tokenData, encoding: .utf8) ?? "<not text>")
            exit(1)
        }

        if let error = json["error"] {
            print("")
            print("Google returned an OAuth error:")
            print(error)

            if let description = json["error_description"] {
                print(description)
            }

            exit(1)
        }

        print("")
        print("========================================")
        print("OAuth SUCCESS")
        print("========================================")

        if let token = json["access_token"] as? String {
            print("Access token received: \(token.count) characters")
        }

        if let token = json["refresh_token"] as? String {
            print("Refresh token received: \(token.count) characters")
            try Keychain.save(token)
            print("Refresh token saved securely in macOS Keychain.")
        } else {
            print("DEBUG: No refresh_token in OAuth response. Response keys: \(json.keys.sorted())")
        }

        if let expiresIn = json["expires_in"] {
            print("Expires in: \(expiresIn) seconds")
        }

        if let grantedScope = json["scope"] {
            print("Granted scope: \(grantedScope)")
        }

        print("")
        print("The Google OAuth portion is working.")

        // MARK: - Google Calendar API test

        guard let accessToken = json["access_token"] as? String else {
            print("No access token available.")
            exit(1)
        }

        print("")
        let createdCalendarID = try chooseOrCreateDestinationCalendar(accessToken: accessToken, calendarID: destCalendarID ?? "")
        print("")

        // MARK: - Save Settings

        destCalendarID = createdCalendarID
        let newSettings: [String: String] = [
            sourceCalendarIDKey: sourceCalendarID,
            destCalendarIDKey: createdCalendarID
        ]
        try saveSettings(newSettings)
        print("")
        print("Settings saved. Calendar sync is ready.")
        print("Source calendar: \(sourceCalendarID)")
        print("Destination calendar: \(createdCalendarID)")
    }
}
