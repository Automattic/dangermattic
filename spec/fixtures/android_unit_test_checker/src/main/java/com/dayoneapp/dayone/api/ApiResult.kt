package com.dayoneapp.dayone.api

import com.dayoneapp.dayone.api.ApiResult.Failure
import com.dayoneapp.dayone.api.ApiResult.FailureType.GENERIC
import com.dayoneapp.dayone.api.ApiResult.FailureType.SERVER_ERROR
import com.dayoneapp.dayone.api.ApiResult.FailureType.TIMEOUT
import com.dayoneapp.dayone.api.ApiResult.FailureType.UNAUTHORIZED
import com.dayoneapp.syncservice.NetworkErrorType
import com.google.api.client.http.HttpStatusCodes
import retrofit2.Response
import java.io.IOException

sealed class ApiResult<T> {
    data class Success<T>(
        val data: T,
    ) : ApiResult<T>()

    class Empty<T> : ApiResult<T>()

    data class Failure<T>(
        val type: FailureType,
        val errorCode: Int? = null,
        val errorMessage: String? = null,
    ) : ApiResult<T>()

    enum class FailureType {
        SERVER_ERROR,
        UNAUTHORIZED,
        TIMEOUT,
        GENERIC,
        NOT_CONNECTED,
        ;

        companion object {
            fun fromNetworkErrorType(networkErrorType: NetworkErrorType): FailureType =
                when (networkErrorType) {
                    NetworkErrorType.SERVER_ERROR -> SERVER_ERROR
                    NetworkErrorType.UNAUTHORIZED -> UNAUTHORIZED
                    NetworkErrorType.TIMEOUT -> TIMEOUT
                    NetworkErrorType.GENERIC -> GENERIC
                    else -> {
                        GENERIC
                    }
                }
        }
    }
}

suspend fun <T> apiCall(apiCall: suspend () -> Response<T>): ApiResult<T> =
    try {
        with(apiCall()) {
            if (this.isSuccessful) {
                this.body()?.let {
                    ApiResult.Success(it)
                } ?: ApiResult.Empty()
            } else {
                val type =
                    when (this.code()) {
                        HttpStatusCodes.STATUS_CODE_UNAUTHORIZED, HttpStatusCodes.STATUS_CODE_FORBIDDEN -> UNAUTHORIZED
                        HttpStatusCodes.STATUS_CODE_SERVER_ERROR -> SERVER_ERROR
                        else -> GENERIC
                    }
                Failure(type, this.code(), this.message())
            }
        }
    } catch (e: IOException) {
        Failure(TIMEOUT)
    }
    