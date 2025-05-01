#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Add Notion Todo
# @raycast.mode compact

# Optional parameters:
# @raycast.icon ./images/notion.png
# @raycast.argument1 { "type": "text", "placeholder": "Title" }
# @raycast.argument2 { "type": "text", "placeholder": "Date (yyyy-mm-dd, +n)", "optional": true }
# @raycast.packageName Notion

# エラーハンドリング
set -e

# 環境変数を読み込む
load_env() {
  if [ ! -f ./.env ]; then
    echo "ERROR: Failed to read .env file"
    exit 1
  fi
  
  # .envファイルを読み込む
  set -a
  source ./.env
  set +a
  
  # 必要な環境変数をチェック
  if [ -z "$NOTION_TOKEN" ]; then
    echo "ERROR: NOTION_TOKEN is not set"
    exit 1
  fi
  
  if [ -z "$NOTION_TASK_DATABASE_ID" ]; then
    echo "ERROR: NOTION_TASK_DATABASE_ID is not set"
    exit 1
  fi
}

# 日付バリデーション
validate_date() {
  local date_string="$1"
  
  # 空の場合は今日の日付を返す
  if [ -z "$date_string" ]; then
    date "+%Y-%m-%d"
    return
  fi
  
  # N日後の処理
  if [[ "$date_string" =~ ^\+([0-9]+)$ ]]; then
    days_to_add="${BASH_REMATCH[1]}"
    if [[ "$(uname)" == "Darwin" ]]; then
      # macOS
      date -v+${days_to_add}d "+%Y-%m-%d"
    else
      # Linux
      date -d "+${days_to_add} days" "+%Y-%m-%d"
    fi
    return
  fi
  
  # YYYY-MM-DD 形式
  if [[ "$date_string" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "$date_string"
    return
  fi
  
  echo "ERROR: Invalid date format"
  exit 1
}

# Notionにタスクを作成
create_todo() {
  local title="$1"
  local start_date="$2"
  
  # JSONデータを作成
  json_data=$(cat << EOF
{
  "parent": { "database_id": "$NOTION_TASK_DATABASE_ID" },
  "properties": {
    "Title": {
      "title": [
        {
          "text": {
            "content": "$title"
          }
        }
      ]
    },
    "Date": {
      "date": {
        "start": "$start_date"
      }
    }
  }
}
EOF
)

  # APIリクエスト
  response=$(curl -s -X POST "https://api.notion.com/v1/pages" \
    -H "Authorization: Bearer $NOTION_TOKEN" \
    -H "Content-Type: application/json" \
    -H "Notion-Version: 2022-06-28" \
    -d "$json_data")
  
  # エラーチェック
  if [[ "$response" == *"error"* ]]; then
    echo "ERROR: An error occurred: $response"
    exit 1
  fi
}

main() {
  # 環境変数をロード
  load_env
  
  # 引数をチェック
  if [ -z "$1" ]; then
    echo "ERROR: Please specify a title"
    exit 1
  fi
  
  title="$1"
  custom_date="$2"
  
  # 日付を検証
  start_date=$(validate_date "$custom_date")
  
  # Notionタスクを作成
  create_todo "$title" "$start_date"
  
  echo "Successfully created Todo!"
}

main "$@"
