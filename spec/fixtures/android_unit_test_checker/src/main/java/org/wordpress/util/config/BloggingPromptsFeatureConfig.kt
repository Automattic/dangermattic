// Taken from https://github.com/wordpress-mobile/WordPress-Android/blob/44282b137085ec230771fc2c87ad9a44610fbeb1/WordPress/src/main/java/org/wordpress/android/util/config/BloggingPromptsFeatureConfig.kt
package org.wordpress.android.util.config

import org.wordpress.android.BuildConfig
import org.wordpress.android.annotation.Feature
import org.wordpress.android.util.config.BloggingPromptsFeatureConfig.Companion.BLOGGING_PROMPTS_REMOTE_FIELD
import javax.inject.Inject

@Feature(BLOGGING_PROMPTS_REMOTE_FIELD, true)
class BloggingPromptsFeatureConfig
@Inject constructor(appConfig: AppConfig) : FeatureConfig(
    appConfig,
    BuildConfig.BLOGGING_PROMPTS,
    BLOGGING_PROMPTS_REMOTE_FIELD
) {
    override fun isEnabled(): Boolean {
        return super.isEnabled() && BuildConfig.IS_JETPACK_APP
    }

    companion object {
        const val BLOGGING_PROMPTS_REMOTE_FIELD = "blogging_prompts_remote_field"
    }
}
