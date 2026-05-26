package com.somyun.memo

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import com.somyun.memo.ui.MemoListScreen
import com.somyun.memo.ui.MemoViewModel
import com.somyun.memo.ui.theme.MemoTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // FCM 토큰 등록 (위젯 실시간 갱신용)
        MemoFirebaseMessagingService.registerToken(this)
        setContent {
            MemoTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    val viewModel: MemoViewModel = viewModel()
                    MemoListScreen(viewModel = viewModel)
                }
            }
        }
    }
}