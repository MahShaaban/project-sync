#!/bin/bash

# Core processing script for project-sync
# Main user interface: psync command
# Direct usage: bash psync.sh <csv_file> [line_number|--all]

# set -e  # Disabled for now - some piped commands return non-zero

# Script configuration
readonly SCRIPT_DIR="$PWD"
readonly VERSION="0.1"
readonly SCRIPT_NAME="psync"

# Usage information (minimal - main interface is via 'psync' command)
usage() {
    cat << EOF
$SCRIPT_NAME v$VERSION - Core Processing Script

This is the core processing script. Use the 'psync' command for the main interface.

Basic usage:
  bash psync.sh <csv_file> [line_number|--all]

For full functionality, use: psync --help
EOF
}

# Log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Count lines in CSV file (excluding empty lines)
count_csv_lines() {
    local csv_file="$1"
    
    if [[ ! -f "$csv_file" ]]; then
        echo "0"
        return
    fi
    
    # Count non-empty lines
    grep -c '^[^[:space:]]*,' "$csv_file" 2>/dev/null || echo "0"
}

# Parse CSV line for this array task
parse_csv_line() {
    local csv_file="${1:-$CSV_FILE}"
    local task_id="${2:-$TASK_ID}"
    local line_number="$task_id"  # In SLURM, task_id and line_number are the same (1-based)
    local line
    
    line=$(sed -n "${line_number}p" "$csv_file" 2>/dev/null) || {
        log "No data for task $task_id, exiting"
        exit 0
    }
    
    [[ -z "$line" ]] && {
        log "Empty line for task $task_id, exiting"
        exit 0
    }
    
    # Use global variables (no local declaration)
    IFS=',' read -r project experiment run analysis source destination option <<< "$line"
    
    # Basic field count validation only - detailed validation happens later
    # Just check if we have the minimum expected number of fields
}

# Validate CSV line for processing (returns 0 for valid, 1 for skip with warning)
validate_csv_line() {
    local line_num="$1"
    
    # Rule 1: Project must always be provided (cannot be empty) - WARN and skip
    if [[ -z "$project" ]]; then
        echo "WARNING line $line_num: Project field is required and cannot be empty - skipping line"
        return 1
    fi
    
    # Rule 2: If run is provided, experiment must also be provided - WARN and skip
    if [[ -n "$run" && -z "$experiment" ]]; then
        echo "WARNING line $line_num: Run field provided but experiment field is missing (run requires experiment) - skipping line"
        return 1
    fi
    
    # Rule 3: Analysis cannot be provided when run or experiment are present - WARN and skip
    if [[ -n "$analysis" && ( -n "$run" || -n "$experiment" ) ]]; then
        echo "WARNING line $line_num: Analysis field cannot be provided when run or experiment fields are present - skipping line"
        return 1
    fi
    
    # Rule 4: Source must be provided - WARN and skip if missing
    if [[ -z "$source" ]]; then
        echo "WARNING line $line_num: No source provided - skipping line"
        return 1
    fi
    
    # Rule 5: Option must be provided - WARN and skip if missing
    if [[ -z "$option" ]]; then
        echo "WARNING line $line_num: No operation option provided - skipping line"
        return 1
    fi
    
    return 0
}

# Build destination path from non-empty fields
build_path() {
    local path=""
    local fields=("${project:-}" "${experiment:-}" "${run:-}" "${analysis:-}")
    
    for field in "${fields[@]}"; do
        [[ -n "$field" ]] && path="${path:+$path/}$field"
    done
    
    echo "$path"
}

# Get rsync options based on operation type
get_rsync_options() {
    case "$1" in
        dryrun)  echo "--dry-run" ;;
        copy)    echo "" ;;
        move)    echo "--remove-source-files" ;;
        archive) echo "ARCHIVE" ;;  # Special flag for archive operation
        permit)  echo "PERMIT" ;;   # Special flag for permission operation
        skip)    echo "SKIP" ;;     # Special flag to skip entry
        *)       log "ERROR: Invalid option '$1'"; exit 1 ;;
    esac
}

# Perform rsync operation
perform_rsync() {
    local src="$1"
    local dest="$2"
    local opts="$3"
    
    # Create destination directory (only if it doesn't exist and not a file)
    if [[ ! -e "$dest" ]]; then
        mkdir -p "$dest"
    elif [[ ! -d "$dest" && "$opts" != "PERMIT" ]]; then
        # If destination exists but is not a directory, and we're not doing PERMIT operation
        mkdir -p "$dest"
    fi
    
    log "Syncing: $src -> $dest"
    log "Options: $opts"
    
    # Handle special operations
    case "$opts" in
        "SKIP")
            log "SKIP: Skipping entry completely"
            return 0
            ;;
        "PERMIT")
            log "PERMIT: Setting permissions to 755 on $dest"
            if [[ -d "$dest" ]]; then
                chmod 755 "$dest"
                log "Permissions set to 755 for directory: $dest"
            else
                log "WARNING: $dest is not a directory, cannot set permissions"
            fi
            return 0
            ;;
        "ARCHIVE")
            log "ARCHIVE: Creating tar.gz archive of $src"
            local archive_name="$(basename "$src")_$(date +%Y%m%d_%H%M%S).tar.gz"
            local archive_path="$dest/$archive_name"
            
            # Create tar.gz archive
            if tar -czf "$archive_path" -C "$(dirname "$src")" "$(basename "$src")"; then
                log "Archive created successfully: $archive_path"
            else
                log "ERROR: Failed to create archive: $archive_path"
                exit 1
            fi
            return 0
            ;;
        *)
            # Standard rsync operations
            if [[ -n "$opts" ]]; then
                rsync -av --progress $opts "$src" "$dest"
            else
                rsync -av --progress "$src" "$dest"
            fi
            ;;
    esac
}

