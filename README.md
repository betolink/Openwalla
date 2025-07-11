# LuCI Mobile

<div align="center">
  <a href="https://apt.izzysoft.de/fdroid/index/apk/com.cogwheel.LuCIMobile">
    <img src="https://gitlab.com/IzzyOnDroid/repo/-/raw/master/assets/IzzyOnDroid.png" alt="Get it on IzzyOnDroid"/>
  </a>
  <br><br>
  <a href="https://shields.rbtlog.dev/com.cogwheel.LuCIMobile">
    <img src="https://shields.rbtlog.dev/simple/com.cogwheel.LuCIMobile" alt="RB shield"/>
  </a>
  <br><br>
  <img src="fastlane/metadata/android/en-US/images/phoneScreenshots/dashboard-screen.png" width="500"/>
</div>

<br>

**LuCI Mobile** is a modern Flutter app for managing and monitoring multiple OpenWrt/LuCI routers. It features a beautiful Material 3 UI, secure authentication, real-time stats, and seamless multi-router support.

---

## 🚀 Features

- **Multiple Router Management:** Add, switch, and manage any number of OpenWrt routers. Each router’s data is kept separate and secure.
- **Secure Login:** HTTP/HTTPS support, self-signed certificate handling, and secure credential storage.
- **Dashboard Overview:** Real-time system stats, interface status, connected clients, and interactive charts.
- **Network Interface Management:** View and monitor all wired and wireless interfaces, bandwidth, IPs, and DNS.
- **Client Management:** See all connected devices, connection type, MAC/IP, vendor, DHCP lease, and more.
- **System Control:** Remote reboot, settings, and theme customization (light/dark mode).
- **Modern UI/UX:** Material Design 3, responsive layout, and intuitive navigation.
- **Open Source:** GPLv3 licensed and available on [IzzyOnDroid](https://apt.izzysoft.de/fdroid/index/apk/com.cogwheel.LuCIMobile).

---

## 📱 Multiple Router Functionality

- **Add Unlimited Routers:** Each with its own credentials and settings.
- **Quick Switch:** Instantly switch routers from the dashboard dropdown or "Manage Routers" screen.
- **Isolated Data:** Each router’s dashboard, clients, and settings are kept separate.
- **Edit & Remove:** Update credentials, rename, or remove routers at any time.
- **Auto-Connect:** Remembers your last selected router and auto-connects on launch.
- **Secure Storage:** All credentials are stored securely on your device.

---

## 🖼️ Screenshots

| Login | Dashboard | Clients | Interfaces |
|-------|-----------|---------|------------|
| <img src="fastlane/metadata/android/en-US/images/phoneScreenshots/login-screen.png" width="200"/> | <img src="fastlane/metadata/android/en-US/images/phoneScreenshots/dashboard-screen.png" width="200"/> | <img src="fastlane/metadata/android/en-US/images/phoneScreenshots/clients-screen.png" width="200"/> | <img src="fastlane/metadata/android/en-US/images/phoneScreenshots/interfaces-screen-wired.png" width="200"/> |

---

## ⚡ Installation

**Get it on [IzzyOnDroid](https://apt.izzysoft.de/fdroid/index/apk/com.cogwheel.LuCIMobile)** or build from source:

```bash
git clone https://github.com/cogwheel0/luci-mobile.git
cd luci-mobile
flutter pub get
flutter run
```

- Requires Flutter 3.32.5+ and Dart 3.8+
- Android: `flutter build apk`  
- iOS: `flutter build ios`

---

## 🛠️ Project Structure

```
lib/
├── config/                 # App configuration
├── models/                 # Data models (client, interface, router)
├── screens/                # UI screens (dashboard, clients, interfaces, login, more, etc.)
├── services/               # Business logic (API, secure storage)
├── state/                  # State management (app_state.dart)
├── widgets/                # Reusable UI components (luci_app_bar.dart)
└── main.dart               # App entry point
```

---

## 🔑 Key Dependencies
- **provider**: State management
- **http**: Network communication
- **flutter_secure_storage**: Secure credential storage
- **fl_chart**: Data visualization
- **package_info_plus**: App info
- **url_launcher**: External links

---

## 🧑‍💻 Development & Contribution

- Run in dev mode: `flutter run`
- Build for release: `flutter build apk --release` or `flutter build ios --release`
- Analyze code: `flutter analyze`

**Contributions welcome!** Please fork, branch, and submit a pull request.

---

## 🛡️ Security & Privacy
- All credentials are stored securely on-device
- HTTPS and self-signed certificate support
- No analytics or tracking

---

## ❓ Troubleshooting

- **Connection Failed:** Check router IP, LuCI web interface, firewall, and try both HTTP/HTTPS.
- **Authentication Failed:** Verify credentials and admin privileges.
- **No Data Displayed:** Check UCI RPC, network, and router logs.

---

## 📄 License

GPL v3.0. See [LICENSE](LICENSE).

---

## 🙏 Acknowledgments
- OpenWrt community for LuCI
- Flutter team
- [OpenWrtManager](https://github.com/hagaygo/OpenWrtManager) inspiration
- Contributors and testers

---

**Note:** This app requires an OpenWrt router with LuCI web interface enabled. Make sure your router is properly configured before use.
