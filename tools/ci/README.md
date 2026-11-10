# CI changes waiting for the owner

`ios-app-macos26.patch` moves the app build to the `macos-26` runner (Xcode 26.6, iOS 26 SDK), which the
system Liquid Glass in launcher v2 (M24) needs. The token used by the assistant has only the `repo` scope, so
GitHub refuses a push that touches `.github/workflows/`. Apply it yourself:

    git apply tools/ci/ios-app-macos26.patch
    git commit -am "ci: build on macOS 26 for system Liquid Glass" && git push

Or edit `.github/workflows/ios-app.yml` by hand: `runs-on: macos-26`, and add the "Show the Xcode and SDK" step.
The first build after the change recompiles the engine (about 21 minutes) because the Rust cache key changes.
