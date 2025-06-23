#!/bin/bash
set -e

# Script to build Inji Wallet using a Docker container.

# --- Configuration ---
# Docker image name (Dynamically determined from the GitHub repository URL)
# Assumes the image is hosted on GitHub Container Registry (GHCR)
# and follows the pattern ghcr.io/OWNER/REPO/IMAGE_NAME:TAG
DEFAULT_DOCKER_IMAGE_NAME="android-build-env"
DEFAULT_DOCKER_IMAGE_TAG="latest"
# Construct the full image path, attempting to get OWNER/REPO from git remote
# Default to a placeholder if not in a git repo or remote is not GitHub
if git rev-parse --is-inside-work-tree > /dev/null 2>&1 && git config --get remote.origin.url &> /dev/null; then
    # Use # as delimiter for sed to avoid issues with slashes in the URL
    # Also, ensure .git is matched at the end of the string and . is escaped.
    REPO_FULL_NAME=$(git config --get remote.origin.url | sed -e 's#https://github.com/##' -e 's#\.git$##')
    DOCKER_IMAGE="ghcr.io/${REPO_FULL_NAME}/${DEFAULT_DOCKER_IMAGE_NAME}:${DEFAULT_DOCKER_IMAGE_TAG}"
else
    # Fallback if not in a git repo or no GitHub remote
    # The user might need to set DOCKER_IMAGE manually or build it locally
    echo "Warning: Could not determine GitHub repository from git remote."
    echo "You may need to manually set the DOCKER_IMAGE variable in this script or ensure it's available locally."
    DOCKER_IMAGE="your-ghcr-username-or-org/your-repo/${DEFAULT_DOCKER_IMAGE_NAME}:${DEFAULT_DOCKER_IMAGE_TAG}" # Placeholder
fi

INJI_WALLET_REPO_URL="https://github.com/mosip/inji-wallet.git"
DEFAULT_INJI_WALLET_SRC_DIR="./inji-wallet-src" # Default directory to clone into if not provided
OUTPUT_DIR="./output"

# --- Helper Functions ---
print_usage() {
    echo "Usage: $0 [OPTIONS] [PATH_TO_INJI_WALLET_SOURCE]"
    echo ""
    echo "Builds the Inji Wallet Android application using a Docker container."
    echo ""
    echo "If PATH_TO_INJI_WALLET_SOURCE is provided and exists, it will be mounted into the Docker container."
    echo "If not provided or the path doesn't exist, the script will attempt to clone it from ${INJI_WALLET_REPO_URL} into '${DEFAULT_INJI_WALLET_SRC_DIR}'."
    echo ""
    echo "Options:"
    echo "  -h, --help         Show this help message."
    echo "  --image IMAGE_URI  Specify the full Docker image URI to use (e.g., my-builder:latest or ghcr.io/owner/repo/img:tag)."
    echo "                     Defaults to: ${DOCKER_IMAGE}"
    echo ""
    echo "The build artifacts will be placed in the '${OUTPUT_DIR}' directory in the current path."
}

# --- Argument Parsing ---
INJI_WALLET_SRC_PATH=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help) print_usage; exit 0 ;;
        --image) DOCKER_IMAGE="$2"; shift ;;
        -*) echo "Unknown option: $1"; print_usage; exit 1 ;;
        *) INJI_WALLET_SRC_PATH="$1" ;;
    esac
    shift
done

# --- Main Script ---

echo "--- Inji Wallet Dockerized Build ---"
echo "Using Docker image: ${DOCKER_IMAGE}"

# Validate Docker installation
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed. Please install Docker to continue."
    exit 1
fi

# Prepare Inji Wallet source code
CLONED_INJI_WALLET=false
if [[ -z "${INJI_WALLET_SRC_PATH}" ]]; then
    echo "Path to Inji Wallet source not provided."
    INJI_WALLET_SRC_PATH="${DEFAULT_INJI_WALLET_SRC_DIR}"
    if [ -d "${INJI_WALLET_SRC_PATH}" ]; then
        echo "Using existing directory for Inji Wallet source: ${INJI_WALLET_SRC_PATH}"
        echo "Warning: Files in this directory might be overwritten if a git pull is performed by the build process inside Docker."
    else
        echo "Cloning Inji Wallet from ${INJI_WALLET_REPO_URL} into ${INJI_WALLET_SRC_PATH}..."
        git clone "${INJI_WALLET_REPO_URL}" "${INJI_WALLET_SRC_PATH}"
        CLONED_INJI_WALLET=true
    fi
elif [ ! -d "${INJI_WALLET_SRC_PATH}" ]; then
    echo "Provided Inji Wallet source path '${INJI_WALLET_SRC_PATH}' does not exist."
    echo "Attempting to clone Inji Wallet from ${INJI_WALLET_REPO_URL} into ${INJI_WALLET_SRC_PATH}..."
    git clone "${INJI_WALLET_REPO_URL}" "${INJI_WALLET_SRC_PATH}"
    CLONED_INJI_WALLET=true
else
    echo "Using user-provided Inji Wallet source directory: ${INJI_WALLET_SRC_PATH}"
fi

# Absolute path for Docker mount
INJI_WALLET_SRC_PATH_ABS="$(cd "$(dirname "${INJI_WALLET_SRC_PATH}")" && pwd)/$(basename "${INJI_WALLET_SRC_PATH}")"

