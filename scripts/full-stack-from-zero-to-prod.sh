#!/bin/bash

# Full-Stack T3 Deployment Script
# Deploys complete T3 stack applications from zero to production
# Force mode enabled by default - will destroy existing resources

set -e  # Exit on any error

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

# Step 1: Environment Setup
log_info "Starting T3 Stack Deployment..."

# Get app name from current directory or use argument
APP_NAME=${1:-$(basename "$PWD")}
log_info "Deploying app: $APP_NAME"

# Force mode enabled by default
FORCE_MODE=${FORCE_MODE:-true}
log_info "Force mode: $FORCE_MODE"

# Step 2: Install Prerequisites
log_info "Checking and installing prerequisites..."

# Check and install jq
if ! command -v jq >/dev/null 2>&1; then
    log_info "Installing jq"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install jq
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sudo apt-get update && sudo apt-get install -y jq
    fi
else
    log_success "jq already installed"
fi



# Check and install GitHub CLI
if ! command -v gh >/dev/null 2>&1; then
    log_info "Installing GitHub CLI"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install gh
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        type -p curl >/dev/null || sudo apt install curl -y
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
        sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
        sudo apt update && sudo apt install gh -y
    fi
else
    log_success "GitHub CLI already installed"
fi

# Check and install Vercel CLI
if ! command -v vercel >/dev/null 2>&1; then
    log_info "Installing Vercel CLI"
    npm install -g vercel
else
    log_success "Vercel CLI already installed"
fi

# Check and install Neon CLI
if ! command -v neonctl >/dev/null 2>&1; then
    log_info "Installing Neon CLI"
    npm install -g neonctl
else
    log_success "Neon CLI already installed"
fi

# Step 3: Authentication
log_info "Checking authentication status..."

# GitHub authentication
if ! gh auth status >/dev/null 2>&1; then
    log_warning "GitHub authentication required"
    log_info "Opening browser for GitHub authentication..."
    gh auth login --web
    log_info "Waiting for authentication to complete..."
    sleep 10
    
    # Verify authentication
    if ! gh auth status >/dev/null 2>&1; then
        log_error "GitHub authentication failed"
        exit 1
    fi
else
    log_success "GitHub authenticated"
fi

# For force mode, ensure delete permissions
if [[ "$FORCE_MODE" == "true" ]] && ! gh auth status 2>&1 | grep -q "delete_repo"; then
    log_warning "Requesting GitHub delete permissions for force mode"
    gh auth refresh -h github.com -s delete_repo
fi

# Vercel authentication
if ! vercel whoami >/dev/null 2>&1; then
    log_warning "Vercel authentication required"
    log_info "Opening browser for Vercel authentication..."
    vercel login
    log_info "Waiting for authentication to complete..."
    sleep 10
    
    # Verify authentication
    if ! vercel whoami >/dev/null 2>&1; then
        log_error "Vercel authentication failed"
        exit 1
    fi
else
    log_success "Vercel authenticated"
fi

# Neon authentication
if ! neonctl orgs list >/dev/null 2>&1; then
    log_warning "Neon authentication required"
    log_info "Opening browser for Neon authentication..."
    neonctl auth
    log_info "Waiting for authentication to complete..."
    sleep 30
    
    # Verify authentication
    if ! neonctl orgs list >/dev/null 2>&1; then
        log_error "Neon authentication failed"
        exit 1
    fi
else
    log_success "Neon authenticated"
fi

# Get authenticated user
GITHUB_USER=$(gh api user --jq .login)
log_success "Authenticated GitHub user: $GITHUB_USER"

# Set Neon context to avoid prompts
log_info "Setting up Neon context..."
ORG_ID=$(neonctl orgs list --output json | jq -r '.[0].id')
neonctl set-context --org-id $ORG_ID
log_success "Neon context set to organization: $ORG_ID"

