# sincro_mobile

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Gmail email triage feature (requires a dart-define)

The "Conectar Gmail" flow on the Home screen requires a Google OAuth Web Client ID to be passed
at build/run time via `--dart-define=GOOGLE_WEB_CLIENT_ID=...`. Without it, Android's native
Google Sign-In flow silently returns a null `serverAuthCode`, the connection request throws, and
the user only sees a generic "Não foi possível conectar" message with no indication why.

```
flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=your-client-id.apps.googleusercontent.com
```

Use the same OAuth Web Client ID configured on the backend (`GOOGLE_CLIENT_ID` in
`backend/.env`) — see the Prerequisites section of
`docs/superpowers/plans/2026-08-02-gestao-executiva-triagem-email-plan.md` for how to create one.
