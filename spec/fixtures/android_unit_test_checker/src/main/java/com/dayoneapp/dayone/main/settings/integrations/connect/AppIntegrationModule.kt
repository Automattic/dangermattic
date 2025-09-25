package com.dayoneapp.dayone.main.settings.integrations.connect

import com.dayoneapp.dayone.main.settings.integrations.IntegrationAppId
import com.dayoneapp.dayone.main.settings.integrations.strava.StravaAppIntegrationHandler
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Qualifier
import javax.inject.Singleton
import kotlin.jvm.JvmWildcard

@Qualifier
@Retention(AnnotationRetention.BINARY)
annotation class AppIntegrationHandlers

@Module
@InstallIn(SingletonComponent::class)
internal object AppIntegrationModule {
    @Provides
    @Singleton
    @AppIntegrationHandlers
    fun provideAppIntegrationHandlers(
        stravaAppIntegrationHandler: StravaAppIntegrationHandler,
    ): Map<IntegrationAppId, @JvmWildcard AppIntegrationHandler> =
        mapOf(
            IntegrationAppId.STRAVA to stravaAppIntegrationHandler,
        )
}
