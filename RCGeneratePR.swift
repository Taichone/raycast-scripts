#!/usr/bin/swift

// Required parameters:
// @raycast.schemaVersion 1
// @raycast.title PR Generator
// @raycast.mode compact

// Optional parameters:
// @raycast.icon ./Assets/GitHub.png
// @raycast.argument1 { "type": "dropdown", "placeholder": "Language", "optional": false, "data": [{"title": "English", "value": "english"}, {"title": "Japanese", "value": "japanese"}] }
// @raycast.argument2 { "type": "text", "placeholder": "Diff (optional)", "optional": true }
// @raycast.packageName Dify

import Foundation

let argumentsCount = 1

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

func main() {
    Task {
        do {
            // 環境変数を読み込む
            let env = try EnvReader.getEnvDict()
            guard let difyBaseURL = env["DIFY_BASE_URL"], !difyBaseURL.isEmpty else {
                throw NSError(domain: "EnvReaderError", code: 1, userInfo: [NSLocalizedDescriptionKey: "DIFY_BASE_URL is not set"])
            }
            guard let difyAPIToken = env["DIFY_PR_GENERATOR_API_TOKEN"], !difyAPIToken.isEmpty else {
                throw NSError(domain: "EnvReaderError", code: 1, userInfo: [NSLocalizedDescriptionKey: "DIFY_PR_GENERATOR_API_TOKEN is not set"])
            }
            
            // Raycast 引数を読み込む
            let arguments = CommandLine.arguments
            guard arguments.count > argumentsCount else {
                throw NSError(domain: "EnvReaderError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Please specify a title"])
            }
            let language = arguments[1]
            
            // Request
            // Diff（オプション引数）
            var diffContent = ""
            if arguments.count >= 3 && !arguments[2].isEmpty {
                diffContent = arguments[2]
            } else {
                if let clipboardContent = getClipboardContent(), !clipboardContent.isEmpty {
                    diffContent = clipboardContent
                } else {
                    throw NSError(domain: "EnvReaderError", code: 1, userInfo: [NSLocalizedDescriptionKey: "No diff found in clipboard. Please provide a diff as an argument or copy it to clipboard."])
                }
            }
            
            // JSON データの準備
            // gitDiffをJSONエスケープする必要がある
            let jsonData = """
            {
              "inputs": {
                "language": "\(language)",
                "git_diff": \(diffContent.data(using: .utf8)!.base64EncodedString().debugDescription)
              },
              "response_mode": "blocking",
              "user": "raycast-user"
            }
            """
            
            // URLリクエストの準備
            guard let url = URL(string: "\(difyBaseURL)/completion-messages") else {
                throw NSError(domain: "EnvReaderError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("Bearer \(difyAPIToken)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = jsonData.data(using: .utf8)
            
            // APIリクエスト送信と応答の受信
            let (data, _) = try await URLSession.shared.data(for: request)
            
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
                    throw NSError(domain: "EnvReaderError", code: 1, userInfo: [NSLocalizedDescriptionKey: "JSON parsing error: \(error)"])
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
                    throw NSError(
                        domain: "EnvReaderError",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to extract PR review, copying original response: \(responseString)"]
                    )
                }
            } else {
                throw NSError(domain: "EnvReaderError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not decode response data"])
            }
        } catch {
            print("ERROR: \(error)")
            exit(1)
        }
        
        print("Successfully generated PR description!")
        exit(0)
    }
    
    RunLoop.main.run()
}

main()