# Prepare output directory
mkdir -p "${OUTPUT_DIR}"
OUTPUT_DIR_ABS="$(cd "$(dirname "${OUTPUT_DIR}")" && pwd)/$(basename "${OUTPUT_DIR}")"
echo "Build artifacts will be copied to: ${OUTPUT_DIR_ABS}"

# Attempt to pull the image first, in case it's pre-built by CI
echo "Attempting to pull Docker image ${DOCKER_IMAGE}..."
if docker pull "${DOCKER_IMAGE}"; then
    echo "Successfully pulled ${DOCKER_IMAGE}."
else
    echo "Failed to pull ${DOCKER_IMAGE}. This is okay if you intend to use a locally built image with the same name."
    echo "If the build fails later, ensure the image exists locally or is correctly specified."
fi


# Define Inji Wallet build commands to be executed inside Docker
DOCKER_BUILD_COMMANDS=$(cat <<'EOF'
set -e # Exit immediately if a command exits with a non-zero status.
echo "--- Inside Docker Container ---"
echo "Working directory: $(pwd)" # Should be /app/inji-wallet

echo "ANDROID_SDK_ROOT is: $ANDROID_SDK_ROOT"
echo "JAVA_HOME is: $JAVA_HOME"
java -version
node -v
npm -v
yarn --version
expo --version

# 1. Ensure android/local.properties points to the correct SDK location
echo "Creating android/local.properties..."
mkdir -p android
echo "sdk.dir=${ANDROID_SDK_ROOT}" > android/local.properties
echo "Created android/local.properties with content:"
cat android/local.properties

# 2. Generate debug.keystore if it doesn't exist in the mounted source's android/app directory
KEYSTORE_PATH="android/app/debug.keystore"
if [ ! -f "${KEYSTORE_PATH}" ]; then
    echo "Debug keystore not found at ${KEYSTORE_PATH}. Generating a new one..."
    mkdir -p android/app
    keytool -genkey -v \
        -storetype PKCS12 \
        -keyalg RSA \
        -keysize 2048 \
        -validity 10000 \
        -storepass 'android' \
        -keypass 'android' \
        -alias androiddebugkey \
        -keystore "${KEYSTORE_PATH}" \
        -dname "CN=io.mosip.residentapp,OU=Development,O=Inji,L=Bengaluru,S=Karnataka,C=IN"
    echo "Generated new debug.keystore."
else
    echo "Using existing debug.keystore found at ${KEYSTORE_PATH}."
fi

# Set environment variables for the keystore (might be used by Gradle)
export DEBUG_KEYSTORE_ALIAS=androiddebugkey
export DEBUG_KEYSTORE_PASSWORD=android

# 3. Fix npm cache permissions and install dependencies
echo "Fixing potential npm cache permission issues..."
mkdir -p /root/.npm
chown -R 1001:118 /root/.npm
echo "Running npm install..."
npm install

# 4. Run the Android build command
echo "Running npm run android:mosip..."
# The Inji Wallet's package.json script for "android:mosip" might be:
# "android:mosip": "cd android && ./gradlew clean && ./gradlew assembleMosipDebug && cd .."
# We are already in the root, so let's assume it handles cd into android or uses -p android
npm run android:mosip

# 5. Copy build artifacts to /build_output
echo "Copying build artifacts..."
ARTIFACT_DIR="android/app/build/outputs/apk/mosip/debug"
if [ -d "$ARTIFACT_DIR" ] && [ -n "$(ls -A $ARTIFACT_DIR/*.apk 2>/dev/null)" ]; then
    echo "Found APKs in $ARTIFACT_DIR. Copying to /build_output/"
    cp -r ${ARTIFACT_DIR}/*.apk /build_output/
    ls -la /build_output/
else
    echo "Error: No APKs found in ${ARTIFACT_DIR} after build."
    echo "Listing contents of android/app/build/outputs/apk/ (if it exists):"
    ls -Rla android/app/build/outputs/apk/ || echo "android/app/build/outputs/apk/ not found."
    exit 1
fi

echo "--- Exiting Docker Container ---"
EOF
)

echo "Starting Docker container for build..."
# Note: Adding --user $(id -u):$(id -g) can help with file permissions on output,
# but might complicate things if the container user needs specific UIDs or root access for installs.
# For now, let the container run as root, and the user can chown the output if needed.
docker run --rm \
    -v "${INJI_WALLET_SRC_PATH_ABS}:/app/inji-wallet:rw" \
    -v "${OUTPUT_DIR_ABS}:/build_output:rw" \
    -e "ANDROID_SDK_ROOT=${ANDROID_SDK_ROOT}" \
    -w /app/inji-wallet \
    "${DOCKER_IMAGE}" \
    /bin/bash -c "${DOCKER_BUILD_COMMANDS}"

echo "--- Build Process Complete ---"
echo "Build artifacts (if any) are in: ${OUTPUT_DIR_ABS}"
ls -la "${OUTPUT_DIR_ABS}"

# Cleanup cloned repo if we cloned it
# if [ "$CLONED_INJI_WALLET" = true ] && [ -d "${INJI_WALLET_SRC_PATH}" ]; then
#     read -p "Do you want to remove the cloned Inji Wallet source directory '${INJI_WALLET_SRC_PATH}'? (y/N) " -n 1 -r
#     echo
#     if [[ $REPLY =~ ^[Yy]$ ]]; then
#         echo "Removing ${INJI_WALLET_SRC_PATH}..."
#         rm -rf "${INJI_WALLET_SRC_PATH}"
#     fi
# fi

echo "Script finished."
