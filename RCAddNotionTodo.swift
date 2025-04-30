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

let argumentsCount = 1

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
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    enum DateError: Error {
        case invalidFormat
    }
    
    static func validateDate(_ dateString: String?) -> Result<String, DateError> {
        // nilまたは空文字列の場合は今日の日付を返す
        guard let dateString = dateString, !dateString.isEmpty else {
            return .success(dateFormatter.string(from: Date()))
        }
        
        // N日後の処理
        if dateString.hasPrefix("+") {
            if let daysToAdd = Int(dateString.dropFirst()),
               let futureDate = Calendar.current.date(byAdding: .day, value: daysToAdd, to: Date()) {
                return .success(dateFormatter.string(from: futureDate))
            }
        }
        
        // YYYY-MM-DD 形式
        if dateString.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
            if let date = dateFormatter.date(from: dateString) {
                return .success(dateFormatter.string(from: date))
            }
        }
        
        return .failure(.invalidFormat)
    }
}

func main() {
    // 環境変数を読み込む
    let env = EnvReader.getEnvDict()
    guard let notionToken = env["NOTION_TOKEN"], !notionToken.isEmpty else {
        print("ERROR: NOTION_TOKEN is not set")
        exit(1)
    }
    guard let databaseId = env["NOTION_TASK_DATABASE_ID"], !databaseId.isEmpty else {
        print("ERROR: NOTION_TASK_DATABASE_ID is not set")
        exit(1)
    }

    // Raycast 引数を読み込む
    let arguments = CommandLine.arguments
    guard arguments.count > argumentsCount else {
        print("ERROR: Please specify a title")
        exit(1)
    }
    let title = arguments[1]
    let customDate = arguments.count > 2 ? arguments[2] : nil

    let dateResult = DateUtils.validateDate(customDate)
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
