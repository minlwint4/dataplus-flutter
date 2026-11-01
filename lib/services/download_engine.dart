name: Build Flutter APK

on:
  push:
    branches: [ main, master ]
  workflow_dispatch:

permissions:
  contents: write

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
    - name: Checkout Code
      uses: actions/checkout@v4

    - name: Set up Java
      uses: actions/setup-java@v4
      with:
        distribution: 'zulu'
        java-version: '17'

    - name: Configure Maven Central Mirror
      run: |
        mkdir -p ~/.gradle/init.d
        cat << 'EOF' > ~/.gradle/init.d/mirror.init.gradle
        def mirrorUrl = "https://maven-central.storage-download.googleapis.com/maven2/"
        allprojects {
            buildscript {
                repositories {
                    all { ArtifactRepository repo ->
                        if (repo instanceof MavenArtifactRepository) {
                            def url = repo.url.toString()
                            if (url.contains("repo.maven.apache.org") || url.contains("repo1.maven.org")) {
                                repo.setUrl(mirrorUrl)
                            }
                        }
                    }
                }
            }
            repositories {
                all { ArtifactRepository repo ->
                    if (repo instanceof MavenArtifactRepository) {
                        def url = repo.url.toString()
                        if (url.contains("repo.maven.apache.org") || url.contains("repo1.maven.org")) {
                            repo.setUrl(mirrorUrl)
                        }
                    }
                }
            }
        }
        EOF

    - name: Set up Flutter
      uses: subosito/flutter-action@v2
      with:
        flutter-version: '3.24.0'
        channel: 'stable'
        cache: true

    - name: Configure Android Project & Permissions
      run: |
        echo "Generating fresh Android Project structure..."
        rm -rf android
        flutter create . --org com.dataplus --project-name dataplus_app

        if [ -f "android/app/build.gradle" ]; then
          sed -i 's/applicationId ".*"/applicationId "com.dataplus.dataplus_app"/g' android/app/build.gradle
          sed -i 's/namespace ".*"/namespace "com.dataplus.dataplus_app"/g' android/app/build.gradle || true
          sed -i 's/compileSdk = .*/compileSdk = 34/g' android/app/build.gradle || true
          sed -i 's/compileSdkVersion .*/compileSdkVersion 34/g' android/app/build.gradle || true
        fi

        mkdir -p android
        echo "flutter.sdk=$FLUTTER_ROOT" > android/local.properties
        echo "flutter.buildMode=release" >> android/local.properties
        echo "flutter.versionName=1.0.0" >> android/local.properties
        echo "flutter.versionCode=1" >> android/local.properties

        if [ -f "android/settings.gradle" ]; then
          sed -i 's/org.jetbrains.kotlin.android" version "[^"]*"/org.jetbrains.kotlin.android" version "1.9.24"/g' android/settings.gradle
        fi

        if [ -f "android/build.gradle" ]; then
          sed -i '1i ext.kotlin_version = "1.9.24"\n' android/build.gradle
        else
          echo 'ext.kotlin_version = "1.9.24"' > android/build.gradle
        fi

        mkdir -p android/app/src/main/res/xml
        printf '%s\n' \
          '<?xml version="1.0" encoding="utf-8"?>' \
          '<paths xmlns:android="http://schemas.android.com/apk/res/android">' \
          '    <external-path name="external_files" path="." />' \
          '    <external-storage-path name="external_storage" path="." />' \
          '    <cache-path name="cache" path="." />' \
          '    <root-path name="root" path="." />' \
          '</paths>' > android/app/src/main/res/xml/filepaths.xml

        sed -i 's/android:label="[^"]*"/android:label="DATA_PLUS"/g' android/app/src/main/AndroidManifest.xml
        
        # 🌟 Background Service & Notifications Permissions
        sed -i '/<application/i \    <uses-permission android:name="android.permission.INTERNET"/>\n    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>\n    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>\n    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>\n    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="29"/>\n    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"/>\n    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>\n    <uses-permission android:name="android.permission.WAKE_LOCK"/>\n    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>\n    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC"/>\n    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>' android/app/src/main/AndroidManifest.xml
        sed -i 's/<application/<application android:usesCleartextTraffic="true" android:requestLegacyExternalStorage="true"/g' android/app/src/main/AndroidManifest.xml

        # 🌟 FileProvider & DownloadForegroundService Registration
        sed -i '/<\/application>/i \        <provider\n            android:name="androidx.core.content.FileProvider"\n            android:authorities="${applicationId}.fileProvider"\n            android:exported="false"\n            android:grantUriPermissions="true">\n            <meta-data\n                android:name="android.support.FILE_PROVIDER_PATHS"\n                android:resource="@xml/filepaths" \/>\n        <\/provider>\n        <service\n            android:name=".DownloadForegroundService"\n            android:foregroundServiceType="dataSync"\n            android:exported="false" \/>' android/app/src/main/AndroidManifest.xml

        mkdir -p android/app/src/main/kotlin/com/dataplus/dataplus_app
        printf '%s\n' \
          'package com.dataplus.dataplus_app' \
          '' \
          'import android.app.Activity' \
          'import android.app.Notification' \
          'import android.app.NotificationChannel' \
          'import android.app.NotificationManager' \
          'import android.app.Service' \
          'import android.content.Context' \
          'import android.content.Intent' \
          'import android.content.ComponentName' \
          'import android.net.Uri' \
          'import android.net.wifi.WifiManager' \
          'import android.os.Build' \
          'import android.os.Environment' \
          'import android.os.IBinder' \
          'import android.os.PowerManager' \
          'import android.os.StatFs' \
          'import android.provider.Settings' \
          'import android.view.WindowManager' \
          'import androidx.core.app.NotificationCompat' \
          'import androidx.core.content.FileProvider' \
          'import java.io.File' \
          'import io.flutter.embedding.android.FlutterActivity' \
          'import io.flutter.embedding.engine.FlutterEngine' \
          'import io.flutter.plugin.common.MethodChannel' \
          '' \
          'class DownloadForegroundService : Service() {' \
          '    companion object {' \
          '        const val CHANNEL_ID = "dataplus_downloads"' \
          '        const val NOTIF_ID = 2024' \
          '        var isRunning = false' \
          '    }' \
          '    private var wakeLock: PowerManager.WakeLock? = null' \
          '    private var wifiLock: WifiManager.WifiLock? = null' \
          '' \
          '    override fun onCreate() {' \
          '        super.onCreate() { }' \
          '        createChannel()' \
          '        try {' \
          '            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager' \
          '            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "DataPlus:DownloaderWakeLock").apply {' \
          '                setReferenceCounted(false)' \
          '                acquire(10 * 60 * 1000L * 60)' \
          '            }' \
          '            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager' \
          '            wifiLock = wm.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "DataPlus:DownloaderWifiLock").apply {' \
          '                setReferenceCounted(false)' \
          '                acquire()' \
          '            }' \
          '        } catch (_: Exception) {}' \
          '    }' \
          '' \
          '    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {' \
          '        val title = intent?.getStringExtra("title") ?: "DATA PLUS"' \
          '        val desc = intent?.getStringExtra("desc") ?: "ဖိုင်များ ဒေါင်းလုဒ်ဆွဲနေပါသည်..."' \
          '        val notif = NotificationCompat.Builder(this, CHANNEL_ID)' \
          '            .setContentTitle(title)' \
          '            .setContentText(desc)' \
          '            .setSmallIcon(android.R.drawable.stat_sys_download)' \
          '            .setOngoing(true)' \
          '            .setPriority(NotificationCompat.PRIORITY_LOW)' \
          '            .build()' \
          '        startForeground(NOTIF_ID, notif)' \
          '        isRunning = true' \
          '        return START_NOT_STICKY' \
          '    }' \
          '' \
          '    override fun onDestroy() {' \
          '        isRunning = false' \
          '        try {' \
          '            wakeLock?.let { if (it.isHeld) it.release() }' \
          '            wifiLock?.let { if (it.isHeld) it.release() }' \
          '        } catch (_: Exception) {}' \
          '        super.onDestroy()' \
          '    }' \
          '' \
          '    override fun onBind(intent: Intent?): IBinder? = null' \
          '' \
          '    private fun createChannel() {' \
          '        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {' \
          '            val ch = NotificationChannel(CHANNEL_ID, "DATA PLUS Background Download", NotificationManager.IMPORTANCE_LOW)' \
          '            ch.description = "Download Service Notification"' \
          '            val nm = getSystemService(NotificationManager::class.java)' \
          '            nm?.createNotificationChannel(ch)' \
          '        }' \
          '    }' \
          '}' \
          '' \
          'class MainActivity: FlutterActivity() {' \
          '    private val CHANNEL = "com.dataplus/storage"' \
          '    private var pendingPickResult: MethodChannel.Result? = null' \
          '    private val PICK_IMAGE_REQ = 9001' \
          '' \
          '    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {' \
          '        super.onActivityResult(requestCode, resultCode, data)' \
          '        if (requestCode == PICK_IMAGE_REQ) {' \
          '            val res = pendingPickResult' \
          '            pendingPickResult = null' \
          '            if (res != null) {' \
          '                if (resultCode == Activity.RESULT_OK && data?.data != null) {' \
          '                    try {' \
          '                        val uri = data.data!!' \
          '                        val inputStream = contentResolver.openInputStream(uri)' \
          '                        val tempFile = File(cacheDir, "req_photo_${System.currentTimeMillis()}.jpg")' \
          '                        if (inputStream != null) {' \
          '                            inputStream.use { input ->' \
          '                                tempFile.outputStream().use { output -> input.copyTo(output) }' \
          '                            }' \
          '                            res.success(tempFile.absolutePath)' \
          '                        } else { res.success(null) }' \
          '                    } catch (e: Exception) { res.success(null) }' \
          '                } else { res.success(null) }' \
          '            }' \
          '        }' \
          '    }' \
          '' \
          '    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {' \
          '        super.configureFlutterEngine(flutterEngine)' \
          '        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->' \
          '            when (call.method) {' \
          '                "startDownloadService" -> {' \
          '                    try {' \
          '                        val title = call.argument<String>("title") ?: "DATA PLUS"' \
          '                        val desc = call.argument<String>("desc") ?: "ဖိုင်များ ဒေါင်းလုဒ်ဆွဲနေပါသည်..."' \
          '                        val intent = Intent(this, DownloadForegroundService::class.java).apply {' \
          '                            putExtra("title", title)' \
          '                            putExtra("desc", desc)' \
          '                        }' \
          '                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {' \
          '                            startForegroundService(intent)' \
          '                        } else { startService(intent) }' \
          '                        result.success(true)' \
          '                    } catch (e: Exception) { result.error("ERROR", e.message, null) }' \
          '                }' \
          '                "stopDownloadService" -> {' \
          '                    try {' \
          '                        val intent = Intent(this, DownloadForegroundService::class.java)' \
          '                        stopService(intent)' \
          '                        result.success(true)' \
          '                    } catch (e: Exception) { result.error("ERROR", e.message, null) }' \
          '                }' \
          '                "pickImage" -> {' \
          '                    try {' \
          '                        pendingPickResult = result' \
          '                        val intent = Intent(Intent.ACTION_GET_CONTENT).apply {' \
          '                            type = "image/*"' \
          '                            addCategory(Intent.CATEGORY_OPENABLE)' \
          '                        }' \
          '                        startActivityForResult(Intent.createChooser(intent, "ဓာတ်ပုံ ရွေးချယ်ပါ"), PICK_IMAGE_REQ)' \
          '                    } catch (e: Exception) {' \
          '                        pendingPickResult = null' \
          '                        result.success(null)' \
          '                    }' \
          '                }' \
          '                "keepScreenOn" -> {' \
          '                    try {' \
          '                        val enable = call.argument<Boolean>("enable") ?: true' \
          '                        runOnUiThread {' \
          '                            if (enable) {' \
          '                                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)' \
          '                            } else {' \
          '                                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)' \
          '                            }' \
          '                        }' \
          '                        result.success(true)' \
          '                    } catch (e: Exception) {' \
          '                        result.error("ERROR", e.message, null)' \
          '                    }' \
          '                }' \
          '                "openDefaultApps" -> {' \
          '                    val intents = listOf(' \
          '                        Intent().setComponent(ComponentName("com.android.settings", "com.android.settings.applications.PreferredActivitySettings")),' \
          '                        Intent("android.settings.MANAGE_DEFAULT_APPS_SETTINGS"),' \
          '                        Intent("android.intent.action.MAIN").setComponent(ComponentName("com.android.settings", "com.android.settings.SubSettings")).putExtra(":settings:show_fragment", "com.android.settings.applications.PreferredListSettings"),' \
          '                        Intent().setComponent(ComponentName("com.miui.securitycenter", "com.miui.appmanager.AppManagerMainActivity")),' \
          '                        Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS),' \
          '                        Intent(Settings.ACTION_APPLICATION_SETTINGS)' \
          '                    )' \
          '                    var opened = false' \
          '                    for (targetIntent in intents) {' \
          '                        try {' \
          '                            targetIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)' \
          '                            startActivity(targetIntent)' \
          '                            opened = true' \
          '                            break' \
          '                        } catch (e: Exception) {}' \
          '                    }' \
          '                    if (opened) {' \
          '                        result.success(true)' \
          '                    } else {' \
          '                        result.error("ERROR", "Cannot open default apps", null)' \
          '                    }' \
          '                }' \
          '                "getStorageSpace" -> {' \
          '                    try {' \
          '                        val map = HashMap<String, Any>()' \
          '                        val internalPath = Environment.getExternalStorageDirectory()' \
          '                        val internalStat = StatFs(internalPath.path)' \
          '                        val intBlockSize = internalStat.blockSizeLong' \
          '                        map["total"] = internalStat.blockCountLong * intBlockSize' \
          '                        map["free"] = internalStat.availableBlocksLong * intBlockSize' \
          '                        val externalDirs = getExternalFilesDirs(null)' \
          '                        var sdFound = false' \
          '                        if (externalDirs.size > 1 && externalDirs[1] != null) {' \
          '                            val sdFile = externalDirs[1]' \
          '                            val isRemovable = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {' \
          '                                Environment.isExternalStorageRemovable(sdFile)' \
          '                            } else { true }' \
          '                            if (isRemovable) {' \
          '                                try {' \
          '                                    val sdStat = StatFs(sdFile.path)' \
          '                                    val sdBlockSize = sdStat.blockSizeLong' \
          '                                    map["sdTotal"] = sdStat.blockCountLong * sdBlockSize' \
          '                                    map["sdFree"] = sdStat.availableBlocksLong * sdBlockSize' \
          '                                    map["sdPath"] = sdFile.absolutePath' \
          '                                    map["sdAvailable"] = true' \
          '                                    sdFound = true' \
          '                                } catch (e: Exception) {}' \
          '                            }' \
          '                        }' \
          '                        if (!sdFound) {' \
          '                            map["sdAvailable"] = false' \
          '                            map["sdTotal"] = 0L' \
          '                            map["sdFree"] = 0L' \
          '                            map["sdPath"] = ""' \
          '                        }' \
          '                        result.success(map)' \
          '                    } catch (e: Exception) {' \
          '                        result.error("ERROR", e.message, null)' \
          '                    }' \
          '                }' \
          '                "openFile" -> {' \
          '                    try {' \
          '                        val filePath = call.argument<String>("path") ?: ""' \
          '                        val mimeType = call.argument<String>("mimeType") ?: "*/*"' \
          '                        val file = File(filePath)' \
          '                        if (!file.exists()) {' \
          '                            result.error("NOT_FOUND", "File not found", null)' \
          '                            return@setMethodCallHandler' \
          '                        }' \
          '                        val uri = FileProvider.getUriForFile(' \
          '                            this,' \
          '                            "${applicationContext.packageName}.fileProvider",' \
          '                            file' \
          '                        )' \
          '                        val intent = Intent(Intent.ACTION_VIEW).apply {' \
          '                            setDataAndType(uri, mimeType)' \
          '                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)' \
          '                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)' \
          '                        }' \
          '                        startActivity(intent)' \
          '                        result.success(true)' \
          '                    } catch (e: Exception) {' \
          '                        result.error("ERROR", e.message, null)' \
          '                    }' \
          '                }' \
          '                else -> { result.notImplemented() }' \
          '            }' \
          '        }' \
          '    }' \
          '}' > android/app/src/main/kotlin/com/dataplus/dataplus_app/MainActivity.kt

    - name: Install Dependencies & Patch Plugin SDK/Kotlin Versions
      run: |
        flutter clean
        flutter pub cache clean -f
        flutter pub get

        find ~/.pub-cache -name "build.gradle" -exec sed -i "s/ext.kotlin_version = '[^']*'/ext.kotlin_version = '1.9.24'/g" {} + || true
        find ~/.pub-cache -name "build.gradle" -exec sed -i 's/compileSdk 35/compileSdk 34/g' {} + || true
        find ~/.pub-cache -name "build.gradle" -exec sed -i 's/compileSdk = 35/compileSdk = 34/g' {} + || true
        find ~/.pub-cache -name "build.gradle" -exec sed -i 's/compileSdkVersion 35/compileSdkVersion 34/g' {} + || true

    - name: Generate App Launcher Icons
      run: |
        mkdir -p assets
        if [ -f "icon.png" ]; then
          cp icon.png assets/icon.png
        fi
        if [ -f "assets/icon.png" ]; then
          dart run flutter_launcher_icons
        fi

    - name: Ensure Persistent Release Keystore & Configure Signing
      run: |
        if [ ! -f "dataplus.jks" ]; then
          echo "Generating new persistent release keystore..."
          keytool -genkey -v -keystore dataplus.jks -alias dataplus -keyalg RSA -keysize 2048 -validity 10000 -storepass dataplus123 -keypass dataplus123 -dname "CN=DataPlus, OU=App, O=DataPlus, L=Yangon, C=MM"
          
          git config --global user.name "github-actions[bot]"
          git config --global user.email "github-actions[bot]@users.noreply.github.com"
          git add dataplus.jks
          git commit -m "chore: persist release signing keystore [skip ci]" || true
          git push || true
        else
          echo "Using existing persistent keystore from repository."
        fi
        
        cp dataplus.jks android/app/dataplus.jks

        if ! grep -q "signingConfigs.release" android/app/build.gradle; then
          sed -i '/buildTypes {/i \    signingConfigs {\n        release {\n            storeFile file("dataplus.jks")\n            storePassword "dataplus123"\n            keyAlias "dataplus"\n            keyPassword "dataplus123"\n            v1SigningEnabled true\n            v2SigningEnabled true\n            v3SigningEnabled true\n        }\n    }' android/app/build.gradle
          sed -i -E 's/signingConfig =? signingConfigs\.debug/signingConfig = signingConfigs.release/g' android/app/build.gradle
        fi

    - name: Build APK (Release)
      run: |
        flutter build apk --release \
          --target-platform android-arm,android-arm64 \
          --build-name=1.0.${{ github.run_number }} \
          --build-number=${{ github.run_number }} \
          --dart-define=APP_VERSION=1.0.${{ github.run_number }}

    - name: Upload APK Artifact
      uses: actions/upload-artifact@v4
      with:
        name: DATAPLUS_v1.0.${{ github.run_number }}
        path: build/app/outputs/flutter-apk/app-release.apk
