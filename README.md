# 🌐 Web Viewer App (Flutter)

A minimal Flutter Android app — paste any URL and it loads the website right inside the app.

---

## 📁 Project Structure

```
webview_app/
├── lib/
│   └── main.dart                        ← All app code (UI + WebView logic)
├── android/
│   └── app/src/main/
│       ├── AndroidManifest.xml          ← Internet permission + config
│       └── res/xml/
│           └── network_security_config.xml  ← Allows HTTP & HTTPS
└── pubspec.yaml                         ← Dependencies (webview_flutter)
```

---

## 🚀 How to Run

### 1. Create a new Flutter project

```bash
flutter create webview_app
cd webview_app
```

### 2. Replace files

Copy the files from this ZIP into your project:
- Replace `lib/main.dart`
- Replace `pubspec.yaml`
- Replace `android/app/src/main/AndroidManifest.xml`
- Add `android/app/src/main/res/xml/network_security_config.xml` (create the `xml` folder if needed)

### 3. Install dependencies

```bash
flutter pub get
```

### 4. Run on Android

Connect your Android phone or start an emulator, then:

```bash
flutter run
```

---

## ✅ Requirements

- Flutter SDK 3.0+
- Android SDK (minSdkVersion 21+)
- Physical Android device or emulator

---

## 📦 Dependencies

| Package | Version | Purpose |
|---|---|---|
| `webview_flutter` | ^4.7.0 | Display websites inside the app |

---

## 💡 How It Works

1. Type or paste any URL in the top bar (e.g. `google.com`)
2. Tap the **→** button or press Enter
3. The website loads fullscreen — just like a browser!

- `https://` is added automatically if you don't include it
- Works with both HTTP and HTTPS URLs
- Shows a loading bar while the page loads
- Shows a friendly error if the URL is invalid or unreachable
