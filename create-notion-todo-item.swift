#!/usr/bin/swift

// Required parameters:
// @raycast.schemaVersion 1
// @raycast.title タスク作成
// @raycast.mode compact

// Optional parameters:
// @raycast.icon ✅
// @raycast.argument1 { "type": "text", "placeholder": "Title" }
// @raycast.argument2 { "type": "text", "placeholder": "Date (YYYY-MM-DD)", "optional": true }
// @raycast.packageName Notion

// 環境変数の設定
// @raycast.refreshTime 1h
// @raycast.preferenceValues [{"name":"NOTION_TOKEN", "type":"password", "required":true, "title":"Notion APIトークン", "description":"NotionのAPIトークン"}, {"name":"NOTION_TASK_DATABASE_ID", "type":"textfield", "required":true, "title":"タスクデータベースID", "description":"タスクデータベースのID"}]

import Foundation

struct DateUtils {
    enum DateError: Error, CustomStringConvertible {
        case invalidFormat(String)
        case emptyDate
        
        var description: String {
            switch self {
            case .invalidFormat(let message):
                return message
            case .emptyDate:
                return "エラー: 日付が指定されていません"
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
        case "今日", "today", "今", "":
            return dateFormatter.string(from: today)
        case "明日", "tomorrow", "あした", "あす":
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) {
                return dateFormatter.string(from: tomorrow)
            }
        case "明後日", "あさって":
            if let dayAfterTomorrow = calendar.date(byAdding: .day, value: 2, to: today) {
                return dateFormatter.string(from: dayAfterTomorrow)
            }
        default:
            break
        }
        
        return nil
    }
    
    /// 空の日付文字列をチェックし、空ならnilに変換
    static func emptyToNil(_ dateString: String?) -> String? {
        guard let dateString = dateString else {
            return nil
        }
        
        if dateString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }
        
        return dateString
    }
    
    /// 日付文字列を処理し、有効な日付をYYYY-MM-DD形式で返す
    /// - Parameters:
    ///   - dateString: 処理する日付文字列
    ///   - defaultToToday: 日付が無効または未指定の場合に今日の日付を使用する場合はtrue
    /// - Returns: 処理結果（成功した場合は日付文字列、失敗した場合はエラーメッセージ）
    static func processDate(_ dateString: String?, defaultToToday: Bool = true) -> Result<String, DateError> {
        let cleanDateString = emptyToNil(dateString)
        
        // 日付が指定されている場合は変換を試みる
        if let dateStr = cleanDateString {
            if let normalizedDate = normalizeDate(dateStr) {
                return .success(normalizedDate)
            } else {
                let errorMessage = "エラー: 日付は YYYY-MM-DD または YYYY/MM/DD 形式で入力してください\n例: 2023-12-31, 2023/12/31, 12-31, 12/31, 今日, 明日, 一週間後 など"
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

func loadEnvFile() -> [String: String] {
    var env = [String: String]()
    let fileManager = FileManager.default
    let currentPath = fileManager.currentDirectoryPath
    let envPath = currentPath + "/.env"
    
    guard fileManager.fileExists(atPath: envPath) else {
        print("警告: .envファイルが見つかりません: \(envPath)")
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
        print("ERROR: .envファイルの読み込みに失敗しました: \(error.localizedDescription)")
    }
    
    return env
}

// MARK: - Entry Point
let envVars = loadEnvFile()
let notionToken = ProcessInfo.processInfo.environment["NOTION_TOKEN"] ?? envVars["NOTION_TOKEN"] ?? ""
let databaseId = ProcessInfo.processInfo.environment["NOTION_TASK_DATABASE_ID"] ?? envVars["NOTION_TASK_DATABASE_ID"] ?? ""
if notionToken.isEmpty {
    print("ERROR: NOTION_TOKENが設定されていません")
    exit(1)
}

if databaseId.isEmpty {
    print("ERROR: NOTION_TASK_DATABASE_IDが設定されていません")
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    print("ERROR: タイトルを指定してください")
    exit(1)
}

let title = arguments[1]
let customDate = arguments.count > 2 ? arguments[2] : nil
let dateResult = DateUtils.processDate(customDate)
let today: String

switch dateResult {
case .success(let date):
    today = date
case .failure(let error):
    print(error)
    exit(1)
}

print("リクエスト送信中...")

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
                "start": today
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
    print("エラー: JSONデータの作成に失敗しました")
    exit(1)
}

// リクエストの送信
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
    print("エラーが発生しました:")
    print(error.localizedDescription)
    exit(1)
}

guard let data = responseData,
      let responseString = String(data: data, encoding: .utf8) else {
    print("エラー: レスポンスの解析に失敗しました")
    exit(1)
}

if responseString.contains("error") {
    print("エラーが発生しました:")
    print(responseString)
    exit(1)
} else {
    print("Todo を作成しました: \(title)")
    print("日付: \(today)")
} 