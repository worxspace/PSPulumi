# See here for image contents: https://github.com/microsoft/vscode-dev-containers/tree/v0.234.0/containers/alpine/.devcontainer/base.Dockerfile

# [Choice] Alpine version: 3.14, 3.13, 3.12, 3.11
ARG VARIANT="3.15"
FROM mcr.microsoft.com/vscode/devcontainers/base:0-alpine-${VARIANT}

# Install pwsh
RUN apk add --no-cache \
    ca-certificates \
    less \
    ncurses-terminfo-base \
    krb5-libs \
    libgcc \
    libintl \
    libssl1.1 \
    libstdc++ \
    tzdata \
    userspace-rcu \
    zlib \
    icu-libs \
    curl \
    git

RUN apk -X https://dl-cdn.alpinelinux.org/alpine/edge/main add --no-cache \
    lttng-ust

# Download the powershell '.tar.gz' archive
RUN curl -L https://github.com/PowerShell/PowerShell/releases/download/v7.2.4/powershell-7.2.4-linux-alpine-x64.tar.gz -o /tmp/powershell.tar.gz

# Create the target folder where powershell will be placed
RUN mkdir -p /opt/microsoft/powershell/7

# Expand powershell to the target folder
RUN tar zxf /tmp/powershell.tar.gz -C /opt/microsoft/powershell/7

# Set execute permissions
RUN chmod +x /opt/microsoft/powershell/7/pwsh

# Create the symbolic link that points to pwsh
RUN ln -s /opt/microsoft/powershell/7/pwsh /usr/bin/pwsh

# Download the pulumi '.tar.gz' archive
RUN curl -fsSL https://get.pulumi.com/releases/sdk/pulumi-v3.33.2-linux-x64.tar.gz  -o /tmp/pulumi.tar.gz

# Create the target folder where pulumi will be placed
RUN mkdir -p /opt/pulumi

# Expand pulumi to the target folder
RUN tar zxf /tmp/pulumi.tar.gz -C /opt

# Set execute permissions
RUN chmod +x /opt/pulumi/pulumi

# Create the symbolic link that points to pulumi
RUN ln -s /opt/pulumi/pulumi /usr/bin/pulumi