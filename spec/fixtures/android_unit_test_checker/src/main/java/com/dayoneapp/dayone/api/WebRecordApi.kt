package com.dayoneapp.dayone.api

import com.dayoneapp.dayone.domain.sync.WebRecordRemote
import com.google.gson.annotations.SerializedName
import retrofit2.Response
import retrofit2.http.*

@JvmInline
value class CursorTime(
    val time: String,
)

val ZeroCursorTime = CursorTime("0")

data class WebRecordChanges(
    @SerializedName("changes")
    val changes: List<WebRecordRemote>,
    @SerializedName("cursor")
    val cursor: String,
)

interface WebRecordApi {
    @POST("$SYNC/named/{name}")
    suspend fun createRecord(
        @Path("name") name: String,
        @Body record: WebRecordRemote,
    ): Response<WebRecordRemote>

    @PUT("$SYNC/{syncId}")
    suspend fun updateRecord(
        @Path("syncId") syncId: String,
        @Body record: WebRecordRemote,
    ): Response<WebRecordRemote>

    @GET("$SYNC/named/{name}")
    suspend fun fetchRecord(
        @Path("name") name: String,
    ): Response<WebRecordRemote>

    @GET("$SYNC/changes/{kind}")
    suspend fun fetchRecordChanges(
        @Path("kind") kind: String,
        @Query("cursor") cursor: CursorTime,
    ): Response<WebRecordChanges>

    companion object {
        const val SYNC = "/api/v4/sync"
    }
}
