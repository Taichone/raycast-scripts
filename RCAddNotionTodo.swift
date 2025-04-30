#!/usr/bin/swift

// Required parameters:
// @raycast.schemaVersion 1
// @raycast.title Add Notion Todo
// @raycast.mode compact

// Optional parameters:
// @raycast.icon ✅
// @raycast.argument1 { "type": "text", "placeholder": "Title" }
// @raycast.argument2 { "type": "text", "placeholder": "Date (YYYY-MM-DD)", "optional": true }
// @raycast.packageName Notion

import Foundation

struct EnvReader {
    static func getEnvDict() -> [String: String] {
        var env = [String: String]()
        let fileManager = FileManager.default
        let currentPath = fileManager.currentDirectoryPath
        let envPath = currentPath + "/.env"
        
        guard fileManager.fileExists(atPath: envPath) else {
            print("Warning: .env file not found: \(envPath)")
            return env
        }

        do {
            let contents = try String(contentsOfFile: envPath, encoding: .utf8)
            contents.components(separatedBy: .newlines).forEach { line in
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedLine.isEmpty && !trimmedLine.hasPrefix("#") {
                    let parts = trimmedLine.split(separator: "=", maxSplits: 1)
                    if parts.count == 2 {
                        let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                        var value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        if (value.hasPrefix("\"") && value.hasSuffix("\"")) || 
                        (value.hasPrefix("'") && value.hasSuffix("'")) {
                            value = String(value.dropFirst().dropLast())
                        }
                        
                        env[key] = value
                    }
                }
            }
        } catch {
            print("ERROR: Failed to read .env file: \(error.localizedDescription)")
        }

        return env
    }
}

struct DateUtils {
    enum DateError: Error, CustomStringConvertible {
        case invalidFormat(String)
        case emptyDate
        
        var description: String {
            switch self {
            case .invalidFormat(let message):
                return message
            case .emptyDate:
                return "Error: No date specified"
            }
        }
    }
    
    static func today() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.string(from: Date())
    }
    
    static func normalizeDate(_ dateString: String?) -> String? {
        guard let dateString = dateString, !dateString.isEmpty else {
            return nil
        }

        if dateString.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
            return dateString
        }
        
        let normalizedDate = dateString.replacingOccurrences(of: "/", with: "-")
        if normalizedDate.range(of: #"^\d{4}-\d{1,2}-\d{1,2}$"#, options: .regularExpression) != nil {
            let components = normalizedDate.split(separator: "-")
            if components.count == 3 {
                let year = components[0]
                let month = components[1].count == 1 ? "0\(components[1])" : components[1]
                let day = components[2].count == 1 ? "0\(components[2])" : components[2]
                return "\(year)-\(month)-\(day)"
            }
        }
        
        if normalizedDate.range(of: #"^\d{1,2}-\d{1,2}$"#, options: .regularExpression) != nil {
            let components = normalizedDate.split(separator: "-")
            if components.count == 2 {
                let currentYear = Calendar.current.component(.year, from: Date())
                let month = components[0].count == 1 ? "0\(components[0])" : components[0]
                let day = components[1].count == 1 ? "0\(components[1])" : components[1]
                return "\(currentYear)-\(month)-\(day)"
            }
        }

        let today = Date()
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        switch dateString {
        case "today", "今日", "今", "":
            return dateFormatter.string(from: today)
        case "tomorrow", "明日", "あした", "あす":
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) {
                return dateFormatter.string(from: tomorrow)
            }
        case "day after tomorrow", "明後日", "あさって":
            if let dayAfterTomorrow = calendar.date(byAdding: .day, value: 2, to: today) {
                return dateFormatter.string(from: dayAfterTomorrow)
            }
        default:
            break
        }
        
        return nil
    }
    
    /// Convert empty date string to nil
    static func emptyToNil(_ dateString: String?) -> String? {
        guard let dateString = dateString else {
            return nil
        }
        
        if dateString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }
        
        return dateString
    }
    
    /// Process date string and return valid date in YYYY-MM-DD format
    /// - Parameters:
    ///   - dateString: Date string to process
    ///   - defaultToToday: Use today's date if date is invalid or not specified
    /// - Returns: Processing result (date string if successful, error message if failed)
    static func processDate(_ dateString: String?, defaultToToday: Bool = true) -> Result<String, DateError> {
        let cleanDateString = emptyToNil(dateString)
        
        // Try to convert if date is specified
        if let dateStr = cleanDateString {
            if let normalizedDate = normalizeDate(dateStr) {
                return .success(normalizedDate)
            } else {
                let errorMessage = "Error: Enter date in YYYY-MM-DD or YYYY/MM/DD format\nExample: 2023-12-31, 2023/12/31, 12-31, 12/31, today, tomorrow, etc."
                return .failure(.invalidFormat(errorMessage))
            }
        } else if defaultToToday {
            let todayStr = today()
            return .success(todayStr)
        } else {
            return .failure(.emptyDate)
        }
    }
}

func main() {
    // Read environment variables
    let env = EnvReader.getEnvDict()
    guard let notionToken = env["NOTION_TOKEN"], !notionToken.isEmpty else {
        print("ERROR: NOTION_TOKEN is not set")
        exit(1)
    }

    guard let databaseId = env["NOTION_TASK_DATABASE_ID"], !databaseId.isEmpty else {
        print("ERROR: NOTION_TASK_DATABASE_ID is not set")
        exit(1)
    }

    let arguments = CommandLine.arguments
    guard arguments.count > 1 else {
        print("ERROR: Please specify a title")
        exit(1)
    }

    // Set Notion Database properties
    let title = arguments[1]
    let customDate = arguments.count > 2 ? arguments[2] : nil

    let dateResult = DateUtils.processDate(customDate)
    let startDate: String
    switch dateResult {
    case .success(let date):
        startDate = date
    case .failure(let error):
        print(error)
        exit(1)
    }

    print("Sending request...")

    // 対象の Notion Database 形式に合わせる
    let jsonData: [String: Any] = [
        "parent": ["database_id": databaseId],
        "properties": [
            "Title": [
                "title": [
                    [
                        "text": [
                            "content": title
                        ]
                    ]
                ]
            ],
            "Date": [
                "date": [
                    "start": startDate
                ]
            ]
        ]
    ]

    let url = URL(string: "https://api.notion.com/v1/pages")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(notionToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")

    do {
        request.httpBody = try JSONSerialization.data(withJSONObject: jsonData)
    } catch {
        print("Error: Failed to create JSON data")
        exit(1)
    }

    let semaphore = DispatchSemaphore(value: 0)
    var responseData: Data?
    var responseError: Error?

    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        responseData = data
        responseError = error
        semaphore.signal()
    }

    task.resume()
    semaphore.wait()

    if let error = responseError {
        print("An error occurred:")
        print(error.localizedDescription)
        exit(1)
    }

    guard let data = responseData,
        let responseString = String(data: data, encoding: .utf8) else {
        print("Error: Failed to parse response")
        exit(1)
    }

    if responseString.contains("error") {
        print("An error occurred:")
        print(responseString)
        exit(1)
    } else {
        print("Created Todo: \(title)")
    } 
}

main()
