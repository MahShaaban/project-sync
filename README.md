# Project Sync Tool

An rsync-based file synchronization script designed to work both in a cluster
arrays and as a standalone tool. The script processes CSV-defined sync jobs with configurable sync operations.

## Overview

The `psync` command provides a unified interface for file synchronization operations. It uses `psync.sh` as the core processing engine and reads job definitions from CSV files.

## Features

- **Dual Mode Operation**: Works in SLURM array jobs or standalone mode
- **CSV-Driven Configuration**: Job definitions stored in easy-to-edit CSV format
- **Multi-line Processing**: Process all CSV lines automatically or selectively
- **Multiple Sync Options**: Support for dry-run, copy, move, archive, permit, and skip operations

## Processing Modes

The script supports multiple processing modes for different use cases:

### Standalone Mode

```bash
# Process specific line (default: line 1)
psync tests/data.csv
psync --line 3 tests/data.csv

# Process all lines
psync --all tests/data.csv
```

### Cluster array

```bash
# Submit SLURM job using configuration from psync.conf
psync --executor sbatch data.csv
```

### Interactive Mode
```bash
# Guided setup for single operations
psync interactive
```

### Helper Commands

#### Create and Validate CSV Files
```bash
# Create new project template
psync new genomics_project

# Validate CSV file
psync check genomics_project.csv

# Preview directory structure
psync preview genomics_project.csv
```

## CSV Format

The input CSV file should contain the following columns:

| Column | Description | Required | Example |
|--------|-------------|----------|---------|
| project | Project name | No | `genomics_study` |
| experiment | Experiment identifier | No | `exp_001` |
| run | Run identifier | No | `run_042` |
| analysis | Analysis type | No | `variant_calling` |
| source | Source path | **Yes** | `/data/raw/samples/` |
| destination | Destination folder name | **Yes** | `processed_data` |
| option | Sync operation type | **Yes** | `copy` |

### CSV Example
```csv
project1,exp1,run1,,tests/source/test_data,data,dryrun
project1,exp1,run2,,tests/source/test_data,,copy
project2,,,analysis1,tests/source/scripts,data,move
```

### Sync Options

| Option | Description | Implementation |
|--------|-------------|----------------|
| `dryrun` | Preview what would be synced | `rsync --dry-run` |
| `copy` | Standard copy operation | `rsync -av` |
| `move` | Copy files and delete source | `rsync --remove-source-files` |
| `archive` | Create tar.gz archive of source | `tar -czf` with timestamp |
| `permit` | Set directory permissions to 755 | `chmod 755` on destination |
| `skip` | Skip entry completely | No operation performed |

#### Detailed Option Descriptions

**dryrun**: Performs a dry run using rsync to show what files would be transferred without actually copying them. Useful for validation and testing.

**copy**: Standard file copying using rsync with archive mode (`-a`) and verbose output (`-v`). Preserves file attributes, permissions, and timestamps.

**move**: Copies files using rsync and then removes the source files. Equivalent to a move operation but with rsync's robust transfer capabilities.

**archive**: Creates a compressed tar.gz archive of the source directory/files. The archive is named with a timestamp: `<source_name>_YYYYMMDD_HHMMSS.tar.gz`.

**permit**: Sets permissions to 755 (rwxr-xr-x) on the destination directory. Useful for ensuring proper access permissions on shared directories. Only works on directories.

**skip**: Completely skips the entry - no operation is performed. Useful for temporarily disabling entries in your CSV without removing them.

## Directory Structure

The script builds destination paths hierarchically from non-empty CSV fields:

```
# A run
<script_directory>/<project>/<experiment>/<run>/<destination>/

# An analysis
<script_directory>/<project>/<analysis>/<destination>/
```

## Installation & Setup

### Installation Using Makefile

#### 1. User Installation (Recommended)
```bash
# Clone repository
git clone https://github.com/MahShaaban/project-sync.git
cd project-sync

# Install for current user (~/.local/bin)
make install-user
```

#### 2. System-wide Installation
```bash
# Clone repository
git clone https://github.com/MahShaaban/project-sync.git
cd project-sync

# Install system-wide (requires sudo)
sudo make install
```

### Additional Makefile Targets

```bash
# Show all available targets
make help

# Run tests
make test

# Clean build artifacts
make clean

# Uninstall
make uninstall-user        # Remove user installation
sudo make uninstall        # Remove system installation

# Package for distribution
make package-tarball       # Create tarball
```

## Testing

This project includes comprehensive tests using the **bats-core** testing framework.

### Run Tests Using Makefile

```bash
# Install test framework only
make install-bats

# Run all tests (installs bats-core if needed)
make test
```

## Configuration

### SLURM Configuration
SLURM settings are configured via the external `psync.conf` file:

```properties
job-name=psync-projects
output=logs/psync-projects_%A_%a.out
error=logs/psync-projects_%A_%a.err
partition=compute
cpus-per-task=1
array=1-1000
```

To customize SLURM settings, edit `psync.conf` before using `psync --executor sbatch`.

## Requirements

- **Bash**: Version 4.0 or higher
- **rsync**: Standard rsync utility
- **SLURM**: Optional, for cluster execution

## Contributing

1. Fork the repository: https://github.com/MahShaaban/project-sync
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass: `make test`
5. Submit a pull request

## License

This project is available under the MIT License. See LICENSE file for details.
