#!/bin/bash

# Core processing script for project-sync
# Main user interface: psync command
# Direct usage: bash psync.sh <input_file> [line_number|--all]

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
  bash psync.sh <input_file> [line_number|--all]

For full functionality, use: psync --help
EOF
}

# Log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Detect file type (CSV or JSON)
detect_file_type() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        echo "UNKNOWN"
        return 1
    fi
    
    # Check file extension first
    case "${file,,}" in
        *.json) echo "JSON"; return 0 ;;
        *.csv) echo "CSV"; return 0 ;;
    esac
    
    # If no clear extension, check content
    local first_line
    first_line=$(head -n1 "$file" 2>/dev/null)
    
    if [[ "$first_line" =~ ^\s*\{ ]]; then
        echo "JSON"
    elif [[ "$first_line" =~ ^[^,]*,[^,]* ]]; then
        echo "CSV"
    else
        echo "UNKNOWN"
        return 1
    fi
}

# Count entries in file (auto-detect format)
count_file_lines() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        echo "0"
        return
    fi
    
    local file_type
    file_type=$(detect_file_type "$file")
    
    case "$file_type" in
        "CSV") grep -c '^[^[:space:]]*,' "$file" 2>/dev/null || echo "0" ;;
        "JSON") 
            local count
            count=$(grep -o '^\s*{' "$file" 2>/dev/null | wc -l)
            if grep -q '"psync_tasks"' "$file" 2>/dev/null; then
                echo $((count - 1))
            else
                echo "$count"
            fi
            ;;
        *) echo "0" ;;
    esac
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
    IFS=',' read -r project experiment run analysis source destination option owner <<< "$line"
    
    # Basic field count validation only - detailed validation happens later
    # Just check if we have the minimum expected number of fields
}

# Parse JSON task for this array task
parse_json_line() {
    local json_file="${1:-$CSV_FILE}"
    local task_id="${2:-$TASK_ID}"
    
    # Find the psync_tasks array start
    local start_line task_json
    start_line=$(grep -n '"psync_tasks"' "$json_file" | cut -d: -f1)
    if [[ -z "$start_line" ]]; then
        log "No data for task $task_id, exiting"
        exit 0
    fi
    
    # Extract task using line-based approach
    task_json=$(sed -n "${start_line},\$p" "$json_file" | awk -v target="$((task_id - 1))" '
        /^\s*{/ && !/psync_tasks/ { if (count++ == target) start=1; next }
        start && /^\s*}/ { print; exit }
        start { print }
    ')
    
    if [[ -z "$task_json" ]]; then
        log "No data for task $task_id, exiting"
        exit 0
    fi
    
    # Extract fields using sed
    project=$(echo "$task_json" | sed -n 's/.*"project"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    experiment=$(echo "$task_json" | sed -n 's/.*"experiment"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    run=$(echo "$task_json" | sed -n 's/.*"run"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    analysis=$(echo "$task_json" | sed -n 's/.*"analysis"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    source=$(echo "$task_json" | sed -n 's/.*"source"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    destination=$(echo "$task_json" | sed -n 's/.*"destination"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    option=$(echo "$task_json" | sed -n 's/.*"option"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    owner=$(echo "$task_json" | sed -n 's/.*"owner"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
}

# Parse line from file (auto-detect format)
parse_file_line() {
    local file="${1:-$CSV_FILE}"
    local task_id="${2:-$TASK_ID}"
    local file_type
    file_type=$(detect_file_type "$file")
    
    case "$file_type" in
        "CSV") parse_csv_line "$file" "$task_id" ;;
        "JSON") parse_json_line "$file" "$task_id" ;;
        *) 
            log "ERROR: Unsupported file format for $file"
            exit 1
            ;;
    esac
}

# Common validation logic for both CSV and JSON
validate_task() {
    local line_num="$1"
    local label="${2:-line}"  # "line" for CSV, "task" for JSON
    
    # Check required fields (excluding source which has special handling)
    if [[ -z "$destination" || -z "$option" ]]; then
        echo "ERROR $label $line_num: Missing required fields (destination, option)"
        return 2  # Error
    fi
    
    # Source field special handling - warning but continue processing
    if [[ -z "$source" ]]; then
        echo "WARNING $label $line_num: Source field is empty - directory will be created but no data will be moved"
    fi
    
    # Owner field warning
    if [[ -z "$owner" ]]; then
        echo "WARNING $label $line_num: Owner field is empty - this may cause permission issues"
    fi
    
    # Project hierarchy validation
    if [[ -z "$project" ]]; then
        echo "WARNING $label $line_num: Project field is required and cannot be empty - skipping $label"
        return 1  # Skip
    fi
    
    if [[ -n "$run" && -z "$experiment" ]]; then
        echo "WARNING $label $line_num: Run field provided but experiment field is missing (run requires experiment) - skipping $label"
        return 1  # Skip
    fi
    
    if [[ -n "$analysis" && ( -n "$run" || -n "$experiment" ) ]]; then
        echo "WARNING $label $line_num: Analysis field cannot be provided when run or experiment fields are present - skipping $label"
        return 1  # Skip
    fi
    
    # Option validity
    case "$option" in
        dryrun|copy|move|archive|permit|skip) ;;
        *) 
            echo "ERROR $label $line_num: Invalid option '$option'"
            return 2  # Error
            ;;
    esac
    
    return 0  # Valid
}

