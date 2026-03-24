#!/bin/bash
set -e

SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/lib/common.sh"

warning "⚠️  /cleanup is deprecated and will be removed in a future version."
echo ""
echo "Cleanup is now integrated into /csw:spec."
echo "Completed specs are automatically cleaned at the start of each new spec cycle."
echo ""
echo "To clean up now, start a new spec:"
echo "  csw spec <feature-name>"
echo ""
exit 0
