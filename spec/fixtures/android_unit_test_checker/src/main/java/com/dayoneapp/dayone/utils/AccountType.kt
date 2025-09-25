package com.dayoneapp.dayone.utils

enum class AccountType(
    val key: String,
) {
    DAY_ONE("Day One"),
    GOOGLE("Google"),
    APPLE("Apple ID"),
    ;

    companion object {
        @JvmStatic
        fun fromString(key: String): AccountType = values().find { it.key == key }!!
    }
}
