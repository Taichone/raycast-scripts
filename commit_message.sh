#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Create Commit Message
# @raycast.mode compact

# Optional parameters:
# @raycast.icon ./images/GitHub.png
# @raycast.argument1 { "type": "dropdown", "placeholder": "Language", "optional": true, "data": [{"title": "English", "value": "english"}, {"title": "Japanese", "value": "japanese"}] }
# @raycast.argument2 { "type": "text", "placeholder": "Diff (optional)", "optional": true }
# @raycast.packageName Dify

# 環境変数の取得 ---
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

DIFY_BASE_URL=$DIFY_BASE_URL
DIFY_API_TOKEN=$DIFY_COMMIT_MESSAGE_GENERATOR_API_TOKEN

if [ -z "$DIFY_BASE_URL" ]; then
  echo "Error: DIFY_BASE_URL is not set"
  exit 1
fi

if [ -z "$DIFY_API_TOKEN" ]; then
  echo "Error: DIFY_COMMIT_MESSAGE_GENERATOR_API_TOKEN is not set"
  exit 1
fi

# 引数を確認 ---
LANGUAGE="$1"
if [ -z "$LANGUAGE" ]; then
  LANGUAGE="english"
fi

GIT_DIFF="$2"

# 引数がない場合はクリップボードから取得
if [ -z "$GIT_DIFF" ]; then
  echo "No diff provided as argument. Getting diff from clipboard..."
  GIT_DIFF=$(pbpaste)
  if [ -z "$GIT_DIFF" ]; then
    echo "Error: No diff found in clipboard. Please provide a diff as an argument or copy it to clipboard."
    exit 1
  fi
fi

# Dify ワークフロー ---
echo "Generating PR description for $LANGUAGE language..."

JSON_DATA='{
  "inputs": {
    "language": "'"$LANGUAGE"'",
    "git_diff": '"$(echo "$GIT_DIFF" | jq -sR .)"'
  },
  "response_mode": "blocking",
  "user": "raycast-user"
}'

RESPONSE=$(curl -s -X POST "${DIFY_BASE_URL}/workflows/run" \
  -H "Authorization: Bearer ${DIFY_API_TOKEN}" \
  -H "Content-Type: application/json" \
  --data "${JSON_DATA}")

echo "$RESPONSE" | jq '.'

# レスポンスから値を抽出（jqを使用）
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