# specs/003-android-client.md — R8 rules for the release build.
#
# `isMinifyEnabled` was false until 2026-08-05 with a TODO to enable it "before shipping". Enabling
# it late is exactly when reflection-dependent libraries break, so it is switched on now, while
# there is an emulator to verify against, rather than under submission pressure.
#
# The app's own code needs no keep rules: every wire model is (de)serialized by kotlinx.serialization
# through generated serializers, not reflection, so R8 can rename freely.

# --- kotlinx.serialization -------------------------------------------------------------------
# The generated $$serializer objects are reached reflectively by the runtime's serializer lookup.
# Without these, decoding fails at runtime with SerializationException — and only for the release
# build, which is the worst possible time to discover it.
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**
-keepclassmembers class **$$serializer { *; }
-keepclasseswithmembers class ** {
    public static ** Companion;
    kotlinx.serialization.KSerializer serializer(...);
}
-if @kotlinx.serialization.Serializable class **
-keepclassmembers class <1> {
    static <1>$Companion Companion;
}

# --- Firebase / Google Play services ----------------------------------------------------------
# Both resolve components reflectively at init; stripping them yields an empty-stack crash on the
# first Firebase call rather than a compile error.
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# --- AndroidX WorkManager ---------------------------------------------------------------------
# Workers are instantiated by name. The custom WorkerFactory covers this app's own workers, but
# the library still reflects over ListenableWorker subclasses.
-keep class * extends androidx.work.ListenableWorker { *; }

# --- Kotlin coroutines ------------------------------------------------------------------------
-dontwarn kotlinx.coroutines.**

# Keep source file/line info so a release stack trace from a family member is readable.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
