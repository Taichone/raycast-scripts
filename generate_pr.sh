#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Create PR Description
# @raycast.mode compact

# Optional parameters:
# @raycast.icon ./Assets/GitHub.png
# @raycast.argument1 { "type": "dropdown", "placeholder": "Language", "optional": true, "data": [{"title": "English", "value": "english"}, {"title": "Japanese", "value": "japanese"}] }
# @raycast.argument2 { "type": "text", "placeholder": "Diff (optional)", "optional": true }
# @raycast.packageName Dify

# .envファイルが存在する場合は読み込む
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

# 環境変数の取得
DIFY_BASE_URL=$DIFY_BASE_URL
DIFY_API_TOKEN=$DIFY_PR_GENERATOR_API_TOKEN

# 環境変数チェック
if [ -z "$DIFY_BASE_URL" ]; then
  echo "Error: DIFY_BASE_URL is not set"
  exit 1
fi

if [ -z "$DIFY_API_TOKEN" ]; then
  echo "Error: DIFY_PR_TOKEN is not set"
  exit 1
fi

# 引数から環境を取得
LANGUAGE="$1"
if [ -z "$LANGUAGE" ]; then
  LANGUAGE="english"
fi

echo "Selected language: $LANGUAGE"

# 引数からdiffを取得、空の場合はクリップボードから取得
GIT_DIFF="$2"
if [ -z "$GIT_DIFF" ]; then
  echo "No diff provided as argument. Getting diff from clipboard..."
  GIT_DIFF=$(pbpaste)
  
  # クリップボードも空の場合は終了
  if [ -z "$GIT_DIFF" ]; then
    echo "Error: No diff found in clipboard. Please provide a diff as an argument or copy it to clipboard."
    exit 1
  fi
fi

echo "Generating PR description for $LANGUAGE language..."

# JSONデータの準備
JSON_DATA='{
  "inputs": {
    "language": "'"$LANGUAGE"'",
    "git_diff": '"$(echo "$GIT_DIFF" | jq -sR .)"'
  },
  "response_mode": "blocking",
  "user": "raycast-user"
}'

# Dify APIリクエスト送信
RESPONSE=$(curl -s -X POST "${DIFY_BASE_URL}/workflows/run" \
  -H "Authorization: Bearer ${DIFY_API_TOKEN}" \
  -H "Content-Type: application/json" \
  --data "${JSON_DATA}")

echo "$RESPONSE" | jq '.'

# レスポンスからPRレビュー文を抽出（jqを使用）
PR_DESCRIPTION=$(echo "$RESPONSE" | jq -r '.data.outputs.result')

# 抽出結果の確認
if [ -z "$PR_DESCRIPTION" ] || [ "$PR_DESCRIPTION" = "null" ]; then
  echo "Error: Unable to extract PR description"
  echo "$RESPONSE" | pbcopy
  echo "--------- Error: Copied Response to Clipboard ---------"
else
  echo "$PR_DESCRIPTION" | pbcopy
  echo "--------- Success: Copied PR Description to Clipboard ---------"
  echo "$PR_DESCRIPTION"
fi