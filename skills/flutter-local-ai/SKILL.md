---
name: flutter-local-ai
description: Use when writing or reviewing Flutter app code that uses the flutter_local_ai package for on-device AI (Apple Foundation Models, Android Gemini Nano via ML Kit, Windows AI Foundry, Chrome Prompt API) - checking availability, generating or streaming text, structured JSON output, tool calls, genUI modules, platform setup, or testing with FakeLocalAiHost.
---

# Using flutter_local_ai

`flutter_local_ai` runs the operating system's built-in language model. It
does not download or bundle a model. Every feature depends on the device, OS
version and user settings, so **check at runtime and always have a fallback.**

```dart
import 'package:flutter_local_ai/flutter_local_ai.dart';
```

Requires Flutter 3.44+ / Dart 3.12+ (`flutter pub add flutter_local_ai`).

## Rule 1: check capabilities at runtime, never by platform

```dart
final status = await LocalAi.availability();
if (status != LocalAiAvailability.available) {
  if (status.isTransient) {
    // downloadable / downloading: the model can still become ready.
    await LocalAi.ensureReady(onProgress: (p) => debugPrint('$p%'));
  } else {
    debugPrint(await LocalAi.availabilityReason());
    return useFallback(); // server, bundled model, or hide the feature
  }
}

final caps = await LocalAi.capabilities();
caps.supportsStructuredOutput; caps.supportsToolCalling;
caps.supportsVision;           caps.supportsTokenCount;
```

Do **not** branch on `Platform.isIOS` and friends to decide features. The same
binary reports vision as unavailable on iOS 26 and available on 27.

`LocalAiAvailability` values: `available`, `downloadable`, `downloading`,
`unavailableDeviceUnsupported`, `unavailableOsTooOld`, `unavailableDisabled`,
`unavailableOther`.

On the **web**, `ensureReady()` must run inside a user gesture (a button's
`onPressed`). Outside one it throws `LocalAiUserActivationRequiredException`.

## Pick an API

| Need | Use |
|---|---|
| One conversation, simple prompts, tool calls, genUI | `FlutterLocalAi` |
| Several concurrent conversations, images, cancellation, token counts, explicit lifecycle | `LocalAiModel` / `LocalAiSession` |

Both run on the same native implementation. Don't mix them for one
conversation.

### `FlutterLocalAi` (one-shot facade)

```dart
final ai = FlutterLocalAi();
if (!await ai.isAvailable()) return;

await ai.initialize(instructions: 'You are a concise assistant.');

final res = await ai.generateText(
  prompt: 'Explain photosynthesis in two sentences.',
  config: const GenerationConfig(maxTokens: 200, temperature: 0.7),
);
print(res.text);            // also res.tokenCount, res.generationTimeMs

await for (final delta in ai.generateTextStream(prompt: 'A haiku on rain')) {
  buffer.write(delta);      // chunks are deltas, not cumulative
}
```

- Call `initialize()` before generating. It is required on Apple.
- Pass `instructions:` to `generateText`/`generateTextStream` for a stateless
  one-shot session that leaves the shared conversation untouched. Prefer it
  for independent calls. On Apple the shared transcript counts against a
  4096-token context window.
- `getPlatformInfo()` returns the backend and capability flags (the older
  form of `LocalAi.capabilities()`).
- Android model download: `getModelStatus()`, `downloadModel()`, and
  `openAICorePlayStore()` when AICore is missing.

### `LocalAiModel` / `LocalAiSession` (session API)

```dart
final model = await LocalAiModel.create(maxTokens: 4096);
final session = await model.openSession(
  systemInstruction: 'Be concise.',
  temperature: 0.7,
);
try {
  await session.addQueryChunk('Summarize: ...');
  // await session.addImage(bytes); // only if caps.supportsVision
  await for (final delta in session.getResponseAsync()) {
    buffer.write(delta);
  }
  // session.getResponse() for the whole text at once
  // session.stopGeneration() to cancel
} finally {
  await session.close();
  await model.close();
}
```

- Always close sessions and models (`try`/`finally`, or `dispose()` in a
  `State`).
- One turn per session at a time. A second concurrent `getResponse` throws
  `LocalAiSessionBusyException`. Open another session for parallel work.
- Per-turn sampling: `getResponse(overrides: LocalAiGenerationOverrides(...))`.

## Structured output (JSON schema)

Supported on Apple, Windows and web. **Not on Android**, where it throws
`STRUCTURED_OUTPUT_UNSUPPORTED`. Gate on `supportsStructuredOutput`.

