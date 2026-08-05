#!/bin/bash
set -e

if [ -z "$1" ]; then
    echo "Usage: ./release.sh <version>"
    echo "Example: ./release.sh 1.0.0"
    exit 1
fi

VERSION="v$1"
# Ensure the v is not duplicated if you typed v1.0.0
if [[ "$1" == v* ]]; then
    VERSION="$1"
fi

# Check if tag already exists locally or remotely
TAG_EXISTS=false
if git rev-parse "$VERSION" >/dev/null 2>&1 || git ls-remote --tags origin | grep -q "refs/tags/$VERSION"; then
    TAG_EXISTS=true
fi

if [ "$TAG_EXISTS" = true ]; then
    echo "⚠️  Warning: Release $VERSION already exists."
    read -p "Do you want to delete the existing release and overwrite it? (y/N): " CONFIRM
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "🗑️  Deleting existing release $VERSION..."
        # Delete from GitHub and remote tags
        gh release delete "$VERSION" -y --cleanup-tag 2>/dev/null || true
        git push --delete origin "$VERSION" 2>/dev/null || true
        # Delete local tag
        git tag -d "$VERSION" 2>/dev/null || true
    else
        echo "❌ Aborting release."
        exit 1
    fi
fi

VERSION_NUM="$1"
if [[ "$1" == v* ]]; then
    VERSION_NUM="${1:1}"
fi

if [ "$TAG_EXISTS" = false ]; then
    echo "⚙️  Updating Info.plist version to $VERSION_NUM..."
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION_NUM" Info.plist || true
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION_NUM" Info.plist || true
    git add Info.plist
    git diff --cached --quiet || git commit -m "Bump version to $VERSION_NUM"
fi

echo "🚀 Building Unlatch..."
./build.sh

echo "📦 Packaging $VERSION..."
cd build
rm -f Unlatch.zip
zip -r -q Unlatch.zip Unlatch.app
cd ..

echo "🏷️ Creating git tag and pushing..."
git tag -a "$VERSION" -m "Release $VERSION"
git push origin "$VERSION" --force

echo "🚢 Publishing release to GitHub..."
gh release create "$VERSION" build/Unlatch.zip --title "Unlatch $VERSION" --generate-notes

echo "✅ Successfully released $VERSION!"
