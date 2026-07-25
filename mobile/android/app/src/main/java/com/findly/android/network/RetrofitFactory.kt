package com.findly.android.network

import com.jakewharton.retrofit2.converter.kotlinx.serialization.asConverterFactory
import com.findly.android.auth.AuthProvider
import java.util.concurrent.TimeUnit
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import retrofit2.Retrofit

/** Builds the [FindlyApiService] Retrofit client. `baseUrl` is `AppConfig.baseUrl`
 * (`{scheme}://{host}/api/`, specs/003-android-client.md §5/§13) — never hardcoded here. */
object RetrofitFactory {

    fun create(baseUrl: String, authProvider: AuthProvider): FindlyApiService {
        val okHttpClient = OkHttpClient.Builder()
            .addInterceptor(AuthInterceptor(authProvider))
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(15, TimeUnit.SECONDS)
            .writeTimeout(15, TimeUnit.SECONDS)
            .build()

        val contentType = "application/json".toMediaType()

        val retrofit = Retrofit.Builder()
            .baseUrl(baseUrl)
            .client(okHttpClient)
            .addConverterFactory(FindlyJson.asConverterFactory(contentType))
            .build()

        return retrofit.create(FindlyApiService::class.java)
    }
}
