#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Create PR Review
# @raycast.mode compact

# Optional parameters:
# @raycast.icon ./icons/dify.png
# @raycast.argument1 { "type": "dropdown", "placeholder": "Language", "optional": true, "data": [{"title": "English", "value": "english"}, {"title": "Japanese", "value": "japanese"}] }
# @raycast.argument2 { "type": "text", "placeholder": "Diff (optional)", "optional": true }
# @raycast.packageName Dify

# 環境変数の設定
# @raycast.refreshTime 1h
# @raycast.preferenceValues [{"name":"DIFY_BASE_URL", "type":"textfield", "required":true, "title":"Dify Base URL", "description":"Dify APIのベースURL", "default":"https://dify.arklet.jp/v1"}, {"name":"DIFY_PR_GENERATOR_API_TOKEN", "type":"password", "required":true, "title":"Dify PR Generator API Token", "description":"PR生成AIのAPIトークン"}]

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

echo "Generating PR review for $LANGUAGE language..."

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
RESPONSE=$(curl -s -X POST "${DIFY_BASE_URL}/completion-messages" \
  -H "Authorization: Bearer ${DIFY_API_TOKEN}" \
  -H "Content-Type: application/json" \
  --data "${JSON_DATA}")

# デバッグ用にレスポンス全体を表示
echo "API レスポンス:"
echo "$RESPONSE" | jq '.'

# レスポンスからPRレビュー文を抽出（jqを使用）
PR_REVIEW=$(echo "$RESPONSE" | jq -r '.answer')

# 抽出結果の確認
if [ -z "$PR_REVIEW" ] || [ "$PR_REVIEW" = "null" ]; then
  echo "Error: Unable to extract PR review"
  echo "Trying alternative extraction method..."
  # 代替抽出方法を試す
  PR_REVIEW=$(echo "$RESPONSE" | jq -r '.data.answer // .data.outputs.text')
  
  # それでも空なら
  if [ -z "$PR_REVIEW" ] || [ "$PR_REVIEW" = "null" ]; then
    echo "Alternative extraction also failed. Copying original response..."
    PR_REVIEW="$RESPONSE"
  fi
fi

# PRレビュー文をクリップボードにコピー
echo "$PR_REVIEW" | pbcopy

# 完了メッセージ
echo "PR review created and copied to clipboard"
echo "--------- Created PR Review ---------"
echo "$PR_REVIEW" 