# Process a single CSV line
process_single_line() {
    local csv_file="$1"
    local line_number="$2"
    
    log "Processing line $line_number"
    
    # Parse CSV input (use line_number as task_id since they're 1-based)
    parse_csv_line "$csv_file" "$line_number"
    
    # Validate the parsed line
    if ! validate_csv_line "$line_number"; then
        log "Completed processing line $line_number"
        return 0
    fi
    
    # Build paths and options
    local file_path
    file_path=$(build_path)
    local full_dest="$SCRIPT_DIR/$file_path/$destination"
    local rsync_opts
    rsync_opts=$(get_rsync_options "$option")
    
    # Log configuration
    log "Project: $project, Experiment: $experiment, Run: $run, Analysis: $analysis"
    log "Constructed path: $file_path"
    log "Full destination: $full_dest"
    
    # Perform the sync
    perform_rsync "$source" "$full_dest" "$rsync_opts"
    
    log "Completed processing line $line_number"
}

# Helper Functions (formerly in psync-helper.sh)
# Create a new CSV template
psync_new() {
    local project_name="${1:-new_project}"
    local csv_file="${2:-${project_name}.csv}"
    
    cat > "$csv_file" << EOF
# $project_name sync configuration
# Format: project,experiment,run,analysis,source,destination,option
$project_name,exp_001,run_001,,/source/path,preprocessed,copy
$project_name,exp_001,run_002,,/source/path,qc_results,dryrun
$project_name,,,analysis,/processed/path,final_results,move
EOF
    
    echo "Created template: $csv_file"
    echo "Edit the file and run: psync $csv_file"
}

# Validate CSV file
psync_check() {
    local csv_file="$1"
    local skip_source_check=false
    
    # Parse optional flags
    if [[ "$csv_file" == "--skip-source-check" ]]; then
        skip_source_check=true
        csv_file="$2"
    elif [[ "$2" == "--skip-source-check" ]]; then
        skip_source_check=true
    fi
    
    if [[ ! -f "$csv_file" ]]; then
        echo "ERROR: File not found: $csv_file"
        return 1
    fi
    
    echo "Validating $csv_file..."
    local line_num=0
    
    while IFS=, read -r project experiment run analysis source destination option; do
        ((line_num++))
        
        # Skip comments and empty lines
        [[ "$project" =~ ^#.*$ ]] && continue
        [[ -z "$project$experiment$run$analysis$source$destination$option" ]] && continue
        
        # Check required fields
        if [[ -z "$source" || -z "$destination" || -z "$option" ]]; then
            echo "ERROR line $line_num: Missing required fields (source, destination, option)"
            ((errors++))
        fi
        
        # Validate project hierarchy rules
        # Rule 1: Project must always be provided (cannot be empty) - WARN and skip instead of error
        if [[ -z "$project" ]]; then
            echo "WARNING line $line_num: Project field is required and cannot be empty - skipping line"
            continue
        fi
        
        # Rule 2: If run is provided, experiment must also be provided - WARN and skip instead of error
        if [[ -n "$run" && -z "$experiment" ]]; then
            echo "WARNING line $line_num: Run field provided but experiment field is missing (run requires experiment) - skipping line"
            continue
        fi
        
        # Rule 3: Analysis cannot be provided when run or experiment are present - WARN and skip instead of error
        # Only allowed combinations: project+experiment+run OR project+analysis
        if [[ -n "$analysis" && ( -n "$run" || -n "$experiment" ) ]]; then
            echo "WARNING line $line_num: Analysis field cannot be provided when run or experiment fields are present - skipping line"
            continue
        fi
        
        # Rule 4: Source must be provided - WARN and skip if missing
        if [[ -z "$source" ]]; then
            echo "WARNING line $line_num: No source provided - skipping line"
            continue
        fi
        
        # Check option validity
        case "$option" in
            dryrun|copy|move|archive|permit|skip) ;;
            *) 
                echo "ERROR line $line_num: Invalid option '$option'"
                ((errors++))
                ;;
        esac
        
        # Check source path exists (for copy/move operations) - optional
        if [[ "$skip_source_check" == false && "$option" =~ ^(copy|move|dryrun)$ && ! -e "$source" ]]; then
            echo "WARNING line $line_num: Source path does not exist: $source"
        fi
    done < "$csv_file"
    
    echo "✓ CSV file validation completed"
    echo "Found $((line_num)) lines processed"
}

