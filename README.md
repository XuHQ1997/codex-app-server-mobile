# Codex App Server Mobile

An unofficial Flutter client for using
[Codex app-server](https://github.com/openai/codex) from an Android or iOS
device.

The app provides a mobile-native interface for conversations, approvals,
questions, diffs, and workspace files while Codex continues to run on your
development machine. It is designed primarily for a private
[Tailscale](https://tailscale.com/) network connecting a phone to an app-server
running on Linux or WSL.

> [!IMPORTANT]
> This project is not affiliated with or endorsed by OpenAI. Codex app-server's
> WebSocket transport is currently documented upstream as experimental and
> unsupported, so protocol changes may require client updates.

## Features

- Create, resume, search, sort, and delete Codex threads.
- Stream agent responses and compact intermediate reasoning/tool activity.
- Send follow-up input, steer a running turn, or interrupt it.
- Handle command, file-change, and permission approvals on mobile.
- Answer structured questions with options or custom text.
- View file-change diffs and browse/read files under the thread working
  directory.
- Change the model, approval policy, and reasoning effort for a thread.
- Use `/goal` and `/compact` through mobile composer controls.
- Track context-window usage and jump to newly streamed messages.
- Reconnect automatically and resume active conversations after network or app
  lifecycle interruptions.
- Restore the last server address and bearer token from platform secure storage.

## How It Works

```text
Android / iOS
    │
    │  ws:// over a private Tailscale network
    │  Authorization: Bearer <capability token>
    ▼
codex app-server
    │
    ▼
Your repository and development environment
```

The client uses the app-server JSON-RPC protocol over WebSocket. It sends a
bearer token when configured and deliberately does not send an `Origin` header,
as app-server rejects WebSocket upgrades that include one.

`ws://` does not provide TLS by itself. This project assumes Tailscale supplies
authenticated, encrypted transport between the mobile device and development
machine. Do not expose the app-server listener directly to the public internet.

## Server Setup

Generate a capability token on the machine running Codex:

```bash
mkdir -p ~/.codex
head -c 32 /dev/urandom | base64 > ~/.codex/app-server-token
chmod 600 ~/.codex/app-server-token
```

Then start app-server on an address reachable through your Tailscale setup:

```bash
codex app-server \
  --listen ws://0.0.0.0:9999 \
  --ws-auth capability-token \
  --ws-token-file ~/.codex/app-server-token
```

Connect the app using a Tailscale IP or MagicDNS name, for example:

```text
ws://100.x.y.z:9999
ws://development-machine:9999
```

The exact WSL networking steps depend on whether Tailscale runs inside WSL or
on Windows. See [the server setup guide](docs/server-setup.md) for secure
deployment options and troubleshooting.

## Development

Prerequisites:

- Flutter SDK compatible with the version in `pubspec.yaml`
- Android Studio / Android SDK, or Xcode for iOS
- A recent Codex CLI with `codex app-server`

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Build an Android debug APK:

```bash
flutter build apk --debug
```

The APK is written to:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

## Project Structure

```text
lib/
  data/       connection lifecycle, app-server facade, secure settings
  protocol/   typed thread, turn, item, approval, and filesystem models
  rpc/        JSON-RPC client and server-request routing
  state/      Riverpod controllers and streaming item state
  transport/  mobile WebSocket transport
  ui/         setup, threads, chat, approvals, diffs, and file browser
```

## Security

- Keep `--ws-auth capability-token` enabled for a network listener.
- Treat the bearer token as a password; the app stores it using platform secure
  storage.
- Restrict access with Tailscale ACLs where possible.
- Do not expose port `9999` through a public router or unrestricted firewall.
- The app file browser is UI-restricted to the thread working directory, but
  app-server filesystem APIs ultimately run with the server process's OS
  permissions.

## Status

The client is under active development. The implemented protocol surface is
intentionally focused on common mobile workflows rather than every app-server
method.

## License

Licensed under the [Apache License 2.0](LICENSE).