# Validate CSV line for processing (returns 0 for valid, 1 for skip with warning)
validate_csv_line() {
    validate_task "$1" "line"
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
    
    # Handle empty source case
    if [[ -z "$src" ]]; then
        log "Source is empty - directory created but no data transferred: $dest"
        return 0
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
            if [[ -z "$src" ]]; then
                log "ARCHIVE: Cannot create archive - source is empty"
                return 0
            fi
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
            # Standard rsync operations - skip if source is empty
            if [[ -z "$src" ]]; then
                log "Standard operation skipped - source is empty"
                return 0
            fi
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
    local file="$1"
    local line_number="$2"
    
    log "Processing line $line_number"
    
    # Parse input (use line_number as task_id since they're 1-based)
    parse_file_line "$file" "$line_number"
    
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

# Create a new template file
psync_new() {
    local project_name="${1:-new_project}"
    local output_file="${2:-${project_name}.csv}"
    
    if [[ "${output_file,,}" == *.json ]]; then
        cat > "$output_file" << EOF
{
  "psync_tasks": [
    {
      "project": "$project_name",
      "experiment": "exp_001",
      "run": "run_001",
      "analysis": "",
      "source": "/source/path",
      "destination": "preprocessed",
      "option": "copy",
      "owner": "\$USER"
    },
    {
      "project": "$project_name",
      "experiment": "exp_001",
      "run": "run_002",
      "analysis": "",
      "source": "/source/path",
      "destination": "qc_results",
      "option": "dryrun",
      "owner": "\$USER"
    },
    {
      "project": "$project_name",
      "experiment": "",
      "run": "",
      "analysis": "analysis",
      "source": "/processed/path",
      "destination": "final_results",
      "option": "move",
      "owner": "\$USER"
    }
  ]
}
EOF
        echo "Created JSON template: $output_file"
    else
        cat > "$output_file" << EOF
# $project_name sync configuration
# Format: project,experiment,run,analysis,source,destination,option,owner
$project_name,exp_001,run_001,,/source/path,preprocessed,copy,\$USER
$project_name,exp_001,run_002,,/source/path,qc_results,dryrun,\$USER
$project_name,,,analysis,/processed/path,final_results,move,\$USER
EOF
        echo "Created CSV template: $output_file"
    fi
    
    echo "Edit the file and run: psync $output_file"
}

# Validate file
psync_check() {
    local input_file="$1"
    local skip_source_check=false
    
    # Parse optional flags
    if [[ "$input_file" == "--skip-source-check" ]]; then
        skip_source_check=true
        input_file="$2"
    elif [[ "$2" == "--skip-source-check" ]]; then
        skip_source_check=true
    fi
    
    if [[ ! -f "$input_file" ]]; then
        echo "ERROR: File not found: $input_file"
        return 1
    fi
    
    local file_type
    file_type=$(detect_file_type "$input_file")
    
    echo "Validating $input_file ($file_type format)..."
    local line_num=0 errors=0
    
    if [[ "$file_type" == "JSON" ]]; then
        local total_tasks
        total_tasks=$(count_file_lines "$input_file")
        
        for ((i=1; i<=total_tasks; i++)); do
            parse_json_line "$input_file" "$i"
            ((line_num++))
            
            local result
            validate_task "$line_num" "task"
            result=$?
            [[ $result -eq 2 ]] && ((errors++))
            
            # Check source path exists (optional)
            if [[ "$skip_source_check" == false && "$option" =~ ^(copy|move|dryrun)$ && ! -e "$source" ]]; then
                echo "WARNING task $line_num: Source path does not exist: $source"
            fi
        done
    else
        while IFS=, read -r project experiment run analysis source destination option owner; do
            ((line_num++))
            
            # Skip comments and empty lines
            [[ "$project" =~ ^#.*$ ]] && continue
            [[ -z "$project$experiment$run$analysis$source$destination$option" ]] && continue
            
            local result
            validate_task "$line_num" "line"
            result=$?
            [[ $result -eq 2 ]] && ((errors++))
            
            # Check source path exists (optional)
            if [[ "$skip_source_check" == false && "$option" =~ ^(copy|move|dryrun)$ && ! -e "$source" ]]; then
                echo "WARNING line $line_num: Source path does not exist: $source"
            fi
        done < "$input_file"
    fi
    
    echo "✓ $file_type file validation completed"
    echo "Found $line_num lines processed"
}

# Show project structure that would be created
psync_preview() {
    local input_file="$1"
    local file_type
    file_type=$(detect_file_type "$input_file")
    
    echo "Project structure preview for: $input_file ($file_type)"
    echo "====================================="
    
    if [[ "$file_type" == "JSON" ]]; then
        local total_tasks
        total_tasks=$(count_file_lines "$input_file")
        
        for ((i=1; i<=total_tasks; i++)); do
            parse_json_line "$input_file" "$i"
            
            # Build and display path
            local path=""
            for field in "$project" "$experiment" "$run" "$analysis"; do
                [[ -n "$field" ]] && path="${path:+$path/}$field"
            done
            echo "  $path/$destination/ ($option)"
        done
    else
        while IFS=, read -r project experiment run analysis source destination option; do
            # Skip comments and empty lines
            [[ "$project" =~ ^#.*$ ]] && continue
            [[ -z "$project$experiment$run$analysis$source$destination$option" ]] && continue
            
            # Build and display path
            local path=""
            for field in "$project" "$experiment" "$run" "$analysis"; do
                [[ -n "$field" ]] && path="${path:+$path/}$field"
            done
            echo "  $path/$destination/ ($option)"
        done < "$input_file"
    fi
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
    readonly CSV_FILE="${1:?Input file required}"
    readonly PROCESS_MODE="${2:-1}"
    
    # Determine processing mode
    if [[ -n "${SLURM_ARRAY_TASK_ID:-}" ]]; then
        # SLURM array job - process single line with graceful exit
        readonly TASK_ID="$SLURM_ARRAY_TASK_ID"
        readonly IS_SLURM=true
        local line_number=$((TASK_ID))
        local total_lines
        total_lines=$(count_file_lines "$CSV_FILE")
        
        if [[ "$line_number" -gt "$total_lines" ]]; then
            log "SLURM task $line_number: No corresponding line in file (total: $total_lines), exiting gracefully"
            exit 0
        fi
        
        log "SLURM task $line_number: Processing line $line_number of $total_lines"
        process_single_line "$CSV_FILE" "$line_number"
        
    elif [[ "$PROCESS_MODE" == "--all" ]]; then
        # Standalone mode - process all lines
        local total_lines
        total_lines=$(count_file_lines "$CSV_FILE")
        
        if [[ "$total_lines" -eq 0 ]]; then
            log "ERROR: No valid entries found in $CSV_FILE"
            exit 1
        fi
        
        log "Standalone mode: Processing all $total_lines entries"
        
        for ((i=1; i<=total_lines; i++)); do
            log "=== Processing entry $i of $total_lines ==="
            process_single_line "$CSV_FILE" "$i"
            log ""
        done
        
        log "All entries processed successfully"
        
    else
        # Standalone mode - process specific line
        local line_number="$PROCESS_MODE"
        local total_lines
        total_lines=$(count_file_lines "$CSV_FILE")
        
        if [[ "$total_lines" -eq 0 ]]; then
            log "ERROR: No valid entries found in $CSV_FILE"
            exit 1
        fi
        
        # Validate line number
        if ! [[ "$line_number" =~ ^[0-9]+$ ]] || [[ "$line_number" -lt 1 ]] || [[ "$line_number" -gt "$total_lines" ]]; then
            log "ERROR: Invalid line number '$line_number'. Must be between 1 and $total_lines"
            exit 1
        fi
        
        log "Standalone mode: Processing entry $line_number of $total_lines"
        process_single_line "$CSV_FILE" "$line_number"
    fi
}

# Run main function only if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi