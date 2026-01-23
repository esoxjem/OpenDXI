#!/bin/bash
#
# Coolify Deployment Pre-Validation Script
#
# Validates Dockerfiles before deploying to Coolify to catch common issues:
# 1. Docker BuildKit strict linting (secrets in ARG/ENV)
# 2. API-only Rails apps with assets:precompile
# 3. Alpine images missing curl for health checks
#
# Usage:
#   ./scripts/validate-coolify-deployment.sh [path-to-dockerfile]
#
# If no path is provided, validates all Dockerfiles in the repository.
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS=0
WARNINGS=0

log_ok() {
    echo -e "${GREEN}OK${NC}"
}

log_warning() {
    echo -e "${YELLOW}WARNING${NC}"
    WARNINGS=$((WARNINGS + 1))
}

log_error() {
    echo -e "${RED}ERROR${NC}"
    ERRORS=$((ERRORS + 1))
}

validate_dockerfile() {
    local dockerfile="$1"
    local dir=$(dirname "$dockerfile")

    echo ""
    echo "=== Validating: $dockerfile ==="
    echo ""

    # Check 1: BuildKit syntax directive
    echo -n "[1/5] BuildKit syntax directive... "
    if head -1 "$dockerfile" | grep -q "syntax=docker/dockerfile"; then
        log_ok
    else
        log_warning
        echo "      Add at line 1: # syntax=docker/dockerfile:1"
    fi

    # Check 2: BuildKit lint skip for secrets
    echo -n "[2/5] BuildKit secrets lint skip... "
    SECRETS_FOUND=$(grep -E "^(ARG|ENV).*(SECRET|TOKEN|KEY|PASSWORD|CREDENTIAL|MASTER)" "$dockerfile" 2>/dev/null | head -5 || true)
    if [ -n "$SECRETS_FOUND" ]; then
        if head -5 "$dockerfile" | grep -q "skip=SecretsUsedInArgOrEnv"; then
            log_ok
            echo "      (secrets in ARG/ENV, but lint skip is present)"
        else
            log_error
            echo "      Found secrets in ARG/ENV without lint skip:"
            echo "$SECRETS_FOUND" | sed 's/^/        /'
            echo "      Add at line 2: # check=error=true;skip=SecretsUsedInArgOrEnv"
        fi
    else
        log_ok
        echo "      (no secrets detected in ARG/ENV)"
    fi

    # Check 3: Alpine image with curl
    echo -n "[3/5] Alpine image curl check... "
    if grep -qi "alpine" "$dockerfile"; then
        # Check if curl is installed in runner/final stage
        # Look for apk add curl after the last FROM
        LAST_FROM_LINE=$(grep -n "^FROM" "$dockerfile" | tail -1 | cut -d: -f1)
        AFTER_LAST_FROM=$(tail -n +$LAST_FROM_LINE "$dockerfile")

        if echo "$AFTER_LAST_FROM" | grep -q "apk add.*curl"; then
            log_ok
        else
            log_error
            echo "      Alpine image detected but curl not installed in final stage"
            echo "      Add: RUN apk add --no-cache curl"
        fi
    else
        log_ok
        echo "      (not Alpine-based)"
    fi

    # Check 4: API-only Rails apps
    echo -n "[4/5] Rails API-only assets check... "
    if [ -f "$dir/config/application.rb" ]; then
        if grep -q "config.api_only = true" "$dir/config/application.rb" 2>/dev/null; then
            # Only check for uncommented RUN commands with assets:precompile
            if grep -E "^RUN.*assets:precompile" "$dockerfile" >/dev/null 2>&1; then
                log_error
                echo "      API-only Rails app has assets:precompile in Dockerfile"
                echo "      Remove or comment out: RUN ... assets:precompile"
            else
                log_ok
                echo "      (API-only, no assets:precompile)"
            fi
        else
            log_ok
            echo "      (full Rails app with asset pipeline)"
        fi
    else
        log_ok
        echo "      (not a Rails app)"
    fi

    # Check 5: Health endpoint
    echo -n "[5/5] Health endpoint verification... "
    if [ -f "$dir/config/routes.rb" ]; then
        # Rails app
        if grep -qE "(health|/up)" "$dir/config/routes.rb" 2>/dev/null; then
            log_ok
            echo "      (Rails health endpoint found)"
        else
            log_warning
            echo "      No health endpoint in routes.rb"
            echo "      Add: get 'up' => 'rails/health#show'"
        fi
    elif [ -f "$dir/src/app/api/health/route.ts" ] || [ -f "$dir/app/api/health/route.ts" ]; then
        # Next.js app
        log_ok
        echo "      (Next.js health endpoint found)"
    elif [ -f "$dir/package.json" ] && grep -q "next" "$dir/package.json" 2>/dev/null; then
        # Next.js without health endpoint
        log_warning
        echo "      Next.js app without dedicated health endpoint"
        echo "      Create: src/app/api/health/route.ts"
    else
        log_warning
        echo "      Could not verify health endpoint exists"
    fi
}

# Main execution
echo "========================================"
echo "  Coolify Deployment Pre-Validation"
echo "========================================"

if [ -n "$1" ]; then
    # Validate specific Dockerfile
    if [ -f "$1" ]; then
        validate_dockerfile "$1"
    else
        echo "Error: File not found: $1"
        exit 1
    fi
else
    # Find and validate all Dockerfiles
    DOCKERFILES=$(find . -name "Dockerfile" -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null)

    if [ -z "$DOCKERFILES" ]; then
        echo "No Dockerfiles found in current directory"
        exit 1
    fi

    for df in $DOCKERFILES; do
        validate_dockerfile "$df"
    done
fi

# Summary
echo ""
echo "========================================"
echo "  Summary"
echo "========================================"

if [ $ERRORS -gt 0 ]; then
    echo -e "${RED}$ERRORS error(s) found - deployment will likely fail${NC}"
fi

if [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}$WARNINGS warning(s) found - review before deploying${NC}"
fi

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}All checks passed! Ready for Coolify deployment.${NC}"
fi

echo ""

# Exit with error if any errors found
if [ $ERRORS -gt 0 ]; then
    exit 1
fi

exit 0
