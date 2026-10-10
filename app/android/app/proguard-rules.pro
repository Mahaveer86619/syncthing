# ML Kit's code scanner wires its parts together by reflection (component registrars listed in
# its manifest). R8 full mode strips or renames them, which crashes GmsBarcodeScanning.getClient
# with "getClass() on a null object reference".
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_code_scanner.** { *; }
-keep class * implements com.google.firebase.components.ComponentRegistrar { *; }
-keep class com.google.android.gms.common.moduleinstall.** { *; }
