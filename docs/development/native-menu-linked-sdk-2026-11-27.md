# Beta90 native control appearance mismatch

The installed Beta90 uses the real NSSlider and NSSegmentedControl, but renders the older AppKit controls. Its Mach-O LC_BUILD_VERSION records minimumOS13.0 and SDK13.0. The direct swiftc preview records SDK27.0. Linking the same production menu fixture with SDK13.0 reproduces the user's old-style knob, track and segmented control, including during dragging.

A minimal macOS13Swift package confirms the difference on the current Swift6.4 toolchain: default swiftbuild and explicit --sdk27both record SDK13.0; --build-system native records minimumOS13.0 / SDK27.0. Apple documents that rebuilding with the latest SDK enables the refreshed controls: https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass

The App build script now selects the native engine and explicit active SDK and verifies LC_BUILD_VERSION before copying the executable and after signing the bundle. It records the actual linked SDK and deployment target in app-build.json. The native engine is deprecated; revisit this workaround when the default engine records the correct SDK. Never patch the binary's SDK or raise the deployment target to hide the mismatch.

The menu fixture accepts --built-app to reject an SDK mismatch before opening UI and to compile its Swift/C targets with the App's deployment target. Release visual verification must use this mode:

```sh
python3 scripts/build_app.py --output build/sdk-style/iFanControl.app
python3 packaging/pkg/test_menu_speed.py --output ../fixed-preview --built-app build/sdk-style/iFanControl.app
```

The local fixed App and matching fixture record minimumOS13.0 / SDK27.0; bundle minimumOS remains15.0. Four Chinese/English light/dark cases pass, with fresh screenshots showing the glass knob during dragging. The guard rejects installed Beta90's SDK13.0. App source files, metadata, fan logic and language behavior are unchanged. Tests use synthetic telemetry and isolated preferences/configuration; no actual fan control. No macOS15/26hardware test, installation or fix deployment was performed. Published90artifacts remain unchanged; a future release needs a new build number.
