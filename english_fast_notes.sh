#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Add English Fast Note
# @raycast.mode compact

# Optional parameters:
# @raycast.icon ./images/notion.png
# @raycast.argument1 { "type": "text", "placeholder": "Name" }
# @raycast.argument2 { "type": "text", "placeholder": "Description" }
# @raycast.argument3 { "type": "text", "placeholder": "Type (g/v/p)" }
# @raycast.packageName Notion

# Error handling
set -e

# Load environment variables
load_env() {
  if [ ! -f ./.env ]; then
    echo "ERROR: Failed to read .env file"
    exit 1
  fi

  # Load .env file
  set -a
  source ./.env
  set +a

  # Check required environment variables
  if [ -z "$NOTION_ENGLISH_TOKEN" ]; then
    echo "ERROR: NOTION_ENGLISH_TOKEN is not set"
    exit 1
  fi

  if [ -z "$NOTION_ENGLISH_FAST_NOTES_DATABASE_ID" ]; then
    echo "ERROR: NOTION_ENGLISH_FAST_NOTES_DATABASE_ID is not set"
    exit 1
  fi
}

# Validate Type argument and convert shorthand
validate_type() {
  local type="$1"

  case "$type" in
    G|g|grammar)
      echo "Grammar"
      ;;
    V|v|vocabulary)
      echo "Vocabulary"
      ;;
    P|p|pronounce)
      echo "Pronounce"
      ;;
    Grammar|Vocabulary|Pronounce)
      echo "$type"
      ;;
    *)
      echo "ERROR: Invalid type. Must be G/Grammar, V/Vocabulary, or P/Pronounce"
      exit 1
      ;;
  esac
}

# Create note in Notion
create_note() {
  local name="$1"
  local description="$2"
  local type="$3"

  # Create JSON data
  json_data=$(cat << EOF
{
  "parent": { "database_id": "$NOTION_ENGLISH_FAST_NOTES_DATABASE_ID" },
  "properties": {
    "Name": {
      "title": [
        {
          "text": {
            "content": "$name"
          }
        }
      ]
    },
    "Description": {
      "rich_text": [
        {
          "text": {
            "content": "$description"
          }
        }
      ]
    },
    "Type": {
      "select": {
        "name": "$type"
      }
    },
    "Status": {
      "status": {
        "name": "不明"
      }
    }
  }
}
EOF
)

  # API request
  response=$(curl -s -X POST "https://api.notion.com/v1/pages" \
    -H "Authorization: Bearer $NOTION_ENGLISH_TOKEN" \
    -H "Content-Type: application/json" \
    -H "Notion-Version: 2022-06-28" \
    -d "$json_data")

  # Error check
  if [[ "$response" == *"error"* ]]; then
    echo "ERROR: An error occurred: $response"
    exit 1
  fi
}

main() {
  # Load environment variables
  load_env

  # Check arguments
  if [ -z "$1" ]; then
    echo "ERROR: Please specify a name"
    exit 1
  fi

  if [ -z "$2" ]; then
    echo "ERROR: Please specify a description"
    exit 1
  fi

  if [ -z "$3" ]; then
    echo "ERROR: Please specify a type"
    exit 1
  fi

  name="$1"
  description="$2"
  type=$(validate_type "$3")

  # Create Notion note
  create_note "$name" "$description" "$type"

  echo "Successfully created English Fast Note!"
}

main "$@"
