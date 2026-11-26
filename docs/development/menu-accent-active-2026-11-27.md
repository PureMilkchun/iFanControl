# System accent in the status menu

The system accent resolves correctly, but an inactive owner application renders the embedded native controls in neutral gray. A real-menu fixture with NSApp.deactivate reproduces this in Auto and Manual. The old fixture's forced activation masked the difference. Disabled Auto sliders and step checkboxes must remain gray by design; the mode selector remains enabled.

The root menu now retains a MenuActivation delegate. On opening from the background it captures the previous application and activates the owner for native AppKit drawing. On dismissal it defers restoring focus until menu actions have run, skips restoration when an action has opened a key window or another app has already become active, and avoids restoring while the menu is reopened. An already-active owner is unchanged. Native controls and default system colors are retained.

Explicit native tint properties did not override inactive rendering. An active visual-effect backdrop also failed and visibly changed the menu surface, so neither is included.

Validation on macOS27.0.1: initially inactive red/Chinese/dark and blue/English/light menu interactions pass with accent-colored mode selection and enabled Manual controls, disabled gray Auto controls, same-menu drag/save/confirmation behavior and previous-app focus restoration. A purple/Chinese/dark probe compiles to the exact built App SDK/deployment target and confirms that an owned window opened after menu dismissal keeps focus. Actual screenshots in all three colors were reviewed. The accent overrides exist only in isolated process arguments; global AppleAccentColor remains0. App release build and SDK27/minimum13/signature checks pass; bundle admission remains15.0. No actual hardware operation or installation.

```sh
python3 scripts/build_app.py --output build/accent-preview/iFanControl.app
python3 packaging/pkg/test_menu_speed.py --output ../preview --built-app build/accent-preview/iFanControl.app --inactive --accent 4
```

This is a local fix on codex/menu-accent-active. Published Beta91 artifacts and language/fan behavior remain unchanged. No new build number or deployment was made.
