package app.nuvola.cloudphone

import android.app.Application
import app.nuvola.cloudphone.data.ApiClient
import app.nuvola.cloudphone.data.AppConfig
import app.nuvola.cloudphone.data.SettingsStore
import app.nuvola.cloudphone.data.ThemeMode
import app.nuvola.cloudphone.data.TokenStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.Dispatchers

/** Manual dependency container; small enough that a DI framework would add more than it saves. */
class NuvolaApp : Application() {
    lateinit var tokens: TokenStore
        private set
    lateinit var settings: SettingsStore
        private set
    lateinit var client: ApiClient
        private set

    /** Server-provided settings loaded on the splash screen. */
    var config: AppConfig? = null

    /** For short calls that must finish even when the screen that started them closes. */
    val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    lateinit var themeMode: MutableStateFlow<ThemeMode>
        private set

    override fun onCreate() {
        super.onCreate()
        tokens = TokenStore(this)
        settings = SettingsStore(this)
        client = ApiClient(tokens)
        themeMode = MutableStateFlow(settings.themeMode)
    }
}
