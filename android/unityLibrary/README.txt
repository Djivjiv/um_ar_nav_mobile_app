Export the Unity project here as an Android Library.

Source Unity project (on this machine, at time of writing):
  C:\Users\Lj\Documents\Jiver Files\UM_ar_mobileapp_Unity\FINAL_UM_AR\Um_AR_UNITY_MOBILE

How to export:
  1. In Unity, open the project above.
  2. File > Build Settings > Android > Switch Platform (if not already).
  3. In Player Settings, make sure "Export Project" is checked (this makes
     Unity emit a Gradle-ready Android Library module instead of a
     standalone APK).
  4. File > Build Settings > Build. Choose an output folder.
  5. Copy the exported module's contents into THIS folder
     (android/unityLibrary/), so that this folder ends up containing (at
     least):
       android/unityLibrary/build.gradle          (or build.gradle.kts)
       android/unityLibrary/src/main/AndroidManifest.xml
       android/unityLibrary/src/main/java/...      (UnityPlayerActivity etc.)
       android/unityLibrary/libs/*.aar             (unity-classes.jar / aars)
       android/unityLibrary/libs/*.jar

Once a real build.gradle(.kts) exists in this folder, the Flutter project's
Gradle files automatically pick it up:
  - android/settings.gradle.kts only calls `include(":unityLibrary")` when
    this folder actually contains a build.gradle(.kts) — until then it's
    skipped, so `flutter build` / `flutter run` keep working normally with
    no Unity module.
  - android/app/build.gradle.kts's `implementation(project(":unityLibrary"))`
    is likewise only added when the module is included.
  - android/build.gradle.kts's flatDir repository (for unityLibrary's own
    .jar/.aar deps under libs/) is added the same way.

After copying the export in:
  1. Re-run `flutter build apk --debug` from the Flutter project root and
     fix any Gradle errors Unity's own export reports (version mismatches,
     duplicate manifest entries, etc. are common and are unrelated to the
     Flutter side).
  2. In UnityBridge.kt (android/app/src/main/kotlin/.../UnityBridge.kt),
     confirm `Class.forName("com.unity3d.player.UnityPlayerActivity")`
     resolves — `UnityBridgeService.instance.isAvailable()` on the Flutter
     side should then return true, and unity_ar_screen.dart takes over
     instead of falling back to the camera/compass AR screen.
  3. Wire Unity's C# side to call back into UnityBridge's event-emitting
     method (see the TODO(unity) comments in UnityBridge.kt) for
     `arrived` / `qr_scanned` / `error` so Flutter hears back from Unity.

Do not commit an actual Unity export's generated build artifacts (`.gradle`,
`build/`, obj/ etc.) if this repo later adds a .gitignore for this folder —
only the source the export needs to rebuild.
