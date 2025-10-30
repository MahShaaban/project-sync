#!/bin/bash

# Test helper functions for rsync.sh testing

# Set up test environment variables
setup_test_env() {
    export TEST_PROJECT="test_project"
    export TEST_EXPERIMENT="test_experiment"
    export TEST_RUN="test_run"
    export TEST_ANALYSIS="test_analysis"
}

# Create mock source directories with test content
create_test_sources() {
    local base_dir="$1"
    local num_sources="${2:-4}"
    
    for i in $(seq 1 "$num_sources"); do
        local source_dir="$base_dir/source$i"
        mkdir -p "$source_dir"
        echo "Test content for source $i" > "$source_dir/file$i.txt"
        echo "Additional file $i" > "$source_dir/extra$i.dat"
        
        # Create subdirectory with files
        mkdir -p "$source_dir/subdir"
        echo "Subdirectory content $i" > "$source_dir/subdir/sub$i.txt"
    done
}

# Verify that rsync was called with expected parameters
verify_rsync_call() {
    local expected_pattern="$1"
    local output="$2"
    
    if [[ "$output" =~ $expected_pattern ]]; then
        return 0
    else
        echo "Expected pattern '$expected_pattern' not found in output: $output" >&2
        return 1
    fi
}

# Create a CSV file with test data
create_test_csv() {
    local csv_file="$1"
    cat > "$csv_file" << EOF
project1,exp1,run1,analysis1,/tmp/source1,dest1,dryrun
project2,exp2,,analysis2,/tmp/source2,dest2,copy
project3,,,analysis3,/tmp/source3,dest3,move
project4,exp4,run4,,/tmp/source4,dest4,skip
empty_project,,,analysis5,/tmp/source5,dest5,archive
,,,,/tmp/source6,dest6,permit
EOF
}

# Mock rsync function for testing
mock_rsync() {
    echo "MOCK_RSYNC: $*"
    
    # Simulate different rsync behaviors based on arguments
    if [[ "$*" =~ --dry-run ]]; then
        echo "DRY RUN: Would sync files"
    elif [[ "$*" =~ --remove-source-files ]]; then
        echo "MOVE: Files would be moved"
    else
        echo "COPY: Files would be copied"
    fi
    
    return 0
}

# Clean up test environment
cleanup_test_env() {
    unset TEST_PROJECT TEST_EXPERIMENT TEST_RUN TEST_ANALYSIS
    unset SLURM_ARRAY_TASK_ID
    
    # Remove any temporary test directories
    rm -rf /tmp/test_* 2>/dev/null || true
    rm -rf /tmp/source* 2>/dev/null || true
}

# Verify directory structure was created
verify_directory_structure() {
    local base_dir="$1"
    local expected_path="$2"
    local full_path="$base_dir/$expected_path"
    
    if [[ -d "$full_path" ]]; then
        return 0
    else
        echo "Expected directory '$full_path' does not exist" >&2
        return 1
    fi
}

# Check if log output contains expected timestamp format
verify_log_format() {
    local log_output="$1"
    local message="$2"
    
    # Check for timestamp format [YYYY-MM-DD HH:MM:SS]
    if [[ "$log_output" =~ \[2[0-9]{3}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}\].*"$message" ]]; then
        return 0
    else
        echo "Log format verification failed for message: '$message'" >&2
        echo "Actual output: '$log_output'" >&2
        return 1
    fi
}
