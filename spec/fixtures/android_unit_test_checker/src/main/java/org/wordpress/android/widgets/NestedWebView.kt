// example declaration taken from https://github.com/wordpress-mobile/WordPress-Android/blob/44282b137085ec230771fc2c87ad9a44610fbeb1/WordPress/src/main/java/org/wordpress/android/widgets/NestedWebView.kt
package org.wordpress.android.widgets

import android.annotation.SuppressLint
import android.content.Context
import android.util.AttributeSet
import android.view.MotionEvent
import androidx.core.view.NestedScrollingChild3
import androidx.core.view.NestedScrollingChildHelper
import androidx.core.view.ViewCompat
import org.wordpress.android.ui.WPWebView
import android.R as AndroidR

class NestedWebView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = AndroidR.attr.webViewStyle
) : WPWebView(context, attrs, defStyleAttr), NestedScrollingChild3 {
    private var lastY = 0
    private val scrollOffset = IntArray(2)
    private val scrollConsumed = IntArray(2)
    private var nestedOffsetY = 0
    private val nestedScrollingChildHelper: NestedScrollingChildHelper = NestedScrollingChildHelper(this)

    override fun dispatchNestedPreFling(velocityX: Float, velocityY: Float): Boolean {
        return nestedScrollingChildHelper.dispatchNestedPreFling(velocityX, velocityY)
    }

    init {
        isNestedScrollingEnabled = true
    }
}
