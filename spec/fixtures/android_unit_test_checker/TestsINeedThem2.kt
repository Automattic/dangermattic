public open class TestsINeedThem2 {
    fun testMe2() {
    }
}

class TestsINeedThem2AnotherClass
{
    fun thisNeedsATest()
    {
        println("thisNeedsATest")
    }
}

enum class ProtocolState {
    WAITING {
        override fun signal() = TALKING
    },

    TALKING {
        override fun signal() = WAITING
    };

    abstract fun signal(): ProtocolState
}

value class Password(private val s: String)

sealed class Error(val message: String) {
    class NetworkError : Error("Network failure")
    class DatabaseError : Error("Database cannot be reached")
    class UnknownError : Error("An unknown error has occurred")
}
