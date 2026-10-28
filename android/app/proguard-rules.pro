# kotlinx.serialization
-keepattributes *Annotation*, InnerClasses
-keepclassmembers class app.nuvola.cloudphone.data.** { *** Companion; }
-keepclasseswithmembers class app.nuvola.cloudphone.data.** { kotlinx.serialization.KSerializer serializer(...); }
-keep,allowobfuscation,allowshrinking interface retrofit2.Call
-keep,allowobfuscation,allowshrinking class kotlin.coroutines.Continuation
