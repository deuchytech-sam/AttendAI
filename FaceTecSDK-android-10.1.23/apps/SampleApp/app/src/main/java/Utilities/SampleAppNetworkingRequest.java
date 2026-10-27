package Utilities;

import android.graphics.BitmapFactory;
import android.os.Handler;
import android.os.Looper;
import android.util.Base64;
import android.util.Log;

import androidx.annotation.NonNull;

import com.facetec.sampleapp.Config;
import com.facetec.sampleapp.SampleAppActivity;
import com.facetec.sampleapp.SampleAppOfficialIDPhotoFragment;
import com.facetec.sampleapp.SessionRequestProcessor;
import com.facetec.sdk.FaceTecSDK;
import com.facetec.sdk.FaceTecSessionRequestProcessor;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.IOException;

import okhttp3.Call;
import okhttp3.MediaType;
import okhttp3.Request;
import okhttp3.RequestBody;

// Sample class for handling networking calls needed in order for FaceTec to function correctly.
// In Your App, please use the networking constructs and protocols that meet your security requirements.
//
// Notes:
// - Adding additional logic to this code is not allowed.  Do not add any additional logic outside of what is demonstrated in this Sample.
// - Adding additional asynchronous calls to this code is not allowed.  Only make your own additional asynchronous calls once the FaceTec UI is closed.
// - Adding code that modifies any App UI (Yours or FaceTec's) is not allowed.  Only add code that modifies your own App UI once the FaceTec UI is closed.
public class SampleAppNetworkingRequest {
    private static int ERROR_COUNT = 0;
    private static final int MAX_ERROR_RETRIES = 4;

    public static void send(
            @NonNull SessionRequestProcessor referencingProcessor,
            @NonNull String sessionRequestBlob,
            @NonNull FaceTecSessionRequestProcessor.Callback sessionRequestCallback
    ) {
        //
        // Step 1: Construct the payload.
        //
        // - The payload contains the Session Request Blob
        // - Please see the notes below about correctly handling externalDatabaseRefID for certain call types.
        //
        JSONObject sessionRequestCallPayload = new JSONObject();
        ERROR_COUNT = 0;

        try {
            sessionRequestCallPayload.put("requestBlob", sessionRequestBlob);

            // Please see extensive notes in SampleAppActivity for more details.
            // externalDatabaseRefID is included in FaceTec Device SDK Sample App Code for demonstration purposes.
            // In Your App, you will be setting and handling this in Your Webservice code.
            if (!SampleAppActivity.demonstrationExternalDatabaseRefID.isEmpty()) {
                sessionRequestCallPayload.put("externalDatabaseRefID", SampleAppActivity.demonstrationExternalDatabaseRefID);
            }
        }
        catch (JSONException e) {
            e.printStackTrace();
        }

        RequestBody requestBody = RequestBody.create(MediaType.parse("application/json; charset=utf-8"), sessionRequestCallPayload.toString());

        //
        // Step 2: Set up the networking request.
        //
        // - This Sample App demonstrates making calls to the FaceTec Testing API by default.
        // - In Your App, please use the webservice endpoint you have set up that accepts networking requests from Your App.
        // - In Your Webservice, build an endpoint that takes incoming requests, and forwards them to FaceTec Server.
        // - This code should never call your server directly. It should contact middleware you have created that forwards requests to your server.
        //

        Request request = new Request.Builder()
                .url(Config.YOUR_API_OR_FACETEC_TESTING_API_ENDPOINT)
                .header("Content-Type", "application/json")

                // Developer Note: This is ONLY needed for calls to the FaceTec Testing API.
                // You should remove this when using Your App connected to Your Webservice + FaceTec Server
                .header("X-Device-Key", Config.DeviceKeyIdentifier)

                // Developer Note: This is ONLY needed for calls to the FaceTec Testing API.
                // You should remove this when using Your App connected to Your Webservice + FaceTec Server
                .header( "X-Testing-API-Header", FaceTecSDK.getTestingAPIHeader())

                // Developer Note: With the Sample Networking library in this Sample App,
                // this code demonstrates getting the networking request progress and making
                // the appropriate call in the FaceTec Device SDK to update the upload progress.
                // This is how the FaceTec Upload Progress Bar gets changed.
                .post(new ProgressRequestBody(requestBody,
                        (bytesWritten, totalBytes) -> {
                            final float uploadProgressPercent = ((float) bytesWritten) / ((float) totalBytes);
                            referencingProcessor.onUploadProgress(uploadProgressPercent, sessionRequestCallback);
                        }))
                .build();

        //
        // Step 3: Make the API Call, and handle the response.
        //
        // - Unless there is a networking error, or an error in your webservice or infrastructure, the Response Blob is retrieved and passed back into processResponse.
        // - For error cases, abortOnCatastrophicError is called as this would indicate a networking issue on the User device or network, or an error in Your Webservice.
        //

        doSessionRequestWithRetry(request, new okhttp3.Callback() {
            @Override
            public void onResponse(@NonNull Call call, @NonNull okhttp3.Response response) throws IOException {
                //
                // Step 4:  Get the Response Blob and call processResponse on the Session Request Callback.
                //
                // - Call a convenience function that either gets a valid Response Blob, or handles the error and returns null.
                // - Checks for null, indicating an error was detected and handled.
                //
                String responseBlob = getResponseBlobOrHandleError(response, referencingProcessor, sessionRequestCallback);
                if (responseBlob != null) {
                    referencingProcessor.onResponseBlobReceived(responseBlob, sessionRequestCallback);
                }
            }

            @Override
            public void onFailure(@NonNull Call call, @NonNull IOException e) {
                // On catastrophic error, call the onCatastrophicNetworkError handler
                // This should never be called except when a hard server error occurs. For example the user loses network connectivity.
                // You may want to implement some sort of retry logic here
                Log.d("FaceTecSDKSampleApp", "Exception raised while attempting HTTPS call.");

                referencingProcessor.onCatastrophicNetworkError(sessionRequestCallback);
            }
        });
    }

