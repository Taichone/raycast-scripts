#!/usr/bin/swift

// Required parameters:
// @raycast.schemaVersion 1
// @raycast.title Create PR Review
// @raycast.mode compact

// Optional parameters:
// @raycast.icon ./icons/dify.png
// @raycast.argument1 { "type": "dropdown", "placeholder": "Language", "optional": false, "data": [{"title": "English", "value": "english"}, {"title": "Japanese", "value": "japanese"}] }
// @raycast.argument2 { "type": "text", "placeholder": "Diff (optional)", "optional": true }
// @raycast.packageName Dify

// 環境変数の設定
// @raycast.refreshTime 1h
// @raycast.preferenceValues [{"name":"DIFY_BASE_URL", "type":"textfield", "required":true, "title":"Dify API URL", "description":"Dify APIのベースURL", "default":"https://dify.arklet.jp/v1"}, {"name":"DIFY_PR_TOKEN", "type":"password", "required":true, "title":"Dify PR API Token", "description":"PR生成AIのAPIトークン"}]

import Foundation

// 設定とユーティリティ関数
let defaultDifyBaseURL = "https://dify.arklet.jp/v1"

// 環境変数を取得する関数
func getEnvironmentVariable(_ name: String) -> String? {
    return ProcessInfo.processInfo.environment[name]
}

// .envファイルから環境変数を読み込む関数
func loadEnvFile() {
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: ".env") {
        do {
            let envContent = try String(contentsOfFile: ".env", encoding: .utf8)
            let lines = envContent.split(separator: "\n")
            
            for line in lines {
                if line.hasPrefix("#") { continue }
                let parts = line.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                    setenv(key, value, 1)
                }
            }
        } catch {
            print("Error loading .env file: \(error)")
        }
    }
}

// エラーを標準出力して終了する関数
func exitWithError(_ message: String) -> Never {
    print("Error: \(message)")
    exit(1)
}

// クリップボードから内容を取得する関数
func getClipboardContent() -> String? {
    let task = Process()
    task.launchPath = "/usr/bin/pbpaste"
    
    let pipe = Pipe()
    task.standardOutput = pipe
    
    do {
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    } catch {
        print("Error getting clipboard content: \(error)")
        return nil
    }
}

// クリップボードに内容をコピーする関数
func copyToClipboard(_ text: String) {
    let task = Process()
    task.launchPath = "/usr/bin/pbcopy"
    
    let pipe = Pipe()
    task.standardInput = pipe
    
    do {
        try task.run()
        if let data = text.data(using: .utf8) {
            pipe.fileHandleForWriting.write(data)
            pipe.fileHandleForWriting.closeFile()
        }
        task.waitUntilExit()
    } catch {
        print("Error copying to clipboard: \(error)")
    }
}

// JSON文字列をエスケープする関数
func escapeJSONString(_ string: String) -> String {
    let data = string.data(using: .utf8)!
    if let escapedString = String(data: data, encoding: .utf8) {
        return escapedString
    }
    return string
}

// メイン処理
func main() {
    // .envファイルがあれば読み込む
    loadEnvFile()
    
    // 環境変数の取得
    let difyBaseURL = getEnvironmentVariable("DIFY_BASE_URL") ?? defaultDifyBaseURL
    guard let difyApiToken = getEnvironmentVariable("DIFY_PR_TOKEN") else {
        exitWithError("DIFY_PR_TOKEN is not set")
    }
    
    // コマンドライン引数の取得
    let arguments = CommandLine.arguments
    
    // 環境（必須引数）
    guard arguments.count >= 2 else {
        exitWithError("Environment argument is required")
    }
    let environment = arguments[1]
    print("Selected environment: \(environment)")
    
    // Diff（オプション引数）
    var gitDiff = ""
    if arguments.count >= 3 && !arguments[2].isEmpty {
        gitDiff = arguments[2]
    } else {
        print("No diff provided as argument. Getting diff from clipboard...")
        if let clipboardContent = getClipboardContent(), !clipboardContent.isEmpty {
            gitDiff = clipboardContent
        } else {
            exitWithError("No diff found in clipboard. Please provide a diff as an argument or copy it to clipboard.")
        }
    }
    
    print("Generating PR review for \(environment) environment...")
    
    // JSON データの準備
    // gitDiffをJSONエスケープする必要がある
    let jsonData = """
    {
      "inputs": {
        "environment": "\(environment)",
        "git_diff": \(gitDiff.data(using: .utf8)!.base64EncodedString().debugDescription)
      },
      "response_mode": "blocking",
      "user": "raycast-user"
    }
    """
    
    // URLリクエストの準備
    guard let url = URL(string: "\(difyBaseURL)/completion-messages") else {
        exitWithError("Invalid URL")
    }
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.addValue("Bearer \(difyApiToken)", forHTTPHeaderField: "Authorization")
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = jsonData.data(using: .utf8)
    
    // セマフォを使用して同期的にリクエストを処理
    let semaphore = DispatchSemaphore(value: 0)
    var responseData: Data?
    var responseError: Error?
    
    // APIリクエスト送信
    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        responseData = data
        responseError = error
        semaphore.signal()
    }
    task.resume()
    
    // レスポンスを待つ
    semaphore.wait()
    
    // エラー処理
    if let error = responseError {
        exitWithError("API request failed: \(error)")
    }
    
    guard let data = responseData else {
        exitWithError("No data received from API")
    }
    
    // デバッグ用にレスポンス全体を表示
    if let responseString = String(data: data, encoding: .utf8) {
        print("API レスポンス:")
        print(responseString)
        
        // レスポンスからPRレビュー文を抽出
        var prReview: String?
        
        do {
            if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                // 最初の抽出方法
                if let answer = json["answer"] as? String {
                    prReview = answer
                } else if let dataDict = json["data"] as? [String: Any] {
                    // 代替抽出方法
                    if let answer = dataDict["answer"] as? String {
                        prReview = answer
                    } else if let outputs = dataDict["outputs"] as? [String: Any], 
                              let text = outputs["text"] as? String {
                        prReview = text
                    }
                }
            }
        } catch {
            print("JSON parsing error: \(error)")
        }
        
        // 抽出結果の確認
        if let review = prReview, !review.isEmpty {
            // PRレビュー文をクリップボードにコピー
            copyToClipboard(review)
            
            // 完了メッセージ
            print("PR review created and copied to clipboard")
            print("--------- Created PR Review ---------")
            print(review)
        } else {
            print("Failed to extract PR review, copying original response")
            copyToClipboard(responseString)
            print("Original response copied to clipboard")
        }
    } else {
        exitWithError("Could not decode response data")
    }
}

// プログラム実行
main()

