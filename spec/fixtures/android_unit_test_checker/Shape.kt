open class Polygon(sides: Int): Shape {
    override fun draw() {
        for (i in 1..sides)
            draw()
    }
}

abstract class Shape {
    abstract fun draw()
}
