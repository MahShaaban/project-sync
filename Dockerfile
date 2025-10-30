FROM ubuntu:22.04

# Install dependencies
RUN apt-get update && apt-get install -y \
    bash \
    rsync \
    tar \
    gzip \
    git \
    make \
    && rm -rf /var/lib/apt/lists/*

# Clone the latest version from GitHub
RUN git clone https://github.com/MahShaaban/project-sync.git /tmp/psync

# Install psync using the provided installer
WORKDIR /tmp/psync
RUN make install

# Clean up
RUN rm -rf /tmp/psync

# Create app directory for user data
WORKDIR /app

# Create default config directory
RUN mkdir -p /root/.config/psync

# Set entrypoint to the installed psync command
ENTRYPOINT ["/usr/local/bin/psync"]
CMD ["--help"]