```dart
final res = await ai.generateText(
  prompt: 'Extract the city and temperature from: "Rome, 24°C"',
  config: const GenerationConfig(
    maxTokens: 200,
    schema: {
      'type': 'object',
      'properties': {
        'city': {'type': 'string'},
        'celsius': {'type': 'number'},
      },
      'required': ['city', 'celsius'],
    },
  ),
);
final data = res.json; // Map<String, dynamic>?, or res.decodedJson for arrays
```

In the session API, use `session.getStructuredResponse(schema)`.

The supported subset is: objects with `required`, arrays with
`minItems`/`maxItems`, string `enum`, `string`/`integer`/`number`/`boolean`,
and `description`. Anything else throws an `ArgumentError` in Dart. Schemas do
**not** work with streaming. Use `generateText`.

## Tool calls (Apple only)

Gate on `supportsToolCalling`. On Android, Windows and web,
`registerTools` fails.

```dart
await ai.registerTools([
  LocalAiTool(
    name: 'getWeather',
    description: 'Current weather for a city.',
    parameters: const [
      ToolParameter(name: 'city', type: ToolArgumentType.string,
          description: 'City name'),
    ],
    onCall: (args) async => {'celsius': await weather(args['city'] as String)},
  ),
]);
try {
  final res = await ai.generateText(prompt: 'Is it warm in Rome?');
} finally {
  await ai.registerTools(const []); // scope tools to the turn
}
```

- `onCall` returns JSON-serializable data. Throw `LocalAiToolException` to
  give the model a readable error.
- Use `parameterSchema:` (JSON Schema) instead of `parameters:` for enums,
  lists or nested objects. Use one or the other, never both.

## Generative UI

```dart
final generator = LocalAiUiGenerator(ai);
final GenUiModuleSpec? module = await generator.generateModule(
  'Save \$500 for a weekend trip',
  language: 'English',
  onText: (raw) {/* progress */},
);
if (module == null) {
  debugPrint(generator.lastError); // returns null on any failure
  return deterministicUi();
}
render(module.toModuleJson());     // or module.toComponentMaps() for genui
```

Works on Apple and Android. To drive the same schema with another model, use
`LocalAiUiGenerator.genUiInstructions` and `LocalAiUiGenerator.parseModelOutput`.

## Platform setup checklist

- **iOS/macOS**: build with Xcode 26+. Inference needs OS 26+, Apple
  Intelligence hardware, and Apple Intelligence turned on. The app still runs
  on older OSes, where `availability()` returns `unavailableOsTooOld`.
- **Android**: `minSdk = 26`, Kotlin 2.3.21, and
  `compilerOptions { jvmTarget.set(JvmTarget.JVM_11) }`. Don't pin your own ML
  Kit versions. It needs AICore-capable hardware.
- **Windows**: no build setup. Running it needs a Copilot+ PC or supported GPU,
  Windows 11 25H2+, and an **MSIX-packaged** app with the `systemAIModels`
  capability. A plain `flutter run` reports `unavailableOther`. Streaming
  arrives as a single chunk.
- **Web**: desktop Chrome 148 or newer, from `localhost` or HTTPS (no flag
  or origin trial). No image input, no tools; `topP`/`maxOutputTokens` are
  ignored, and so are `temperature`/`topK` where Chrome no longer lets a page
  set them. Call `ensureReady()` from a user gesture.

## Testing

No OS model runs under `flutter test`. Use the published fake:

```dart
import 'package:flutter_local_ai/testing.dart';

test('summarizes', () async {
  final host = FakeLocalAiHost()..response = 'hello';
  debugLocalAiHost = host;
  addTearDown(() async {
    debugLocalAiHost = null;
    await host.dispose();
  });
  // ...exercise code that uses LocalAi / LocalAiModel / FlutterLocalAi
});
```

For streaming tests, play the platform's part with `host.emitToken(...)`,
`host.emitDone(...)` and `host.emitError(...)`. Extend `FakeLocalAiHost`
instead of writing your own double.

## Common mistakes

- Generating without checking `availability()` and providing a fallback.
- Feature-gating on `Platform.isX` instead of `capabilities()`.
- Using a `schema` on Android, or with `generateTextStream`.
- Leaving tools registered across unrelated generations.
- Not closing `LocalAiSession`/`LocalAiModel`.
- Treating stream chunks as cumulative. They are deltas.
- Calling `ensureReady()` at web start-up instead of from a button.
