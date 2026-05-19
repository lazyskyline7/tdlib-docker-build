#!/usr/bin/env bash
set -euo pipefail

# Ensure clean working tree
if [ -n "$(git status --porcelain)" ]; then
    echo "Error: Working tree is not clean. Commit or stash changes first."
    exit 1
fi

# Ensure merge=ours driver is configured (needed for README.md)
git config merge.ours.driver true

# 1. Fetch upstream
echo "==> Fetching upstream..."
git fetch upstream

# 2. Fast-forward master to upstream/master
echo "==> Updating master..."
git checkout master
git merge --ff-only upstream/master

# 3. Merge master into build (README auto-resolved via merge=ours)
echo "==> Merging master into build..."
git checkout build
git merge master

# 4. Bump README version badge to match CMakeLists.txt
VERSION=$(awk '/project\(TDLib VERSION/ {print $3}' CMakeLists.txt | tr -d '[:space:]()')
echo "==> Syncing README badge to ${VERSION}..."
sed -i.bak -E "s|TDLib-[0-9]+\.[0-9]+\.[0-9]+-blue|TDLib-${VERSION}-blue|" README.md
rm -f README.md.bak
if [ -n "$(git status --porcelain README.md)" ]; then
    git add README.md
    git commit -m "docs: bump TDLib version badge to ${VERSION}"
fi

# 5. Create/force-update local tag (force-pushed in step 6)
if [ -z "$VERSION" ]; then
    echo "Error: Could not extract TDLib version from CMakeLists.txt."
    exit 1
fi
echo "==> Tagging ${VERSION}..."
git tag -f "${VERSION}"

# 6. Summary
echo ""
echo "========================================="
echo "  Ready to push"
echo "========================================="
echo "  master  → origin/master"
echo "  build   → origin/build"
echo "  tag     → ${VERSION}"
echo "========================================="
echo ""
read -p "Push all? [y/N] " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Leading '+' force-updates the tag ref only; master/build stay fast-forward
    # (never force branches). --atomic so a rejected branch push can't leave a
    # half-released state where the tag moved but the branches didn't.
    git push --atomic origin master build "+refs/tags/${VERSION}"
    echo ""
    echo "Done! CI/CD will build and release ${VERSION}."
    echo "Note: ${VERSION} was force-pushed. CI may NOT auto-trigger on a moved tag;"
    echo "      re-run the release pipeline manually if no build starts."
else
    echo "Aborted. You can push manually:"
    echo "  git push --atomic origin master build \"+refs/tags/${VERSION}\""
fi
