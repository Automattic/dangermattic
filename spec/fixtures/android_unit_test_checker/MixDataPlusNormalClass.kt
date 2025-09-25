import javax.inject.Inject
import javax.inject.Singleton

internal data class DummyDataClassNotNeedingTests(
    val title: String,
    val id: String
)

@Singleton
internal class DummyClassMissingTest @Inject constructor(
    private val name: String,
) : ParentClass {
    private val loggingTag = 'mylogging'
}
