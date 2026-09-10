/// Google Sign-In OAuth client configuration.
///
/// Firebase is NOT used, so there is no `google-services.json` and no
/// `com.google.gms.google-services` Gradle plugin. `google_sign_in` is
/// configured entirely from the values below.
///
/// - [webClientId] is the "Web application" OAuth client. Supabase validates
///   the Google `idToken` against it, so it is passed as `serverClientId`.
/// - [androidClientId] is the "Android" OAuth client created in Google Cloud
///   for [androidPackageName] + the app signing SHA-1. Android matches the
///   client by package name + SHA-1 at runtime, so it is reference-only here
///   (the `google_sign_in` v6 Android plugin does not take a client id).
/// - [iosClientId] is the "iOS" OAuth client. Required at runtime on iOS
///   (also set it in ios/Runner/Info.plist as `GIDClientID` plus the
///   reversed-client-id URL scheme).
class GoogleAuthConfig {
  GoogleAuthConfig._();

  static const String webClientId =
      '861229438514-4pi7l75heo402tvuubmeagqds8lgqg3c.apps.googleusercontent.com';

  static const String androidPackageName = 'com.example.um_ar_mobile_app';

  static const String androidClientId =
      '861229438514-70113b5t527qtf460k7j3amia7lipi7g.apps.googleusercontent.com';

  /// iOS OAuth client id. Provide via --dart-define=GOOGLE_IOS_CLIENT_ID=...
  static const String iosClientId =
      String.fromEnvironment('GOOGLE_IOS_CLIENT_ID', defaultValue: '');

  static const List<String> scopes = ['email', 'profile'];

  static const String allowedDomain = 'umindanao.edu.ph';
}
