#!/usr/bin/env bash
# Release the current main to the WSL production rehearsal and the connected phone.
#   scripts/release_local.sh            # next patch version (v0.9.0 -> v0.9.1)
#   scripts/release_local.sh minor      # v0.9.1 -> v0.10.0
#   scripts/release_local.sh major      # v0.10.0 -> v1.0.0
# Needs: PLAY_CLOUD_PROJECT_NUMBER in the environment; asks for the keystore passwords.
set -euo pipefail

BUMP=${1:-patch}
VERIFY_URL=https://localhost:8443
PORT=8443
DEPLOY_DIR=/opt/passport-reader/src
PYTHON_DIR=/opt/passport-reader/python
CA_CERT=$HOME/secure/passport-ca/primary-ca.pem
APK=build/app/outputs/flutter-apk/app-real-release.apk

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
fail() { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

cd "$(git rev-parse --show-toplevel)"
[[ "$BUMP" =~ ^(patch|minor|major)$ ]] || fail "bump must be patch, minor or major (got: $BUMP)"
: "${PLAY_CLOUD_PROJECT_NUMBER:?export PLAY_CLOUD_PROJECT_NUMBER first}"

# --- 1. Safety checks ----------------------------------------------------------
step "Checking the repository and the device"
[[ "$(git branch --show-current)" == main ]] || fail "switch to main first"
[[ -z "$(git status --porcelain)" ]] || fail "working tree is not clean: commit or stash first"
git fetch --quiet --tags origin
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] \
  || fail "local main differs from origin/main: push (or pull) first"
[[ "$(adb get-state 2>/dev/null)" == device ]] || fail "no phone on adb (adb connect …)"
[[ -d "$DEPLOY_DIR/.git" ]] || fail "$DEPLOY_DIR missing: do the first deployment by hand (Sprint 9d, Part 5)"
SHA=$(git rev-parse HEAD)

# --- 2. CI gate ----------------------------------------------------------------
step "Waiting for CI on ${SHA:0:7}"
run_id=""
for _ in {1..30}; do                       # CI can take a moment to appear after a push
  run_id=$(gh run list --workflow ci.yml --commit "$SHA" --limit 1 --json databaseId --jq '.[0].databaseId // empty')
  [[ -n "$run_id" ]] && break
  sleep 10
done
[[ -n "$run_id" ]] || fail "no CI run found for $SHA"
gh run watch "$run_id" --exit-status > /dev/null || fail "CI did not pass for $SHA: not releasing"
echo "CI passed (run $run_id)"

# --- 3. Tag ----------------------------------------------------------------------
step "Tagging"
TAG=$(git tag --points-at HEAD --list 'v*' | sort -V | tail -1)
if [[ -n "$TAG" ]]; then
  echo "HEAD is already $TAG: reusing it"
else
  latest=$(git tag --list 'v*' --sort=-v:refname | head -1)
  IFS=. read -r major minor patch <<< "${latest:-v0.0.0}"
  major=${major#v}
  case $BUMP in
    major) TAG="v$((major + 1)).0.0" ;;
    minor) TAG="v$major.$((minor + 1)).0" ;;
    patch) TAG="v$major.$minor.$((patch + 1))" ;;
  esac
  git tag -a "$TAG" -m "Release $TAG"
  git push --quiet origin "$TAG"
  echo "Created $TAG (previous: ${latest:-none})"
fi

# --- 4. Server -------------------------------------------------------------------
step "Deploying $TAG to the WSL server"
git -C "$DEPLOY_DIR" fetch --quiet --tags
git -C "$DEPLOY_DIR" -c advice.detachedHead=false checkout --quiet "$TAG"
(cd "$DEPLOY_DIR/backend" && UV_PYTHON_INSTALL_DIR="$PYTHON_DIR" uv sync --locked --no-dev --quiet)
sudo systemctl restart passport-api
curl -fsS --retry 10 --retry-connrefused --retry-delay 1 --cacert "$CA_CERT" \
  "https://localhost:$PORT/health" > /dev/null || fail "server unhealthy after restart: journalctl -u passport-api -n 30"
echo "Server healthy on $TAG"

# --- 5. App ----------------------------------------------------------------------
step "Building the release APK for $TAG"
if [[ -z "${PR_STORE_PASSWORD:-}" ]]; then
  read -rsp "Keystore password: " PR_STORE_PASSWORD && echo && export PR_STORE_PASSWORD
fi
if [[ -z "${PR_KEY_PASSWORD:-}" ]]; then
  read -rsp "Key password: " PR_KEY_PASSWORD && echo && export PR_KEY_PASSWORD
fi
flutter build apk --release --flavor real \
  --build-name "${TAG#v}" \
  --build-number "$(git rev-list --count HEAD)" \
  --obfuscate --split-debug-info="build/symbols/$TAG" \
  --dart-define=VERIFY_URL="$VERIFY_URL" \
  --dart-define=PLAY_CLOUD_PROJECT_NUMBER="$PLAY_CLOUD_PROJECT_NUMBER"

# --- 6. Phone --------------------------------------------------------------------
step "Installing on the phone"
adb install -r "$APK"
adb reverse "tcp:$PORT" "tcp:$PORT"

step "Released $TAG"
echo "Server: journalctl -u passport-api -f"
echo "Symbols for crash traces: build/symbols/$TAG"