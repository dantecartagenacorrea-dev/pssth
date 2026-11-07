# Código propio de la app: lo llaman Flutter y el sistema por nombre.
-keep class com.lectorpdf.** { *; }

# Plugins de Flutter y clases que se buscan por nombre o desde código nativo.
-keep class io.flutter.plugins.** { *; }
-keep class com.k2fsa.** { *; }
-keepclasseswithmembernames class * { native <methods>; }

# ML Kit arma sus piezas por nombre al iniciar (texto, códigos, idioma, escáner).
-keep class com.google.mlkit.** { *; }
-keep class * implements com.google.firebase.components.ComponentRegistrar { <init>(); }

# Clases opcionales que algunas librerías mencionan pero no traen.
-dontwarn com.google.android.play.core.**
-dontwarn org.apache.tika.**
-dontwarn javax.annotation.**
-dontwarn org.slf4j.**
