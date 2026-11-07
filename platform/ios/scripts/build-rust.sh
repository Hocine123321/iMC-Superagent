#!/usr/bin/env bash
# Builds libhorizon_ios_bridge.a for the device and the simulator and puts each where project.yml looks.
set -euo pipefail
cd "$(dirname "$0")/../../.."          # repository root
export IPHONEOS_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-16.0}"
PROFILE="${PROFILE:-release}"
for pair in "aarch64-apple-ios:device" "aarch64-apple-ios-sim:sim"; do
  target="${pair%%:*}"; dir="${pair##*:}"
  rustup target add "$target" >/dev/null
  (cd horizon && cargo build --locked --profile "$PROFILE" --target "$target" -p horizon-ios-bridge)
  out="platform/ios/build/rust/$dir"; mkdir -p "$out"
  cp "horizon/target/$target/$PROFILE/libhorizon_ios_bridge.a" "$out/"
done
