#!/bin/bash
#
# Setup script for pg_ttl_index development environment
# This script helps set up everything you need to build and test the extension
#

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if PostgreSQL is installed
check_postgresql() {
    info "Checking PostgreSQL installation..."
    
    if ! command -v pg_config &> /dev/null; then
        error "pg_config not found. Please install PostgreSQL development headers."
        echo ""
        echo "macOS: brew install postgresql"
        echo "Ubuntu/Debian: sudo apt-get install postgresql-server-dev-14"
        exit 1
    fi
    
    PG_VERSION=$(pg_config --version | awk '{print $2}')
    info "Found PostgreSQL version: $PG_VERSION"
}

# Check if required build tools are available
check_build_tools() {
    info "Checking build tools..."
    
    if ! command -v make &> /dev/null; then
        error "make not found. Please install GNU Make."
        exit 1
    fi
    
    if ! command -v gcc &> /dev/null && ! command -v clang &> /dev/null; then
        error "No C compiler found. Please install GCC or Clang."
        exit 1
    fi
    
    info "Build tools OK"
}

# Clean previous builds
clean_build() {
    info "Cleaning previous builds..."
    make clean 2>/dev/null || true
    info "Clean complete"
}

# Build the extension
build_extension() {
    info "Building pg_ttl_index extension..."
    
    if make; then
        info "Build successful!"
    else
        error "Build failed. Check errors above."
        exit 1
    fi
}

# Install the extension
install_extension() {
    info "Installing pg_ttl_index extension..."
    
    if sudo make install; then
        info "Installation successful!"
        info "Extension installed to: $(pg_config --sharedir)/extension"
        info "Library installed to: $(pg_config --pkglibdir)"
    else
        error "Installation failed. Make sure you have sudo privileges."
        exit 1
    fi
}

# Show next steps
show_next_steps() {
    echo ""
    info "==================================================================="
    info "           pg_ttl_index Setup Complete!                            "
    info "==================================================================="
    echo ""
    echo "Next steps:"
    echo ""
    echo "1. Add to postgresql.conf:"
    echo "   shared_preload_libraries = 'pg_ttl_index'"
    echo ""
    echo "2. Restart PostgreSQL:"
    echo "   macOS: brew services restart postgresql"
    echo "   Linux: sudo systemctl restart postgresql"
    echo ""
    echo "3. Connect to your database:"
    echo "   psql -d your_database"
    echo ""
    echo "4. Create the extension:"
    echo "   CREATE EXTENSION pg_ttl_index;"
    echo "   SELECT ttl_start_worker();"
    echo ""
    echo "5. Run tests:"
    echo "   psql -d test_db -f test/test_ttl.sql"
    echo ""
    echo "Documentation:"
    echo "  - User Guide:      README.md"
    echo "  - Developer Guide: QUICKSTART.md"
    echo "  - Contributing:    CONTRIBUTING.md"
    echo ""
    info "==================================================================="
}

# Main execution
main() {
    echo ""
    info "pg_ttl_index Development Environment Setup"
    info "==========================================="
    echo ""
    
    check_postgresql
    check_build_tools
    clean_build
    build_extension
    
    # Ask if user wants to install
    echo ""
    read -p "Install extension? (requires sudo) [y/N] " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_extension
    else
        info "Skipping installation. You can install later with: sudo make install"
    fi
    
    show_next_steps
}

# Run main function
main
