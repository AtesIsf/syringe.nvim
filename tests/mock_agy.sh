#!/usr/bin/env bash
PROMPT=""
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --prompt) PROMPT="$2"; shift ;;
  esac
  shift
done

INPUT=$(cat)
UPPER=$(echo "$INPUT" | tr '[:lower:]' '[:upper:]')
echo '```'
echo -n "${UPPER} - ${PROMPT}"
echo
echo '```'
