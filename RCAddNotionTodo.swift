#!/usr/bin/swift

// Required parameters:
// @raycast.schemaVersion 1
// @raycast.title Add Notion Todo
// @raycast.mode compact

// Optional parameters:
// @raycast.icon ./Assets/notion.png
// @raycast.argument1 { "type": "text", "placeholder": "Title" }
// @raycast.argument2 { "type": "text", "placeholder": "Date (yyyy-mm-dd, +n)", "optional": true }
// @raycast.packageName Notion

import Foundation

let argumentsCount = 2

struct EnvReader {
    static func getEnvDict() throws -> [String: String] {
        var env = [String: String]()
        let fileManager = FileManager.default
        let currentPath = fileManager.currentDirectoryPath
        let envPath = currentPath + "/.env"
        
        guard fileManager.fileExists(atPath: envPath) else {
            throw NSError(domain: "EnvReaderError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to read .env file"])
        }
        
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
        
        return env
    }
}

struct DateUtils {
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    static func validateDate(_ dateString: String?) throws -> String {
        // nilまたは空文字列の場合は今日の日付を返す
        guard let dateString = dateString, !dateString.isEmpty else {
            return dateFormatter.string(from: Date())
        }
        
        // N日後の処理
        if dateString.hasPrefix("+") {
            if let daysToAdd = Int(dateString.dropFirst()),
               let futureDate = Calendar.current.date(byAdding: .day, value: daysToAdd, to: Date()) {
                return dateFormatter.string(from: futureDate)
            }
        }
        
        // YYYY-MM-DD 形式
        if dateString.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
            if let date = dateFormatter.date(from: dateString) {
                return dateFormatter.string(from: date)
            }
        }
        
        throw NSError(domain: "DateUtilsError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid date format"])
    }
}

struct NotionClient {
    static func createTodo(notionToken: String, databaseID: String, title: String, startDate: String) async throws {
        let url = URL(string: "https://api.notion.com/v1/pages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(notionToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
        
        let requestJSONObject: [String: Any] = [
            "parent": ["database_id": databaseID],
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

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestJSONObject)
        } catch {
            throw NSError(domain: "NotionClientError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create JSON data"])
        }
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        guard let responseString = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "NotionClientError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse response"])
        }
        
        if responseString.contains("error") {
            throw NSError(domain: "NotionClientError", code: 1, userInfo: [NSLocalizedDescriptionKey: "An error occurred: \(responseString)"])
        }
    }
}

func main() {
    Task {
        do {
            // 環境変数を読み込む
            let env = try EnvReader.getEnvDict()
            guard let notionToken = env["NOTION_TOKEN"], !notionToken.isEmpty else {
                throw NSError(domain: "EnvReaderError", code: 1, userInfo: [NSLocalizedDescriptionKey: "NOTION_TOKEN is not set"])
            }
            guard let databaseID = env["NOTION_TASK_DATABASE_ID"], !databaseID.isEmpty else {
                throw NSError(domain: "EnvReaderError", code: 1, userInfo: [NSLocalizedDescriptionKey: "NOTION_TASK_DATABASE_ID is not set"])
            }
            
            // Raycast 引数を読み込む
            let arguments = CommandLine.arguments
            guard arguments.count > argumentsCount else {
                throw NSError(domain: "EnvReaderError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Please specify a title"])
            }
            let title = arguments[1]
            let customDate = arguments[2]
            let startDate = try DateUtils.validateDate(customDate)
            
            // Request
            try await NotionClient.createTodo(notionToken: notionToken, databaseID: databaseID, title: title, startDate: startDate)
        } catch {
            print("ERROR: \(error)")
            exit(1)
        }
        
        print("Successfully created Todo!")
        exit(0)
    }
    
    RunLoop.main.run()
}

main()