    private static void doSessionRequestWithRetry(Request request, okhttp3.Callback sessionRequestCallback) {
        SampleAppNetworkingLibExample.getApiClient().newCall(request).enqueue(new okhttp3.Callback() {
            @Override
            public void onResponse(@NonNull Call call, @NonNull okhttp3.Response response) throws IOException {
               sessionRequestCallback.onResponse(call, response);
            }

            @Override
            public void onFailure(@NonNull Call call, @NonNull IOException e) {
                if (SampleAppNetworkingRequest.ERROR_COUNT < SampleAppNetworkingRequest.MAX_ERROR_RETRIES) {
                    SampleAppNetworkingRequest.ERROR_COUNT += 1;
                    // After a delay, try again
                    new Handler(Looper.getMainLooper()).postDelayed(() ->
                            doSessionRequestWithRetry(request, sessionRequestCallback),
                        getSessionRequestRetryDelay());
                }
                else {
                    sessionRequestCallback.onFailure(call, e);
                }
            }
        });
    }

    //
    // Gets the time to delay before attempting the Session Request again in the event of a networking-related issue.
    //
    // - In the event of a networking-related issue or webservice error, the network request should be attempted again, multiple times,
    // with additional delays, in order to overcome temporary loss-of-network issues for the User, or issues where your webserver is temporarily unavailable.
    //

    private static int getSessionRequestRetryDelay() {
        if (SampleAppNetworkingRequest.ERROR_COUNT == 1) {
            return 0;
        }
        else if (SampleAppNetworkingRequest.ERROR_COUNT == 2) {
            return 2000;
        }
        else if (SampleAppNetworkingRequest.ERROR_COUNT == 3) {
            return 5000;
        }
        else if (SampleAppNetworkingRequest.ERROR_COUNT == 4) {
            return 10000;
        }
        else {
            return 0;
        }
    }

    static String getResponseBlobOrHandleError(okhttp3.Response response, SessionRequestProcessor referencingProcessor, @NonNull FaceTecSessionRequestProcessor.Callback sessionRequestCallback) throws IOException {
        // On request completion, validate the request status, parse the response and return the data
        if (response.isSuccessful() && response.body() != null) {
            try {
                JSONObject responseJSON = new JSONObject(response.body().string());

                // Developer Note:  This is a special case for Official ID Photo Mode.
                // To demonstrate behavior in the Sample App where the Official ID Photo is shown to the UI,
                // here we store that off if it exists for future code to handle.
                storeOfficialIDPhotoIfApplicable(responseJSON, referencingProcessor, response, sessionRequestCallback);

                String responseBlob = responseJSON.getString("responseBlob");
                response.close();
                return responseBlob;
            }
            catch (JSONException e) {
                logErrorAndCallAbortAndClose("JSON Parsing Failed.  This indicates an issue in your own webservice or API contracts.", referencingProcessor, response, sessionRequestCallback);
            }
        }
        else {
            logErrorAndCallAbortAndClose("API Response not successful.  Inspect network request and response for more details.", referencingProcessor, response, sessionRequestCallback);
        }

        return null;
    }

    static void logErrorAndCallAbortAndClose(String errorDetail, SessionRequestProcessor referencingProcessor, okhttp3.Response response, @NonNull FaceTecSessionRequestProcessor.Callback sessionRequestCallback) {
        Log.d("FaceTecSDKSampleApp", "Networking Exception raised while attempting HTTPS call. Details: " + errorDetail);
        referencingProcessor.onCatastrophicNetworkError(sessionRequestCallback);
        response.close();
    }

    static void storeOfficialIDPhotoIfApplicable(JSONObject responseJSON, SessionRequestProcessor referencingProcessor, okhttp3.Response response, @NonNull FaceTecSessionRequestProcessor.Callback sessionRequestCallback) {
        // Retrieve the Official ID Photo if it exists in the response
        if (!responseJSON.has("result")) {
            return;
        }

        try {
            JSONObject result = responseJSON.getJSONObject("result");

            if (result.has("officialIDPhotoImage")) {
                String photo = result.getString("officialIDPhotoImage");

                if (!photo.isEmpty()) {
                    byte[] decodedBytes = Base64.decode(photo, Base64.DEFAULT);
                    SampleAppOfficialIDPhotoFragment.latestOfficialIDPhoto = BitmapFactory.decodeByteArray(decodedBytes, 0, decodedBytes.length);
                }
            }
        }
        catch (JSONException e) {
            logErrorAndCallAbortAndClose("JSON Parsing Failed.  This indicates an issue in your own webservice or API contracts.", referencingProcessor, response, sessionRequestCallback);
        }
    }
}