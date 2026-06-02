package com.somyun.memo

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import com.somyun.memo.ui.MemoListScreen
import com.somyun.memo.ui.MemoViewModel
import com.somyun.memo.ui.theme.MemoTheme

class MainActivity : ComponentActivity() {
    private var targetMemoId by mutableStateOf<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        targetMemoId = intent.getStringExtra(EXTRA_MEMO_ID)
        enableEdgeToEdge()
        MemoFirebaseMessagingService.registerToken(this)

        setContent {
            MemoTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    val viewModel: MemoViewModel = viewModel()
                    MemoListScreen(
                        viewModel = viewModel,
                        initialFocusMemoId = targetMemoId,
                        onInitialFocusHandled = { targetMemoId = null }
                    )
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        targetMemoId = intent.getStringExtra(EXTRA_MEMO_ID)
    }

    companion object {
        const val EXTRA_MEMO_ID = "memo_id"
    }
}
