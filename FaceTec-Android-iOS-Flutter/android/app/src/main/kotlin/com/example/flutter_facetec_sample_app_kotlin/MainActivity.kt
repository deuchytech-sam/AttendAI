package com.example.flutter_facetec_sample_app_kotlin

import android.util.Log
import androidx.annotation.NonNull
import com.facetec.sdk.FaceTecCustomization
import com.facetec.sdk.FaceTecInitializationError
import com.facetec.sdk.FaceTecSDK
import com.facetec.sdk.FaceTecSDKInstance
import com.facetec.sdk.FaceTecSessionRequestProcessor
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), FaceTecSessionRequestProcessor {
    companion object {
        private const val CHANNEL = "com.facetec.sdk"
        private const val PROCESSOR_CHANNEL = "com.facetec.sdk/livenesscheck"
        private var initializeResultCallback: MethodChannel.Result? = null
    }

    private var faceTecSDKInstance: FaceTecSDKInstance? = null
    private var latestExternalDatabaseRefID = ""
    private lateinit var processorChannel: MethodChannel
    private lateinit var requestCallback: FaceTecSessionRequestProcessor.Callback

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val sdkChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        processorChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PROCESSOR_CHANNEL)
        sdkChannel.setMethodCallHandler(::receivedFaceTecSDKMethodCall)
        processorChannel.setMethodCallHandler(::receivedLivenessCheckProcessorCall)
   }

    private fun receivedFaceTecSDKMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> {
                val deviceKeyIdentifier = call.argument<String>("deviceKeyIdentifier")
                val publicFaceScanEncryptionKey = call.argument<String>("publicFaceScanEncryptionKey")

                if (deviceKeyIdentifier != null && publicFaceScanEncryptionKey != null) {
                    initialize(deviceKeyIdentifier, publicFaceScanEncryptionKey, result)
                }
                else {
                    result.error("InvalidArguments", "Missing deviceKeyIdentifier or publicFaceScanEncryptionKey", null)
                }
            }
            "startLivenessCheck" -> {
                startLivenessCheck(result)
            }
            "createAPIUserAgentString" -> {
                result.success(FaceTecSDK.getTestingAPIHeader())
            }
        else -> result.notImplemented()
        }

    }

    private fun receivedLivenessCheckProcessorCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "abortOnCatastrophicError" -> {
                onCatastrophicNetworkError()
            }
            "onResponseBlobReceived" -> {
                val responseBlob = call.argument<String>("responseBlob")

                if (responseBlob != null) {
                    onResponseBlobReceived(responseBlob)
                }
                else {
                    result.error("InvalidArguments", "Missing arguments for onResponseBlobReceived", null)
                    return
                }
            }
            "onUploadProgress" -> {
                call.argument<Float>("progress")?.let {
                    onUploadProgress(it)
                }
            }
            else -> {
                result.notImplemented()
                return
            }
        }

        result.success(null)
    }

    private fun initialize(deviceKeyIdentifier: String, publicFaceScanEncryptionKey: String, result: MethodChannel.Result) {
        initializeResultCallback = result
        val customization = FaceTecCustomization().apply {
            overlayCustomization.brandingImage = R.drawable.flutter_logo
        }

        FaceTecSDK.setCustomization(customization)
        val initializeCallback = object : FaceTecSDK.InitializeCallback {
            override fun onSuccess(sdkInstance: FaceTecSDKInstance) {
                onFaceTecSDKInitializationSuccess(sdkInstance)
                initializeResultCallback?.success(true)
                initializeResultCallback = null
            }

            override fun onError(error: FaceTecInitializationError) {
                onFaceTecSDKInitializationFailure(error)
                initializeResultCallback?.error("Initialize Failure", "Unable to initialize FaceTec SDK", null)
                initializeResultCallback = null
            }
        }

        FaceTecSDK.initializeWithSessionRequest(this, deviceKeyIdentifier, this, initializeCallback)
    }

    private fun onFaceTecSDKInitializationSuccess(sdkInstance: FaceTecSDKInstance) {
        faceTecSDKInstance = sdkInstance
        Log.d("FaceTecSDKSampleApp", "Initialized Successfully.")
    }

    private fun onFaceTecSDKInitializationFailure(error: FaceTecInitializationError) {
        Log.d("FaceTecSDKSampleApp", error.toString())
    }

    private fun startLivenessCheck(result: MethodChannel.Result) {
        latestExternalDatabaseRefID = ""
        faceTecSDKInstance?.start3DLiveness(this, this)
        result.success(true)
    }

    override fun onSessionRequest(sessionRequestBlob: String, sessionRequestCallback: FaceTecSessionRequestProcessor.Callback) {
        requestCallback = sessionRequestCallback
        val args = hashMapOf<String, Any>(
            "sessionRequestBlob" to sessionRequestBlob,
            "externalDatabaseRefID" to latestExternalDatabaseRefID,
            "userAgentString" to FaceTecSDK.getTestingAPIHeader()
        )

        runOnUiThread {
            processorChannel.invokeMethod("processSession", args)
        }
    }

    fun onResponseBlobReceived(responseBlob: String) {
        requestCallback.processResponse(responseBlob)
    }

    fun onUploadProgress(progress: Float) {
        requestCallback.updateProgress(progress)
    }

    fun onCatastrophicNetworkError() {
        requestCallback.abortOnCatastrophicError()
    }
}