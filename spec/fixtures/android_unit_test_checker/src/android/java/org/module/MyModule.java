package src.android.java.org.module;

import dagger.hilt.components.SingletonComponent;
import dagger.android.AndroidInjectionModule;

@InstallIn(SingletonComponent.class)
@Module(includes = AndroidInjectionModule.class)
public class MyModule {
    @Provides
    public static SharedPreferences provideSharedPrefs(@ApplicationContext Context context) {
        return PreferenceManager.getDefaultSharedPreferences(context);
    }
}
