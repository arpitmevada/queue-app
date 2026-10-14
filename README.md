# Restaurant Queue Manager (Android + Firebase)

Staff Android app (Flutter) + Firebase backend + customer status web page (no customer app needed).

## Setup
1. Install Flutter and Node 20. Create a Firebase project (Blaze plan, needed for Functions).
2. Enable **Authentication > Phone**, **Firestore**, **Hosting**.
3. Generate the Android folder: `flutter create . --org in.yourcompany --project-name queue_manager`
4. Run `dart pub global activate flutterfire_cli && flutterfire configure` (adds google-services.json). Add your SHA-1/SHA-256 in Firebase console for OTP.
5. Edit `public/index.html`: paste your Firebase web config.
6. SMS (India): register on MSG91, complete **DLT** sender ID + template approval. Create `functions/.env`:
   ```
   MSG91_KEY=xxxx
   MSG91_TEMPLATE=xxxx
   BASE_URL=https://YOUR-PROJECT.web.app
   ```
   Template variables: name, token, restaurant, link.
7. Deploy: `cd functions && npm install && cd .. && firebase deploy`
8. Run the app: `flutter run` / build APK: `flutter build apk --release`

## How it works
- Staff log in with mobile + OTP; each restaurant is its own account.
- Token numbers are generated in a Firestore transaction, reset daily.
- A Cloud Function recalculates position/ETA on every change, updates the public status page and sends SMS.
- Customer opens `BASE_URL/q/<id>` to see live status or cancel.

## Roadmap
WhatsApp templates (Gupshup/Interakt), staff roles, reports, QR self check-in, feedback, offline mode.