# Step 4: Resource Cleanup (Force Mode)
if [[ "$FORCE_MODE" == "true" ]]; then
    log_warning "Cleaning up existing resources (Force mode enabled)"
    
    # Delete GitHub repository
    if gh repo view $APP_NAME >/dev/null 2>&1; then
        log_info "Deleting GitHub repository"
        gh repo delete $APP_NAME --yes
    fi
    
    # Delete Neon project
    log_info "Getting list of Neon projects..."
    EXISTING_PROJECTS=$(neonctl projects list --output json)
    log_info "Neon projects list completed, searching for existing project with name: $APP_NAME"
    PROJECT_ID=$(echo "$EXISTING_PROJECTS" | jq -r ".[] | select(.name == \"$APP_NAME\") | .id")
    
    if [[ -n "$PROJECT_ID" && "$PROJECT_ID" != "null" ]]; then
        log_info "Found Neon project: $PROJECT_ID, deleting..."
        neonctl projects delete $PROJECT_ID --yes || {
            log_warning "Neon project deletion failed. Please delete manually if needed."
        }
        log_success "Neon project deleted successfully"
    else
        log_info "No existing Neon project found with name: $APP_NAME"
    fi
    
    # Delete Vercel project
    log_info "Checking for existing Vercel projects..."
    VERCEL_PROJECTS=$(vercel ls --yes 2>/dev/null || echo "")
    if echo "$VERCEL_PROJECTS" | grep -q "$APP_NAME"; then
        log_info "Found Vercel project, deleting: $APP_NAME"
        echo 'y' | vercel remove $APP_NAME --yes || {
            log_warning "Vercel project deletion failed"
        }
        log_success "Vercel project deleted successfully"
    else
        log_info "No existing Vercel project found with name: $APP_NAME"
    fi
    
    # Remove local directory
    log_info "Checking for local directory: $APP_NAME"
    if [[ -d "$APP_NAME" ]]; then
        log_info "Found local directory, removing: $APP_NAME"
        rm -rf $APP_NAME
        log_success "Local directory removed successfully"
    else
        log_info "No local directory found (this is normal for clean deployment)"
    fi
    
    log_success "Resource cleanup phase completed"
fi

# Step 5: Conflict Detection (Non-Force Mode)
if [[ "$FORCE_MODE" == "false" ]]; then
    log_info "Checking for conflicts..."
    CONFLICTS=false
    
    # Check GitHub repository
    if gh repo view $GITHUB_USER/$APP_NAME >/dev/null 2>&1; then
        log_error "GitHub repository '$GITHUB_USER/$APP_NAME' already exists"
        CONFLICTS=true
    fi
    
    # Check Neon projects
    EXISTING_PROJECTS=$(neonctl projects list --output json)
    PROJECT_ID=$(echo "$EXISTING_PROJECTS" | jq -r ".[] | select(.name == \"$APP_NAME\") | .id")
    
    if [[ -n "$PROJECT_ID" && "$PROJECT_ID" != "null" ]]; then
        log_error "Neon project '$APP_NAME' already exists"
        CONFLICTS=true
    fi
    
    # Check Vercel projects
    if vercel ls 2>/dev/null | grep -q "$APP_NAME"; then
        log_error "Vercel project '$APP_NAME' already exists"
        CONFLICTS=true
    fi
    
    # Check local directory
    if [[ -d "$APP_NAME" ]]; then
        log_error "Directory '$APP_NAME' already exists"
        CONFLICTS=true
    fi
    
    if [[ "$CONFLICTS" == "true" ]]; then
        log_error "Conflicts detected. Set FORCE_MODE=true to overwrite"
        exit 1
    fi
    
    log_success "No conflicts detected"
fi

# Step 6: Create T3 Application
log_info "Creating T3 application..."
npx create-t3-app@latest $APP_NAME \
    --CI \
    --tailwind true \
    --nextAuth false \
    --prisma true \
    --trpc true \
    --appRouter true \
    --dbProvider postgres \
    --eslint true

cd $APP_NAME
log_success "T3 application created"

# Step 7: Create GitHub Repository
log_info "Creating GitHub repository..."
git add .
git commit -m "Initial T3 setup with PostgreSQL"

# Create public repository and push
gh repo create $APP_NAME --public --source=. --remote=origin --push
REPO_URL="https://github.com/$GITHUB_USER/$APP_NAME"
log_success "GitHub repository created: $REPO_URL"

# Step 8: Create Neon Database
log_info "Creating Neon database..."

# Get organization ID
ORG_ID=$(neonctl orgs list --output json | jq -r '.[0].id')
log_info "Using organization: $ORG_ID"

# Create database project
DB_RESPONSE=$(neonctl projects create \
    --name $APP_NAME \
    --org-id $ORG_ID \
    --output json)

# Extract connection details
DB_URL=$(echo "$DB_RESPONSE" | jq -r '.connection_uris[0].connection_uri')
PROJECT_ID=$(echo "$DB_RESPONSE" | jq -r '.project.id')

if [[ -z "$DB_URL" || "$DB_URL" == "null" ]]; then
    log_error "Failed to create database"
    log_error "Debug response: $DB_RESPONSE"
    exit 1
fi

# Get the proper connection string with all required parameters
DB_URL=$(neonctl connection-string --project-id $PROJECT_ID --database neondb --role neondb_owner)

log_success "Database created: $PROJECT_ID"
log_info "Database URL: $DB_URL"

