# TapEx Client

Flutter mobile client for TapEx — offline-first expense tracking with Tailscale sync.

## iOS Shortcut: Log Expense

TapEx supports a custom URL scheme so you can log expenses from the iOS Shortcuts app.

### Setup

1. Build and install TapEx on your iPhone.
2. Open the **Shortcuts** app → tap **+** to create a new shortcut.
3. Add action: **Open URL** → enter `tapex://add`
4. Name the shortcut **Log Expense**.
5. Pin to Home Screen or add to a Shortcuts widget for one-tap access.

### What happens

1. Tap the shortcut → TapEx opens.
2. A text input sheet appears with the keyboard ready.
3. Type an expense using the same format as the main app, e.g. `45.90 dinner #food`.
4. Tap **Save** or press Enter → expense is saved locally and syncs in the background.

### Optional pre-fill

To open the sheet with text already filled (still requires tapping Save):

```
tapex://add?text=12%20coffee%20%23food
```

### Simulator test

```bash
xcrun simctl openurl booted "tapex://add"
```

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
