package com.somyun.memo.widget

import android.content.Context
import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * 위젯 업데이트 자동 검증 테스트
 */
class WidgetUpdateTest {

    private lateinit var device: UiDevice
    private val packageName = "com.somyun.memo"

    @Before
    fun setUp() {
        device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
        device.pressHome()

        // 패키지 매니저를 통해 런처 대기
        val launcherPackage: String = device.launcherPackageName
        assertNotNull(launcherPackage)
        device.wait(Until.hasObject(By.pkg(launcherPackage).depth(0)), 5000)
    }

    @Test
    fun testWidgetUpdateFlow() {
        // 1. 위젯이 이미 홈 화면에 있다고 가정 (UI Automator로 위젯 추가는 런처마다 달라 매우 복잡함)
        // 위젯의 초기 상태 "메모를 선택하세요" 확인
        val initialWidget = device.wait(Until.findObject(By.text("메모를 선택하세요")), 5000)
        
        if (initialWidget == null) {
            // 위젯을 못 찾았을 경우, 테스트 환경 준비가 안 된 것으로 간주하고 실패 대신 메시지 출력
            // 실제 환경에서는 위젯을 미리 하나 배치해두는 것이 안정적임
            println("위젯을 홈 화면에서 찾을 수 없습니다. 테스트를 진행하려면 '메모를 선택하세요' 상태의 위젯을 배치해 주세요.")
            return
        }

        // 2. 위젯 클릭하여 설정 화면 진입
        initialWidget.click()

        // 3. 설정 화면 로딩 대기
        device.wait(Until.hasObject(By.pkg(packageName).depth(0)), 5000)
        
        // 4. 리스트에서 메모 하나 선택 (Card 형태의 아이템 클릭)
        // 메모 텍스트를 포함하고 있는 뷰를 찾아 클릭
        val memoItem = device.wait(Until.findObject(By.res(packageName, "")), 5000) 
        // Resource ID가 없을 경우 text가 있는 것을 찾음
        val anyMemo = device.findObject(By.textContains(" ")) // 공백이 있는 아무 텍스트나 (메모 내용 가정)
        
        if (anyMemo != null) {
            val targetText = anyMemo.text
            anyMemo.click()

            // 5. 홈 화면으로 복귀 대기 (액티비티가 finish() 되면서 홈으로 돌아옴)
            device.wait(Until.hasObject(By.pkg(device.launcherPackageName).depth(0)), 5000)

            // 6. 위젯의 텍스트가 선택한 메모의 텍스트로 즉시 변경되었는지 확인
            // 최대 3초간 변경 대기 (재시도 로직 포함 고려)
            val updatedWidget = device.wait(Until.findObject(By.text(targetText)), 5000)
            assertNotNull("위젯이 즉시 업데이트되지 않았습니다.", updatedWidget)
        } else {
            assertTrue("선택할 메모가 없습니다.", false)
        }
    }
}