# Show project structure that would be created
psync_preview() {
    local csv_file="$1"
    
    echo "Project structure preview for: $csv_file"
    echo "====================================="
    
    while IFS=, read -r project experiment run analysis source destination option; do
        # Skip comments and empty lines
        [[ "$project" =~ ^#.*$ ]] && continue
        [[ -z "$project$experiment$run$analysis$source$destination$option" ]] && continue
        
        # Build path
        local path=""
        for field in "$project" "$experiment" "$run" "$analysis"; do
            [[ -n "$field" ]] && path="${path:+$path/}$field"
        done
        
        echo "  $path/$destination/ ($option)"
    done < "$csv_file"
}

# Interactive mode
psync_interactive() {
    echo "=== Project Sync Interactive Mode ==="
    echo
    
    # Get project info
    read -p "Project name: " project
    read -p "Source directory: " source
    read -p "Destination name: " destination
    
    echo
    echo "Select operation:"
    echo "1) dryrun - Preview changes"
    echo "2) copy - Copy files"
    echo "3) move - Move files"
    echo "4) archive - Create archive"
    echo "5) permit - Set permissions"
    echo "6) skip - Skip (for testing)"
    
    read -p "Choice (1-6): " choice
    
    case "$choice" in
        1) option="dryrun" ;;
        2) option="copy" ;;
        3) option="move" ;;
        4) option="archive" ;;
        5) option="permit" ;;
        6) option="skip" ;;
        *) echo "Invalid choice"; return 1 ;;
    esac
    
    # Create temporary CSV
    local temp_csv=$(mktemp --suffix=.csv)
    echo "$project,,,,$source,$destination,$option" > "$temp_csv"
    
    echo
    echo "Running: $option operation"
    echo "Source: $source"
    echo "Destination: $project/$destination"
    echo
    
    # Call main function recursively with the temp CSV
    main "$temp_csv" 1
    rm "$temp_csv"
}

# Main execution
main() {
    # Handle helper commands first
    case "${1:-}" in
        new)
            echo "INFO: For better experience, use: psync new $2"
            shift
            psync_new "$@"
            exit 0
            ;;
        check|validate)
            echo "INFO: For better experience, use: psync check $2"
            shift
            psync_check "$@"
            exit 0
            ;;
        preview|show)
            echo "INFO: For better experience, use: psync preview $2"
            shift
            psync_preview "$@"
            exit 0
            ;;
        interactive|i)
            echo "INFO: For better experience, use: psync interactive"
            psync_interactive
            exit 0
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        --version|-v)
            echo "$SCRIPT_NAME v$VERSION"
            exit 0
            ;;
    esac
    
    [[ $# -eq 0 ]] && { usage; exit 1; }
    
    # Script configuration
    readonly CSV_FILE="${1:?CSV file required}"
    readonly PROCESS_MODE="${2:-1}"  # Can be line number or --all
    
    # Determine processing mode
    if [[ -n "${SLURM_ARRAY_TASK_ID:-}" ]]; then
        # Running in SLURM array job - process single line with graceful exit
        readonly TASK_ID="$SLURM_ARRAY_TASK_ID"
        readonly IS_SLURM=true
        local line_number=$((TASK_ID))
        
        # Count total lines only for logging
        local total_lines
        total_lines=$(count_csv_lines "$CSV_FILE")
        
        if [[ "$line_number" -gt "$total_lines" ]]; then
            log "SLURM task $line_number: No corresponding line in CSV (total: $total_lines), exiting gracefully"
            exit 0
        fi
        
        log "SLURM task $line_number: Processing line $line_number of $total_lines"
        process_single_line "$CSV_FILE" "$line_number"
        
    elif [[ "$PROCESS_MODE" == "--all" ]]; then
        # Standalone mode - process all lines
        local total_lines
        total_lines=$(count_csv_lines "$CSV_FILE")
        
        if [[ "$total_lines" -eq 0 ]]; then
            log "ERROR: No valid CSV lines found in $CSV_FILE"
            exit 1
        fi
        
        log "Standalone mode: Processing all $total_lines lines"
        
        for ((i=1; i<=total_lines; i++)); do
            log "=== Processing line $i of $total_lines ==="
            process_single_line "$CSV_FILE" "$i"
            log ""
        done
        
        log "All lines processed successfully"
        
    else
        # Standalone mode - process specific line
        local line_number="$PROCESS_MODE"
        
        # Count total lines for validation
        local total_lines
        total_lines=$(count_csv_lines "$CSV_FILE")
        
        if [[ "$total_lines" -eq 0 ]]; then
            log "ERROR: No valid CSV lines found in $CSV_FILE"
            exit 1
        fi
        
        # Validate line number
        if ! [[ "$line_number" =~ ^[0-9]+$ ]] || [[ "$line_number" -lt 1 ]] || [[ "$line_number" -gt "$total_lines" ]]; then
            log "ERROR: Invalid line number '$line_number'. Must be between 1 and $total_lines"
            exit 1
        fi
        
        log "Standalone mode: Processing line $line_number of $total_lines"
        process_single_line "$CSV_FILE" "$line_number"
    fi
}

# Run main function only if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi