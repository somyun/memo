package com.somyun.memo.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val LightColorScheme = lightColorScheme(
    primary = Color(0xFF6D5E00),
    onPrimary = Color.White,
    surface = MemoYellow,
    onSurface = TextPrimary,
    background = Background,
    onBackground = TextPrimary,
    error = AccentRed,
    surfaceVariant = MemoYellowDark,
    onSurfaceVariant = TextMuted
)

private val DarkColorScheme = darkColorScheme(
    primary = Color(0xFFD4C85C),
    onPrimary = Color(0xFF1A1A00),
    surface = DarkSurface,
    onSurface = DarkTextPrimary,
    background = DarkBackground,
    onBackground = DarkTextPrimary,
    error = AccentRed,
    surfaceVariant = Color(0xFF3A3620),
    onSurfaceVariant = DarkTextMuted
)

@Composable
fun MemoTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    val colorScheme = if (darkTheme) DarkColorScheme else LightColorScheme

    MaterialTheme(
        colorScheme = colorScheme,
        typography = Typography,
        content = content
    )
}