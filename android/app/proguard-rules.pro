# google_mlkit_text_recognition references optional script recognizers
# (Chinese, Devanagari, Japanese, Korean) that are not bundled — only Latin
# is needed for MRZ. Suppress R8's missing-class errors for them.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# ML Kit loads parts of its text recognizer by name at runtime.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_** { *; }
-dontwarn com.google.mlkit.vision.text.**
