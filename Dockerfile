# Use a base image with Ubuntu and OpenJDK (Java)
FROM eclipse-temurin:11-jdk-focal 
# Using Java 11 as per your default, you can change it if needed

# Set environment variables for Android SDK
ENV ANDROID_SDK_ROOT="/usr/local/android-sdk"
ENV PATH="${PATH}:${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${ANDROID_SDK_ROOT}/platform-tools"

# Install necessary packages
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
    --no-install-recommends \
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
    "cmdline-tools;latest"

# Install Node.js (you mentioned 16.x as default in your workflow, so this ensures it)
# The `eclipse-temurin` image usually comes with Java, but we might need to update Node/npm.
# It's generally better to install Node.js using nvm or a dedicated Node.js image if specific versions are critical,
# but for a simple build, apt-get with a PPA is often sufficient.
# Let's add NodeSource PPA for consistent Node.js versions
RUN curl -fsSL https://deb.nodesource.com/setup_16.x | bash - \
    && apt-get install -y nodejs

# Set up a working directory
WORKDIR /app

# (Optional) Copy your project's package.json and package-lock.json to leverage Docker caching
# This assumes your npm dependencies are at the root of your project
# COPY package*.json ./
# RUN npm ci

# You can add more dependencies or tools here if your build script requires them.
