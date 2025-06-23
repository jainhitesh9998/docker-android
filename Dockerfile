# Use a base image with Ubuntu and OpenJDK (Java 17)
FROM eclipse-temurin:17-jdk-focal

# Set environment variables for Android SDK
ENV ANDROID_SDK_ROOT="/usr/local/android-sdk"
ENV PATH="${PATH}:${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${ANDROID_SDK_ROOT}/platform-tools"

# Install necessary packages, including curl for yarn setup
RUN apt-get update && apt-get install -y \
    wget \
    unzip \
    git \
    nodejs \
    npm \
    build-essential \
    libstdc++6 \
    zlib1g \
    libncurses5 \
    libncurses6 \
    curl \
    gnupg \
    --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# Install Yarn
RUN curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - \
    && echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list \
    && apt-get update && apt-get install -y yarn \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Android SDK command-line tools
RUN mkdir -p ${ANDROID_SDK_ROOT}/cmdline-tools \
    && wget -q https://dl.google.com/android/repository/commandlinetools-linux-9477386_latest.zip -O /tmp/commandlinetools.zip \
    && unzip -q /tmp/commandlinetools.zip -d ${ANDROID_SDK_ROOT}/cmdline-tools \
    && rm /tmp/commandlinetools.zip \
    && mv ${ANDROID_SDK_ROOT}/cmdline-tools/cmdline-tools ${ANDROID_SDK_ROOT}/cmdline-tools/latest

# Accept Android SDK licenses
# This is crucial for SDK commands to work
RUN yes | sdkmanager --licenses

# Install specific Android SDK platforms and build-tools (adjust versions as needed)
# You might need to check your project's build.gradle for the exact versions.
# For example, if your compileSdkVersion is 34 and buildToolsVersion is 34.0.0, use those.
RUN sdkmanager "platforms;android-34" \
    "build-tools;34.0.0" \
    "platform-tools" \
    "cmdline-tools;latest" \
    "ndk;21.4.7075529" \
    "ndk;23.1.7779620" \
    "cmake;3.22.1" \
    "build-tools;33.0.0" \
    "build-tools;30.0.3" \
    && rm -rf ${ANDROID_SDK_ROOT}/.downloadIntermediates

# Install Node.js (you mentioned 16.x as default in your workflow, so this ensures it)
# The `eclipse-temurin` image usually comes with Java, but we might need to update Node/npm.
# It's generally better to install Node.js using nvm or a dedicated Node.js image if specific versions are critical,
# but for a simple build, apt-get with a PPA is often sufficient.
# Let's add NodeSource PPA for consistent Node.js versions
RUN curl -fsSL https://deb.nodesource.com/setup_16.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Expo CLI globally
# Also clean npm cache after global install to reduce image size.
RUN npm install -g expo-cli && npm cache clean --force

# Create a non-root user for npm and build processes
# Using fixed UID/GID as suggested by npm error messages previously, ensuring consistency.
# The complex '|| getent || add' logic aims for idempotency if UIDs/GIDs are already taken.
RUN groupadd -r -g 118 nodeuser || getent group 118 || groupadd -r -g 118 nodeuser
RUN useradd -r -u 1001 -g 118 -m -s /bin/bash -d /home/nodeuser nodeuser || getent passwd 1001 || useradd -r -u 1001 -g 118 -m -s /bin/bash -d /home/nodeuser nodeuser

# Pre-create and set permissions for npm's home directory data
RUN mkdir -p /home/nodeuser/.npm && chown -R 1001:118 /home/nodeuser/.npm

# Set up working directory and ensure it's writable by the new user
RUN mkdir -p /app && chown -R 1001:118 /app

# Switch to the non-root user
USER nodeuser
WORKDIR /app

# (Optional) Copy your project's package.json and package-lock.json to leverage Docker caching
# This assumes your npm dependencies are at the root of your project
# COPY package*.json ./
# RUN npm ci

# You can add more dependencies or tools here if your build script requires them.
#
