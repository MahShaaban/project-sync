#!/bin/bash

# Project Sync Tool Installer
# Installs the rsync project sync tool with all dependencies

set -euo pipefail

# Configuration
readonly TOOL_NAME="psync"
readonly VERSION="0.1"
readonly REPO_URL="https://github.com/username/project-sync"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

print_header() {
    echo
    print_status $BLUE "=== Project Sync Tool Installer v${VERSION} ==="
    echo
}

# Check system requirements
check_requirements() {
    print_status $YELLOW "Checking system requirements..."
    
    # Check for required commands
    local missing_deps=()
    
    for cmd in bash rsync tar chmod mkdir; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_status $RED "ERROR: Missing required dependencies:"
        printf '%s\n' "${missing_deps[@]}"
        exit 1
    fi
    
    print_status $GREEN "✓ All requirements satisfied"
}

# Determine installation directory
get_install_dir() {
    local install_type="${1:-user}"
    
    case "$install_type" in
        "system"|"global")
            echo "/usr/local/bin"
            ;;
        "user"|"local")
            echo "$HOME/.local/bin"
            ;;
        "current"|"here")
            echo "$PWD/bin"
            ;;
        *)
            echo "$1"  # Custom path
            ;;
    esac
}

# Install the tool
install_tool() {
    local install_dir="$1"
    local create_symlinks="${2:-true}"
    
    print_status $YELLOW "Installing to: $install_dir"
    
    # Create installation directory
    mkdir -p "$install_dir"
    
    # Copy main script
    cp rsync.sh "$install_dir/project-sync"
    chmod +x "$install_dir/project-sync"
    
    # Create wrapper script for easier usage
    cat > "$install_dir/psync" << 'EOF'
#!/bin/bash
# Project Sync Tool Wrapper
exec "$(dirname "$0")/project-sync" "$@"
EOF
    chmod +x "$install_dir/psync"
    
    # Create config directory
    local config_dir="$HOME/.config/project-sync"
    mkdir -p "$config_dir"
    
    # Install example templates
    if [[ ! -f "$config_dir/template.csv" ]]; then
        cat > "$config_dir/template.csv" << 'EOF'
# Project Sync Template
# Format: project,experiment,run,analysis,source,destination,option
project_name,exp_001,run_001,analysis_type,/source/path,dest_folder,copy
project_name,exp_002,,quality_check,/qc/path,qc_results,dryrun
backup_project,,,archive_old,/old/data,archived,archive
maintenance,,,permissions,/shared/workspace,workspace,permit
EOF
    fi
    
    # Create default config
    if [[ ! -f "$config_dir/config.sh" ]]; then
        cat > "$config_dir/config.sh" << 'EOF'
#!/bin/bash
# Project Sync Configuration

# Default SLURM settings
export PSYNC_DEFAULT_PARTITION="compute"
export PSYNC_DEFAULT_CPUS="1"
export PSYNC_DEFAULT_MEMORY="4G"
export PSYNC_LOG_DIR="$HOME/logs"

# Default paths
export PSYNC_CONFIG_DIR="$HOME/.config/project-sync"
export PSYNC_TEMPLATE_CSV="$PSYNC_CONFIG_DIR/template.csv"
EOF
    fi
    
    print_status $GREEN "✓ Tool installed successfully"
    
    # Add to PATH instructions
    if [[ "$install_dir" == "$HOME/.local/bin" ]]; then
        print_status $YELLOW "Add to your ~/.bashrc or ~/.profile:"
        echo "export PATH=\"\$HOME/.local/bin:\$PATH\""
    elif [[ "$install_dir" != "/usr/local/bin" ]]; then
        print_status $YELLOW "Add to your PATH:"
        echo "export PATH=\"$install_dir:\$PATH\""
    fi
}

# Install tests
install_tests() {
    local install_dir="$1"
    local test_dir="$install_dir/../share/project-sync/tests"
    
    print_status $YELLOW "Installing test suite..."
    
    mkdir -p "$test_dir"
    cp -r tests/ "$test_dir/"
    cp install_bats.sh run_tests.sh "$test_dir/"
    
    # Create test runner script
    cat > "$install_dir/psync-test" << EOF
#!/bin/bash
# Project Sync Test Runner
TEST_DIR="$test_dir"
cd "\$TEST_DIR"
exec ./run_tests.sh "\$@"
EOF
    chmod +x "$install_dir/psync-test"
    
    print_status $GREEN "✓ Test suite installed"
}

# Create uninstaller
create_uninstaller() {
    local install_dir="$1"
    
    cat > "$install_dir/psync-uninstall" << EOF
#!/bin/bash
# Project Sync Uninstaller

echo "Uninstalling Project Sync Tool..."

# Remove binaries
rm -f "$install_dir/project-sync"
rm -f "$install_dir/psync"
rm -f "$install_dir/psync-test"
rm -f "$install_dir/psync-uninstall"

# Remove shared files
rm -rf "$install_dir/../share/project-sync"

echo "Project Sync Tool uninstalled."
echo "Config files remain in ~/.config/project-sync"
echo "Remove manually if desired: rm -rf ~/.config/project-sync"
EOF
    chmod +x "$install_dir/psync-uninstall"
}

# Usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS] [INSTALL_TYPE]

Install Types:
  system     Install system-wide (/usr/local/bin) - requires sudo
  user       Install for current user (~/.local/bin) [default]
  current    Install in current directory (./bin)
  /path/to   Install to custom directory

Options:
  --with-tests    Install test suite
  --help         Show this help
  --version      Show version

Examples:
  $0                    # Install for user
  $0 system             # Install system-wide
  $0 /opt/tools         # Install to custom path
  $0 --with-tests user  # Install with test suite
EOF
}

# Main installation function
main() {
    local install_tests=false
    local install_type="user"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --with-tests)
                install_tests=true
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            --version)
                echo "Project Sync Tool Installer v${VERSION}"
                exit 0
                ;;
            --*)
                print_status $RED "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                install_type="$1"
                shift
                ;;
        esac
    done
    
    print_header
    
    # Check if we're in the right directory
    if [[ ! -f "rsync.sh" ]]; then
        print_status $RED "ERROR: rsync.sh not found in current directory"
        print_status $YELLOW "Please run this installer from the project-sync directory"
        exit 1
    fi
    
    check_requirements
    
    local install_dir
    install_dir=$(get_install_dir "$install_type")
    
    # Check for sudo requirement
    if [[ "$install_type" == "system" && $EUID -ne 0 ]]; then
        print_status $YELLOW "System installation requires sudo privileges"
        exec sudo "$0" "$@"
    fi
    
    install_tool "$install_dir"
    
    if [[ "$install_tests" == true ]]; then
        install_tests "$install_dir"
    fi
    
    create_uninstaller "$install_dir"
    
    print_status $GREEN "Installation complete!"
    echo
    print_status $BLUE "Quick start:"
    echo "  psync --help                    # Show help"
    echo "  psync ~/.config/project-sync/template.csv 1  # Run template"
    echo "  psync-test                      # Run tests (if installed)"
    echo
}

# Run main function
main "$@"
