#!/usr/bin/env bash

if ! command -v ollama >/dev/null 2>&1; then
    exit 127
fi

# Keep the installed runtime visible while its service is offline.
model_names=$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' || true)

# Build a JSON array
json_array="["
for name in $model_names; do
    json_array+="\"$name\","
done

# Remove trailing comma and close the array
json_array="${json_array%,}]"

# Output the JSON array
echo "$json_array"
