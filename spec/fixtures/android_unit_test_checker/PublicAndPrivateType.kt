class PublicType {
    fun print() = "Hello, ${PrivateType().print()}!"
}

private class PrivateType {
    fun print() = "World"
}
