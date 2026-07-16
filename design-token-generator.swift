#!/bin/bash

set -euo pipefail

PROJECT_ROOT="${SRCROOT:-$(pwd)}"

FIGMA_DIR="${PROJECT_ROOT}/MyApp/Resources/FigmaColors"

TOKEN_DIR="${FIGMA_DIR}/Tokens"

LIGHT_JSON="${TOKEN_DIR}/Light.json"
DARK_JSON="${TOKEN_DIR}/Dark.json"

OUTPUT_XCASSETS="${FIGMA_DIR}/DesignColors.xcassets"
OUTPUT_SWIFT="${FIGMA_DIR}/Generated/DesignColors.swift"

SCRIPT_DIR="${PROJECT_ROOT}/Scripts"

mkdir -p "${FIGMA_DIR}/Generated"

echo "Generating xcassets..."

"${SCRIPT_DIR}/figma-to-xcassets.swift" \
    --light "${LIGHT_JSON}" \
    --dark "${DARK_JSON}" \
    --output "${OUTPUT_XCASSETS}" \
    --preserve-groups

echo "Generating Swift wrapper..."

"${SCRIPT_DIR}/generate-color-code.swift" \
    --input "${OUTPUT_XCASSETS}" \
    --output "${OUTPUT_SWIFT}" \
    --type-name DesignColors \
    --bundle .main

echo "Done!"