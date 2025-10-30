#!/bin/bash

# Package distribution script for Project Sync Tool
# Creates various distribution formats

set -euo pipefail

readonly TOOL_NAME="psync"
readonly VERSION="0.1"
readonly BUILD_DIR="build"
readonly DIST_DIR="dist"

# Create build directory
setup_build() {
    echo "Setting up build environment..."
    rm -rf "$BUILD_DIR" "$DIST_DIR"
    mkdir -p "$BUILD_DIR" "$DIST_DIR"
}

# Create source tarball
create_tarball() {
    echo "Creating source tarball..."
    local tarball_dir="$BUILD_DIR/${TOOL_NAME}-${VERSION}"
    
    mkdir -p "$tarball_dir"
    
    # Copy source files
    cp psync.sh install.sh Makefile README.md "$tarball_dir/"
    cp -r tests/ "$tarball_dir/"
    cp test.sh "$tarball_dir/"
    cp Dockerfile "$tarball_dir/"
    
    # Create tarball
    cd "$BUILD_DIR"
    tar -czf "../$DIST_DIR/${TOOL_NAME}-${VERSION}.tar.gz" "${TOOL_NAME}-${VERSION}/"
    cd ..
    
    echo "✓ Created $DIST_DIR/${TOOL_NAME}-${VERSION}.tar.gz"
}

# Create standalone installer
create_standalone_installer() {
    echo "Creating standalone installer..."
    local installer="$DIST_DIR/${TOOL_NAME}-installer.sh"
    
    # Create self-extracting installer
    cat > "$installer" << 'EOF'
#!/bin/bash
# Project Sync Tool - Standalone Installer
# This is a self-extracting installer

set -euo pipefail

TOOL_NAME="project-sync"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

echo "Project Sync Tool - Standalone Installer"
echo "Extracting files..."

# Extract embedded tarball (added at end of this script)
sed '1,/^__TARBALL_FOLLOWS__$/d' "$0" | tar -xz -C "$TEMP_DIR"

echo "Starting installation..."
cd "$TEMP_DIR/$TOOL_NAME"*

# Run the installer
exec ./install.sh "$@"

__TARBALL_FOLLOWS__
EOF

    # Append the tarball to the installer
    cat "$DIST_DIR/${TOOL_NAME}-${VERSION}.tar.gz" >> "$installer"
    chmod +x "$installer"
    
    echo "✓ Created $installer"
}

# Create Docker container
create_container() {
    echo "Creating Docker container..."
    
    # Copy necessary files to build directory
    cp psync.sh README.md "$BUILD_DIR/"
    cp -r tests/ "$BUILD_DIR/"
    cp test.sh "$BUILD_DIR/"
    cp Dockerfile "$BUILD_DIR/"
    
    echo "✓ Docker files prepared in $BUILD_DIR/"
    echo "Build with: docker build -t project-sync:$VERSION $BUILD_DIR/"
}

# Main function
main() {
    local target="${1:-all}"
    
    case "$target" in
        "tarball")
            setup_build
            create_tarball
            ;;
        "installer")
            setup_build
            create_tarball
            create_standalone_installer
            ;;
        "docker")
            setup_build
            create_container
            ;;
        "all")
            setup_build
            create_tarball
            create_standalone_installer
            create_container
            ;;
        *)
            echo "Usage: $0 [tarball|installer|docker|all]"
            exit 1
            ;;
    esac
    
    echo
    echo "Build complete! Check the $DIST_DIR/ directory for packages."
}

main "$@"
