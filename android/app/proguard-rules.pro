# google_mlkit_text_recognition references optional script recognizers
# (Chinese, Devanagari, Japanese, Korean) that are not bundled — only Latin
# is needed for MRZ. Suppress R8's missing-class errors for them.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
