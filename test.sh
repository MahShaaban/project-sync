#!/bin/bash

# Comprehensive Test Suite for psync (project-sync)
# Combines unit tests, integration tests, and Makefile tests

# Note: Using minimal error handling to allow graceful test failure handling
set +e  # Don't exit on error - we want to handle test failures gracefully

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

print_test() {
    local test_name="$1"
    echo
    print_status $BLUE "Testing: $test_name"
    echo "========================================"
}

# Test counter
TESTS_PASSED=0
TESTS_TOTAL=0

run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="${3:-0}"
    
    ((TESTS_TOTAL++))
    print_test "$test_name"
    
    # Capture the full command output and result
    local output
    local result
    output=$(eval "$test_command" 2>&1)
    result=$?
    
    if [[ $result -eq $expected_result ]]; then
        print_status $GREEN "✓ PASSED: $test_name"
        ((TESTS_PASSED++))
    else
        print_status $RED "✗ FAILED: $test_name (command failed)"
        echo "Command: $test_command"
        echo "Exit code: $result (expected: $expected_result)"
        echo "Output: $output"
    fi
}

# Setup function
setup_test_environment() {
    print_status $YELLOW "Setting up test environment..."
    
    # Ensure log directory exists
    mkdir -p logs
    
    # Backup any existing installation
    if [[ -f ~/.local/bin/project-sync ]]; then
        mv ~/.local/bin/project-sync ~/.local/bin/project-sync.backup || true
    fi
    if [[ -f ~/.local/bin/psync ]]; then
        mv ~/.local/bin/psync ~/.local/bin/psync.backup || true
    fi
    
    # Clean any previous builds
    make clean >/dev/null 2>&1 || true
    
    # Check if bats is installed
    if [ ! -f "bats-core/bin/bats" ]; then
        print_status $YELLOW "bats-core not found. Installing..."
        if make install-bats >/dev/null 2>&1; then
            print_status $GREEN "bats-core installed successfully"
        else
            print_status $RED "Error: Failed to install bats-core!"
            exit 1
        fi
    fi
}

# Cleanup function
cleanup_test_environment() {
    print_status $YELLOW "Cleaning up test environment..."
    
    # Remove test installation (ignore errors)
    rm -f ~/.local/bin/project-sync ~/.local/bin/psync 2>/dev/null || true
    rm -rf ~/.local/share/project-sync 2>/dev/null || true
    
    # Restore backup if it exists
    if [[ -f ~/.local/bin/project-sync.backup ]]; then
        mv ~/.local/bin/project-sync.backup ~/.local/bin/project-sync 2>/dev/null || true
    fi
    if [[ -f ~/.local/bin/psync.backup ]]; then
        mv ~/.local/bin/psync.backup ~/.local/bin/psync 2>/dev/null || true
    fi
    
    # Don't clean build artifacts during testing as it removes bats-core
    # make clean >/dev/null 2>&1 || true
}

# Unit and Integration Tests using bats
run_unit_tests() {
    print_status $GREEN "=== Running Unit & Integration Tests ==="
    echo
    
    # Create tests directory if it doesn't exist
    mkdir -p tests
    
    # Check if test files exist
    if [ ! -f "tests/test_psync.bats" ]; then
        print_status $RED "Error: Test files not found in tests/ directory"
        print_status $YELLOW "Please ensure tests/test_psync.bats exists"
        return 1
    fi
    
    # Run bats tests
    if ./bats-core/bin/bats tests/test_psync.bats; then
        print_status $GREEN "✓ Unit tests passed!"
        return 0
    else
        print_status $RED "✗ Unit tests failed!"
        return 1
    fi
}

# Makefile tests
test_help_target() {
    run_test "make help" "make help | grep -q 'Project Sync Tool'"
}

test_clean_target() {
    # Create some files to clean
    mkdir -p dist/
    touch test.log
    run_test "make clean" "make clean && [[ ! -d dist/ ]] && [[ ! -f test.log ]]"
}

test_user_install() {
    run_test "make install-user" "make install-user && [[ -f ~/.local/bin/psync.sh ]] && [[ -f ~/.local/bin/psync ]]"
}

test_installed_commands() {
    run_test "installed psync --version" "~/.local/bin/psync --version | grep -q 'v0.1'"
    run_test "installed psync --help" "~/.local/bin/psync --help | grep -q 'Usage:'"
}

test_config_creation() {
    run_test "config template created" "[[ -f ~/.config/project-sync/template.csv ]]"
}

test_dist_target() {
    run_test "make dist" "make dist && [[ -f dist/psync-0.1.tar.gz ]]"
}

test_uninstall() {
    run_test "make uninstall-user" "make uninstall-user && [[ ! -f ~/.local/bin/psync.sh ]] && [[ ! -f ~/.local/bin/psync ]]"
}

