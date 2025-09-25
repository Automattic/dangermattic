package com.dayoneapp.mediastorage

import android.graphics.Bitmap

@JvmInline
value class CompressQuality(
    val value: Int,
) {
    init {
        require(value in 1..100) { }
    }
}

class MediaStorageConfiguration(
    val mediaPath: String,
    val externalImagesPath: String,
    val externalVideosPath: String,
    val externalAudiosPath: String,
    val externalDocumentsPath: String,
    val avatarsPath: String,
    val thumbnailsConfiguration: ThumbnailsConfiguration,
)

class ThumbnailsConfiguration(
    val thumbnailsPath: String,
    val height: Int,
    val width: Int,
    val extension: String,
    val compression: Bitmap.CompressFormat,
    val quality: CompressQuality,
)
