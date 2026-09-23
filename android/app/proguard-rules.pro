# Flutter's Play Store deferred-components support — unused in this app,
# safe to ignore (known Flutter + R8 issue, not related to our plugins)
-dontwarn com.google.android.play.core.**


# Flutter core — never strip
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# flutter_foreground_task — background step service (the newest addition)
-keep class com.pravera.flutter_foreground_task.** { *; }

# camera plugin
-keep class io.flutter.plugins.camera.** { *; }
-keep class androidx.camera.** { *; }

# health plugin (Health Connect)
-keep class io.flutter.plugins.health.** { *; }
-keep class androidx.health.connect.** { *; }

# pedometer plugin
-keep class com.mounanas.pedometer.** { *; }
-keep class android.hardware.** { *; }

# WorkManager (used internally by flutter_foreground_task)
-keep class androidx.work.** { *; }

# Supabase / networking — keep model classes reflection-safe
-keepattributes Signature
-keepattributes *Annotation*
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# General safety net for Kotlin reflection metadata
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**