test_reinstall() {
    run_test "reinstall after uninstall" "make install-user && [[ -f ~/.local/bin/psync.sh ]] && ~/.local/bin/psync --version | grep -q 'v0.1'"
}

# Helper command tests
test_helper_commands() {
    print_status $GREEN "=== Testing Helper Commands ==="
    echo
    
    # Initialize local counters to avoid issues
    local local_passed=0
    local local_total=0
    
    # Test new command
    echo "Testing 'new' command..."
    if bash psync.sh new test_project_temp >/dev/null 2>&1 && [[ -f test_project_temp.csv ]]; then
        print_status $GREEN "✓ Helper command 'new' works"
        ((TESTS_PASSED++))
        ((local_passed++))
        rm -f test_project_temp.csv 2>/dev/null || true
    else
        print_status $RED "✗ Helper command 'new' failed"
    fi
    ((TESTS_TOTAL++))
    ((local_total++))
    
    # Test check command with data.csv
    echo "Testing 'check' command..."
    if [[ -f tests/data.csv ]]; then
        if bash psync.sh check tests/data.csv >/dev/null 2>&1; then
            print_status $GREEN "✓ Helper command 'check' works"
            ((TESTS_PASSED++))
            ((local_passed++))
        else
            print_status $RED "✗ Helper command 'check' failed"
        fi
    else
        print_status $YELLOW "Skipping check test (no test data)"
    fi
    ((TESTS_TOTAL++))
    ((local_total++))
    
    # Test preview command
    echo "Testing 'preview' command..."
    if [[ -f tests/data.csv ]]; then
        if bash psync.sh preview tests/data.csv >/dev/null 2>&1; then
            print_status $GREEN "✓ Helper command 'preview' works"
            ((TESTS_PASSED++))
            ((local_passed++))
        else
            print_status $RED "✗ Helper command 'preview' failed"
        fi
    else
        print_status $YELLOW "Skipping preview test (no test data)"
    fi
    ((TESTS_TOTAL++))
    ((local_total++))
    
    echo "Helper tests completed: $local_passed/$local_total passed"
    return 0  # Always return success to prevent early exit
}

# Main test execution
main() {
    print_status $BLUE "=== Comprehensive psync Test Suite ==="
    echo "Date: $(date)"
    echo "PWD: $PWD"
    echo
    
    setup_test_environment
    
    # Run unit tests first
    UNIT_TESTS_PASSED=false
    if run_unit_tests; then
        UNIT_TESTS_PASSED=true
    fi
    
    # Test helper commands
    echo "About to run helper tests..."
    test_helper_commands
    echo "Helper tests function completed"
    
    # Run Makefile tests
    print_status $GREEN "=== Running Makefile Tests ==="
    test_help_target
    test_clean_target
    test_user_install
    test_installed_commands
    test_config_creation
    test_uninstall
    test_reinstall
    test_dist_target
    
    cleanup_test_environment
    
    # Report results
    echo
    print_status $BLUE "=== Test Results Summary ==="
    
    if $UNIT_TESTS_PASSED; then
        print_status $GREEN "✓ Unit Tests: PASSED"
    else
        print_status $RED "✗ Unit Tests: FAILED"
    fi
    
    if [[ $TESTS_PASSED -eq $TESTS_TOTAL ]]; then
        print_status $GREEN "✓ Makefile/Helper Tests: PASSED ($TESTS_PASSED/$TESTS_TOTAL)"
        if $UNIT_TESTS_PASSED; then
            print_status $GREEN "✓ ALL TESTS PASSED"
            exit 0
        else
            print_status $RED "✗ UNIT TESTS FAILED"
            exit 1
        fi
    else
        print_status $RED "✗ Makefile/Helper Tests: FAILED ($TESTS_PASSED/$TESTS_TOTAL)"
        exit 1
    fi
}

# Handle cleanup on exit
# trap cleanup_test_environment EXIT  # Temporarily disabled - causing early exit issues

# Check arguments
case "${1:-all}" in
    "unit"|"bats")
        setup_test_environment
        run_unit_tests
        ;;
    "makefile"|"make")
        main # Will run only makefile tests
        ;;
    "helper"|"helpers")
        setup_test_environment
        test_helper_commands
        cleanup_test_environment
        echo
        print_status $BLUE "=== Helper Test Results ==="
        if [[ $TESTS_PASSED -eq $TESTS_TOTAL ]]; then
            print_status $GREEN "✓ ALL HELPER TESTS PASSED ($TESTS_PASSED/$TESTS_TOTAL)"
            exit 0
        else
            print_status $RED "✗ SOME HELPER TESTS FAILED ($TESTS_PASSED/$TESTS_TOTAL)"
            exit 1
        fi
        ;;
    "all"|*)
        main
        ;;
esac
