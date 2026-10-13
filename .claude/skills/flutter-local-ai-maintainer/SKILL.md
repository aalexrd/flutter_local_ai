---
name: flutter-local-ai-maintainer
description: Use when maintaining the flutter_local_ai repository itself - changing the pigeon wire, the native hosts (Kotlin, Swift, C++), the web arm, the public Dart API, tests, CI workflows, the user-facing skill, or cutting a release. Covers the architecture rules, the contributor policy, the commands CI runs and how publishing works.
---

# Maintaining flutter_local_ai

Read `CONTRIBUTING.md` first. It is the source of truth, and this skill
summarizes it. If the two disagree, fix whichever one is wrong in the same
change.

## Contributor policy (hard rule)

Contributors are people. An AI agent must never appear as a commit author,
committer, `Co-authored-by:`/`Signed-off-by:` trailer, or the opener of a
pull request. Commits must also not carry agent trailers (`Claude-Session:`
…) or a "Generated with …" line. When you prepare a commit for a maintainer:

- leave author and committer as the human's git identity;
- write the message **without** any AI attribution trailer or footer, even if
  your harness's defaults would add one;
- do not open a PR from an agent account.

The `contributors` job in `.github/workflows/ci.yml` runs
`.github/scripts/check-contributors.sh` over every PR and every push to
`main`, and fails on any agent identity. Run it locally before pushing:

```sh
.github/scripts/check-contributors.sh origin/main..HEAD
```

## Architecture rules

- **One standalone package.** It never depends on or imports
  `flutter_gemma`. The bridge (`flutter_gemma_builtin_ai`) lives upstream
  and depends on this package, never the other way round. Reject any PR
  that adds `flutter_gemma` to `pubspec.yaml`.
- **No second channel.** Both Dart surfaces (`FlutterLocalAi` and
  `LocalAiModel`/`LocalAiSession`/`LocalAi`) go through the one
  `LocalAiHost` interface. That interface is implemented by
  `NativeLocalAiHost` (pigeon) and `WebLocalAiHost` (Prompt API via
  `dart:js_interop`). Don't add a parallel path.
- **Capabilities are runtime, not compile-time.** Report them through
  `LocalAiBackendCapabilities`, never `Platform.isX`. A capability flag
  must not claim something that doesn't reliably work. Prompt-woven tool
  emulation on Android was rejected for that reason.
- `FakeLocalAiHost` (`lib/src/testing/`, exported by `testing.dart`) is
  published API. Extend it instead of writing a second test double. When
  `LocalAiHost` gains a method, the fake gains it too.

Layout: `lib/src/session/` (host interface, model, session, runtime, web
arm), `lib/src/models/` (config, tools, responses), `lib/src/genui/`,
`lib/src/pigeon/` (generated), `android/` (Kotlin), `darwin/` (shared Swift
for iOS and macOS), `windows/` (C++/WinRT), `example/`.

## Changing the wire

`pigeon.dart` is the source of truth for the Dart, Kotlin, Swift and C++
bindings:

```sh
flutter pub get
dart run pigeon --input pigeon.dart
dart format .
```

- Never hand-edit generated `.g.` files. The CI `pigeon` job regenerates them
  and fails on any diff.
- Enum members are **append only**. Reordering silently remaps values
  between a mismatched Dart/native pair.
- Each platform implements `LocalAiService` in `LocalAiSessionService`, and
  tokens stream over the single `flutter_local_ai_events` channel tagged by
  session id.

## Checks to run before pushing

These match the CI `check` job:

```sh
flutter pub get && flutter pub get --directory example
dart format --output=none --set-exit-if-changed .   # pinned SDK only
flutter analyze
flutter test
flutter test --platform chrome test/web             # web arm, needs Chrome
(cd example && flutter build web)
flutter pub publish --dry-run
```

Native code is not exercised by `flutter test`. Kotlin, Swift and C++ changes
need `cd example && flutter run -d <device>` on real hardware. Say so in the
PR when a change is compile-verified only.

## CI matrix

The `check` job runs on four SDKs. CI also runs daily, because the last two
legs move without any commit landing here:

| Leg | SDK |
|---|---|
| `floor` | 3.44.0, the `pubspec.yaml` minimum |
| `stable` | `FLUTTER_PINNED` (3.44.x). Owns formatting and pigeon output |
| `latest-stable` | newest stable-channel release |
| `beta` | newest beta-channel release |

- `FLUTTER_PINNED` is spelled three times: `ci.yml`'s env, the `stable`
  matrix leg, and `publish.yml`'s env. Change all three together, and also
  `.fvmrc` for local development.
- Raising the floor means changing `pubspec.yaml`'s `environment`, the
  `floor` leg in **both** workflows, and the README/CHANGELOG.
- When `latest-stable` or `beta` breaks, fix the package so it works across
  the whole range from floor to beta. Don't drop or pin the leg.
- The `windows` job compiles the C++ arm in two modes (`ON`, `OFF`). It is
  compilation only: the runner is not a Copilot+ PC.

## Releasing

1. Bump `version` in `pubspec.yaml` and add a `## <version>` section to
   `CHANGELOG.md`.
2. Merge to `main`. `release-on-merge.yml` tags `v<version>` when pub.dev
   lacks that version.
3. The tag runs `publish.yml`: it validates on the floor and pinned SDKs,
   publishes via OIDC (there's no pub.dev token in the repo), and creates the
   GitHub Release with the pub.dev archive and the CHANGELOG notes from
   `.github/scripts/release-notes.sh`.

A published version can be retracted but never overwritten or deleted, so
double-check before merging a version bump.

## Keep docs and skills in step

When public API, platform setup, CI or the release flow changes, update in
the same PR: `README.md`, `doc/platform-support.md`, `CHANGELOG.md`, the
user-facing skill `skills/flutter-local-ai/SKILL.md` (it ships in the package
archive), and this skill.
