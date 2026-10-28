package app.nuvola.cloudphone

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import app.nuvola.cloudphone.ui.AppNav
import app.nuvola.cloudphone.ui.theme.NuvolaTheme

// AppCompatActivity so per-app language switching works on Android 12 and older.
class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val app = application as NuvolaApp
        setContent {
            val mode by app.themeMode.collectAsState()
            NuvolaTheme(mode) {
                Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                    androidx.compose.foundation.layout.Box(Modifier.safeDrawingPadding()) { AppNav() }
                }
            }
        }
    }
}
