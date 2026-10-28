package app.nuvola.cloudphone.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.nuvola.cloudphone.data.ThemeMode

private val Light = lightColorScheme(
    primary = Color(0xFF4B3FD1),
    onPrimary = Color.White,
    primaryContainer = Color(0xFFE6E3FF),
    onPrimaryContainer = Color(0xFF17104F),
    secondary = Color(0xFF3F7F8C),
    onSecondary = Color.White,
    secondaryContainer = Color(0xFFD9EEF2),
    onSecondaryContainer = Color(0xFF0E3239),
    background = Color(0xFFF6F7FB),
    onBackground = Color(0xFF1B1D2A),
    surface = Color(0xFFFFFFFF),
    onSurface = Color(0xFF1B1D2A),
    surfaceVariant = Color(0xFFECEEF6),
    onSurfaceVariant = Color(0xFF5B6078),
    outline = Color(0xFFC9CDDD),
    outlineVariant = Color(0xFFDFE2EE),
    error = Color(0xFFB3261E),
    onError = Color.White,
    errorContainer = Color(0xFFFBE6E4),
    onErrorContainer = Color(0xFF5C0F0B),
)

private val Dark = darkColorScheme(
    primary = Color(0xFFA69DFF),
    onPrimary = Color(0xFF1E1670),
    primaryContainer = Color(0xFF332A9E),
    onPrimaryContainer = Color(0xFFE6E3FF),
    secondary = Color(0xFF8FCFDB),
    onSecondary = Color(0xFF0E3239),
    secondaryContainer = Color(0xFF26535C),
    onSecondaryContainer = Color(0xFFD9EEF2),
    background = Color(0xFF12131C),
    onBackground = Color(0xFFE8E9F3),
    surface = Color(0xFF1B1D2A),
    onSurface = Color(0xFFE8E9F3),
    surfaceVariant = Color(0xFF262838),
    onSurfaceVariant = Color(0xFFA2A6BF),
    outline = Color(0xFF454860),
    outlineVariant = Color(0xFF2E3145),
    error = Color(0xFFFF8F86),
    onError = Color(0xFF5C0F0B),
    errorContainer = Color(0xFF3D1C1A),
    onErrorContainer = Color(0xFFFBE6E4),
)

/** Status colors, separate from the brand accent. */
@Immutable
data class StatusColors(val ok: Color, val okBg: Color, val warn: Color, val warnBg: Color, val bad: Color, val badBg: Color, val idle: Color, val idleBg: Color)

private val LightStatus = StatusColors(
    ok = Color(0xFF167A4A), okBg = Color(0xFFE3F4EA),
    warn = Color(0xFF9A5B00), warnBg = Color(0xFFFDF1DC),
    bad = Color(0xFFB3261E), badBg = Color(0xFFFBE6E4),
    idle = Color(0xFF5B6078), idleBg = Color(0xFFECEEF6),
)
private val DarkStatus = StatusColors(
    ok = Color(0xFF6FD3A0), okBg = Color(0xFF173326),
    warn = Color(0xFFF2BD6B), warnBg = Color(0xFF3A2B12),
    bad = Color(0xFFFF8F86), badBg = Color(0xFF3D1C1A),
    idle = Color(0xFFA2A6BF), idleBg = Color(0xFF262838),
)

val LocalStatusColors = staticCompositionLocalOf { LightStatus }

private val AppTypography = Typography(
    headlineSmall = TextStyle(fontSize = 24.sp, fontWeight = FontWeight.SemiBold, lineHeight = 32.sp),
    titleLarge = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.SemiBold, lineHeight = 28.sp),
    titleMedium = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.SemiBold, lineHeight = 24.sp),
    bodyLarge = TextStyle(fontSize = 16.sp, lineHeight = 24.sp),
    bodyMedium = TextStyle(fontSize = 14.sp, lineHeight = 20.sp),
    labelLarge = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Medium, lineHeight = 20.sp),
    labelMedium = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Medium, lineHeight = 16.sp),
)

private val AppShapes = Shapes(
    small = RoundedCornerShape(10.dp),
    medium = RoundedCornerShape(16.dp),
    large = RoundedCornerShape(22.dp),
)

@Composable
fun NuvolaTheme(mode: ThemeMode, content: @Composable () -> Unit) {
    val dark = when (mode) {
        ThemeMode.SYSTEM -> isSystemInDarkTheme()
        ThemeMode.LIGHT -> false
        ThemeMode.DARK -> true
    }
    androidx.compose.runtime.CompositionLocalProvider(LocalStatusColors provides if (dark) DarkStatus else LightStatus) {
        MaterialTheme(colorScheme = if (dark) Dark else Light, typography = AppTypography, shapes = AppShapes, content = content)
    }
}
