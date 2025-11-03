#!/usr/bin/env bats

# Load test helpers
load test_helper

# Test setup - runs before each test
setup() {
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR
    
    # Simple test CSV file
    TEST_CSV="$TEST_TEMP_DIR/test.csv"
    cat > "$TEST_CSV" << EOF
project1,exp1,run1,,tests/source/test_data,data,dryrun
project2,,,analysis1,tests/source/scripts,results,copy
EOF
    export TEST_CSV
    
    # Copy script for testing
    TEST_SCRIPT="$TEST_TEMP_DIR/psync_test.sh"
    cp "$BATS_TEST_DIRNAME/../psync.sh" "$TEST_SCRIPT"
    export TEST_SCRIPT
}

# Test teardown - runs after each test
teardown() {
    [[ -n "$TEST_TEMP_DIR" && -d "$TEST_TEMP_DIR" ]] && rm -rf "$TEST_TEMP_DIR"
}

# Basic script structure tests
@test "script has valid structure" {
    grep -q "#!/bin/bash" "$BATS_TEST_DIRNAME/../psync.sh"
    grep -q "Core processing script" "$BATS_TEST_DIRNAME/../psync.sh"
}

@test "usage function works" {
    source "$TEST_SCRIPT"
    run usage
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Core Processing Script" ]]
}

# Core function tests
@test "log function formats messages correctly" {
    source "$TEST_SCRIPT"
    run log "test message"
    [ "$status" -eq 0 ]
    [[ "$output" =~ \[.*\]\ test\ message ]]
}

@test "build_path creates correct paths" {
    source "$TEST_SCRIPT"
    
    # Test with all fields
    project="proj1" experiment="exp1" run="run1" analysis="analysis1"
    run build_path
    [ "$output" = "proj1/exp1/run1/analysis1" ]
    
    # Test with empty fields
    project="proj1" experiment="" run="run1" analysis=""
    run build_path
    [ "$output" = "proj1/run1" ]
    
    # Test single component
    project="proj1" experiment="" run="" analysis=""
    run build_path
    [ "$output" = "proj1" ]
}

@test "get_rsync_options returns correct values" {
    source "$TEST_SCRIPT"
    
    run get_rsync_options "dryrun"
    [ "$output" = "--dry-run" ]
    
    run get_rsync_options "copy"
    [ "$output" = "" ]
    
    run get_rsync_options "move"
    [ "$output" = "--remove-source-files" ]
    
    run get_rsync_options "skip"
    [ "$output" = "SKIP" ]
    
    run get_rsync_options "invalid"
    [ "$status" -eq 1 ]
}

# Processing mode tests
@test "script handles standalone mode" {
    unset SLURM_ARRAY_TASK_ID
    
    # Mock rsync to avoid file operations
    function rsync() { echo "MOCK: rsync $*"; return 0; }
    export -f rsync
    
    run bash "$BATS_TEST_DIRNAME/../psync.sh" "$TEST_CSV" 1 2>&1
    [[ "$output" =~ "Standalone mode: Processing entry 1" ]]
}

@test "script detects SLURM mode" {
    export SLURM_ARRAY_TASK_ID=1
    
    function rsync() { echo "MOCK: rsync $*"; return 0; }
    export -f rsync
    
    run bash "$BATS_TEST_DIRNAME/../psync.sh" "$TEST_CSV" 2>&1
    [[ "$output" =~ "SLURM task 1: Processing line 1" ]]
    
    unset SLURM_ARRAY_TASK_ID
}

@test "script requires CSV file argument" {
    run bash "$BATS_TEST_DIRNAME/../psync.sh"
    [ "$status" -eq 1 ]
}

# Operation tests with mocked commands
@test "perform_rsync handles all operation types" {
    source "$TEST_SCRIPT"
    
    # Mock external commands
    function rsync() { echo "RSYNC: $*"; return 0; }
    function tar() { echo "TAR: $*"; return 0; }
    export -f rsync tar
    
    local test_dest="$TEST_TEMP_DIR/dest"
    
    # Test SKIP
    run perform_rsync "/src" "$test_dest" "SKIP"
    [[ "$output" =~ "SKIP: Skipping entry" ]]
    
    # Test PERMIT
    mkdir -p "$test_dest"
    run perform_rsync "/src" "$test_dest" "PERMIT"
    [[ "$output" =~ "PERMIT: Setting permissions" ]]
    
    # Test ARCHIVE
    run perform_rsync "/src" "$test_dest" "ARCHIVE"
    [[ "$output" =~ "ARCHIVE: Creating tar.gz" ]]
    
    # Test standard operations
    run perform_rsync "/src" "$test_dest" ""
    [[ "$output" =~ "RSYNC: -av --progress" ]]
    
    run perform_rsync "/src" "$test_dest" "--dry-run"
    [[ "$output" =~ "RSYNC: -av --progress --dry-run" ]]
}

# Validation tests
@test "script has validation logic" {
    grep -q "Missing required fields" "$BATS_TEST_DIRNAME/../psync.sh"
    grep -q "validate_csv_line" "$BATS_TEST_DIRNAME/../psync.sh"
}
