package com.dayoneapp.dayone.utils.usecase

import android.content.Context
import android.content.Intent
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts.GetContent
import androidx.activity.result.contract.ActivityResultContracts.GetMultipleContents
import androidx.fragment.app.Fragment
import com.dayoneapp.dayone.utils.UriWrapper
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import javax.inject.Inject

class SelectPhotoUseCase
    @Inject
    constructor() {
        private lateinit var getContent: ActivityResultLauncher<String>
        private val _mediaUris = MutableSharedFlow<List<UriWrapper>>(extraBufferCapacity = 5)
        val mediaUris = _mediaUris.asSharedFlow()

        fun onCreate(
            fragment: Fragment,
            singlePhoto: Boolean = false,
        ) {
            getContent =
                if (singlePhoto) {
                    fragment.registerForActivityResult(GetSingleImage()) { uri ->
                        uri?.let {
                            _mediaUris.tryEmit(listOf(UriWrapper(it)))
                        }
                    }
                } else {
                    fragment.registerForActivityResult(GetMultipleImages()) { uris ->
                        _mediaUris.tryEmit(uris.map { UriWrapper(it) })
                    }
                }
        }

        fun selectPhotos() {
            getContent.launch("image/*")
        }

        private class GetMultipleImages : GetMultipleContents() {
            // Required to remove a lint error due to this method no longer calling super.createIntent()
            @Suppress("MissingSuperCall")
            override fun createIntent(
                context: Context,
                input: String,
            ): Intent =
                Intent(
                    Intent.ACTION_PICK,
                    android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                ).setType(input)
                    .putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                    .apply {
                        putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/jpeg", "image/png", "image/jpg"))
                    }
        }

        private class GetSingleImage : GetContent() {
            // Required to remove a lint error due to this method no longer calling super.createIntent()
            @Suppress("MissingSuperCall")
            override fun createIntent(
                context: Context,
                input: String,
            ): Intent =
                Intent(
                    Intent.ACTION_PICK,
                    android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                ).setType(input)
                    .apply {
                        putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/jpeg", "image/png", "image/jpg"))
                    }
        }
    }
    