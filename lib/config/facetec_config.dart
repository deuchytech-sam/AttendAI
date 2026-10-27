class FaceTecConfig {
  /// Your FaceTec Device Key Identifier from dev.facetec.com
  /// This identifies your application to the FaceTec service
  static const String deviceKeyIdentifier = 'drsq1UUBNCB0IshWhkFSrin3vmintUzg';

  /// FaceTec API base URL
  /// Default: https://api.facetec.com/v1
  /// Override via FACETEC_API_BASE_URL in Firebase Functions config if your tenant uses a custom endpoint
  static const String baseURL = 'https://api.facetec.com/v1';

  /// FaceScan Encryption Public Key
  /// Obtain this from your FaceTec developer console
  /// This key encrypts the FaceMap data before sending to FaceTec servers
  static const String publicFaceScanEncryptionKey = '''
-----BEGIN PUBLIC KEY-----
YOUR_PUBLIC_KEY_HERE
-----END PUBLIC KEY-----''';

  /// Application name for logging/debugging
  static const String appName = 'AttendAI';
}