# Step 9: Deploy to Vercel
log_info "Deploying to Vercel..."

# Deploy to Vercel (auto-answer setup prompts)
echo "y" | vercel --prod --yes

log_info "Adding database configuration"
# Add database URL to Vercel environment
echo "$DB_URL" | vercel env add DATABASE_URL production

log_info "Deploying database schema"
# Deploy Prisma schema to database
DATABASE_URL="$DB_URL" npx prisma db push

log_info "Final deployment"
# Final deployment with database connected
PRODUCTION_URL=$(vercel --prod --yes | grep "Production:" | awk '{print $2}')

# Extract domain information
PROJECT_DOMAIN=""
if [[ -n "$PRODUCTION_URL" ]]; then
    # Get the base domain (project name)
    PROJECT_DOMAIN=$(echo "$PRODUCTION_URL" | sed 's|https://||' | cut -d'-' -f1)
    if [[ -n "$PROJECT_DOMAIN" ]]; then
        PROJECT_DOMAIN="${PROJECT_DOMAIN}.vercel.app"
    fi
fi

# Step 10: Success Output
echo ""
log_success "🎉 DEPLOYMENT COMPLETE! 🎉"
echo ""
echo -e "${GREEN}📱 App Details:${NC}"
echo -e "   ${BLUE}Specific URL:${NC} $PRODUCTION_URL"
if [[ -n "$PROJECT_DOMAIN" ]]; then
    echo -e "   ${BLUE}Domain:${NC} https://$PROJECT_DOMAIN"
fi
echo -e "   ${BLUE}GitHub:${NC} $REPO_URL"
echo -e "   ${BLUE}Database:${NC} $PROJECT_ID (Neon PostgreSQL)"
echo ""

# Verify deployment
log_info "Verifying deployment..."
if curl -s --head "$PRODUCTION_URL" | head -n 1 | grep -q "200 OK"; then
    log_success "Application is live and responding!"
else
    log_warning "Application may still be deploying. Check $PRODUCTION_URL in a few minutes."
fi

# Display environment variables for verification
log_info "Environment variables configured:"
vercel env list

# Additional debugging - check if DATABASE_URL is actually set
log_info "Verifying DATABASE_URL is set correctly..."
vercel env list | grep DATABASE_URL || log_warning "DATABASE_URL not found in environment variables!"

# Wait a moment for deployment to stabilize
log_info "Waiting for deployment to stabilize..."
sleep 10

log_success "T3 Stack deployment completed successfully!"
echo ""
echo -e "${YELLOW}🚀 Next steps:${NC}"
echo "1. 🌐 Visit your app:"
echo "   • Latest deployment: $PRODUCTION_URL"
if [[ -n "$PROJECT_DOMAIN" ]]; then
    echo "   • Project domain: https://$PROJECT_DOMAIN"
fi
echo "2. 📝 Check the repository: $REPO_URL"
echo "3. 💻 For local development: cd $APP_NAME && npm run dev"
echo "4. 🗄️  Database management: https://console.neon.tech/app/projects/$PROJECT_ID"
echo "5. 📋 View all links: cat docs/links.md"
echo ""
echo -e "${GREEN}🎯 Quick Links:${NC}"
echo "• App: $PRODUCTION_URL"
echo "• Repo: $REPO_URL"
echo "• DB: https://console.neon.tech/app/projects/$PROJECT_ID"
echo ""

# Create docs directory and links file
log_info "Creating documentation with deployment links..."
mkdir -p docs

# Create links.md file with all deployment information
cat > docs/links.md << EOF
# ${APP_NAME} - Deployment Links

## 🚀 Live Application
- **Latest Deployment**: $PRODUCTION_URL
$(if [[ -n "$PROJECT_DOMAIN" ]]; then echo "- **Project Domain**: https://$PROJECT_DOMAIN"; fi)

## 📝 Repository
- **GitHub**: $REPO_URL
- **Clone**: \`git clone $REPO_URL.git\`

## 🗄️ Database
- **Provider**: Neon PostgreSQL
- **Project ID**: $PROJECT_ID
- **Console**: https://console.neon.tech/app/projects/$PROJECT_ID

## 🛠️ Development
\`\`\`bash
# Clone the repository
git clone $REPO_URL.git
cd $APP_NAME

# Install dependencies
npm install

# Start development server
npm run dev
\`\`\`

## 📊 Management URLs
- **Vercel Dashboard**: https://vercel.com/dashboard
- **Neon Console**: https://console.neon.tech/
- **GitHub Repository**: $REPO_URL

---
*Generated on $(date) by T3 Deployment Script*
EOF

log_success "Deployment links saved to docs/links.md"