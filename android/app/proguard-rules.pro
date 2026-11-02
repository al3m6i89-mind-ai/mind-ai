# WorkManager creates its Room database by reflection; R8 must keep the generated
# class and its no-argument constructor, or the app crashes at launch.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class * extends androidx.work.ListenableWorker { <init>(android.content.Context, androidx.work.WorkerParameters); }
