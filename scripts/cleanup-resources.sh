#!/bin/bash

# Resource Cleanup Script
# Lists and optionally deletes Vercel and Neon resources
# Usage: ./cleanup-resources.sh [--force]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check for force mode
FORCE_MODE=false
if [[ "$1" == "--force" ]]; then
    FORCE_MODE=true
    log_warning "Force mode enabled - will delete all resources without prompting"
fi

# Function to prompt for deletion
prompt_delete() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_id="$3"
    
    if [[ "$FORCE_MODE" == "true" ]]; then
        echo -e "${RED}[FORCE DELETE]${NC} $resource_type: $resource_name"
        return 0
    else
        echo -e "${YELLOW}Found $resource_type:${NC} $resource_name"
        read -p "Delete this $resource_type? (y/N): " -r REPLY < /dev/tty
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            return 0
        else
            echo "Skipping..."
            return 1
        fi
    fi
}

log_info "Starting resource cleanup scan..."

# Check authentication
log_info "Checking authentication..."

# Check Vercel authentication
if ! vercel whoami >/dev/null 2>&1; then
    log_error "Vercel not authenticated. Run 'vercel login' first"
    exit 1
else
    VERCEL_USER=$(vercel whoami 2>/dev/null)
    log_success "Vercel authenticated as: $VERCEL_USER"
fi

# Check Neon authentication
if ! neonctl orgs list >/dev/null 2>&1; then
    log_error "Neon not authenticated. Run 'neonctl auth' first"
    exit 1
else
    ORG_ID=$(neonctl orgs list --output json | jq -r '.[0].id' 2>/dev/null)
    neonctl set-context --org-id $ORG_ID >/dev/null 2>&1
    log_success "Neon authenticated"
fi

echo ""
log_info "🔍 Scanning for resources..."
echo ""

# =============================================================================
# VERCEL PROJECTS
# =============================================================================
log_info "📦 Scanning Vercel projects..."

# Use vercel projects list and parse it directly from file
vercel projects list > /tmp/vercel_projects_temp.txt 2>&1
if grep -q "Project Name" /tmp/vercel_projects_temp.txt; then
    # Parse the table format, skip header and extract project names
    grep -A 999 "Project Name" /tmp/vercel_projects_temp.txt | tail -n +2 | grep -E "^  [a-zA-Z0-9-]" | while IFS= read -r line; do
        # Extract project name (first column, trim whitespace)
        PROJECT_NAME=$(echo "$line" | awk '{print $1}' | xargs)
        
        if [[ -n "$PROJECT_NAME" && "$PROJECT_NAME" != "" ]]; then
            if prompt_delete "Vercel project" "$PROJECT_NAME" ""; then
                log_info "Deleting Vercel project: $PROJECT_NAME"
                echo 'y' | vercel remove "$PROJECT_NAME" --yes 2>/dev/null || {
                    log_warning "Failed to delete Vercel project: $PROJECT_NAME"
                }
                log_success "Deleted Vercel project: $PROJECT_NAME"
            fi
        fi
    done
else
    log_info "No Vercel projects found"
fi
rm -f /tmp/vercel_projects_temp.txt

echo ""

# =============================================================================
# NEON PROJECTS
# =============================================================================
log_info "🗄️  Scanning Neon projects..."

NEON_PROJECTS=$(neonctl projects list --output json 2>/dev/null || echo "[]")
if [[ "$NEON_PROJECTS" != "[]" && -n "$NEON_PROJECTS" ]]; then
    echo "$NEON_PROJECTS" | jq -r '.[] | "\(.name)|\(.id)"' | while IFS='|' read -r project_name project_id; do
        if [[ -n "$project_name" && -n "$project_id" ]]; then
            if prompt_delete "Neon project" "$project_name" "$project_id"; then
                log_info "Deleting Neon project: $project_name ($project_id)"
                neonctl projects delete "$project_id" --yes 2>/dev/null || {
                    log_warning "Failed to delete Neon project: $project_name"
                }
                log_success "Deleted Neon project: $project_name"
            fi
        fi
    done
else
    log_info "No Neon projects found"
fi

echo ""

# =============================================================================
# SUMMARY
# =============================================================================
log_success "🧹 Resource cleanup completed!"
echo ""

if [[ "$FORCE_MODE" == "true" ]]; then
    log_info "All resources were processed in force mode"
else
    log_info "Only selected resources were deleted"
fi

echo ""
log_info "💡 To run cleanup in force mode (delete all without prompting):"
echo "   ./cleanup-resources.sh --force"
echo ""
log_info "📊 Check remaining resources:"
echo "   Vercel: vercel ls"
echo "   Neon: neonctl projects list"