/// Compile-time configuration, supplied via `--dart-define` at build time. Example:
///   flutter build web \
///     --dart-define=API_BASE_URL=https://api.curia-augur.<your-domain> \
///     --dart-define=COGNITO_USER_POOL_ID=us-east-1_xxx \
///     --dart-define=COGNITO_CLIENT_ID=xxxx
class Config {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );

  static const String cognitoUserPoolId = String.fromEnvironment(
    'COGNITO_USER_POOL_ID',
    defaultValue: '',
  );

  static const String cognitoClientId = String.fromEnvironment(
    'COGNITO_CLIENT_ID',
    defaultValue: '',
  );

  /// GeoJSON boundary files are hosted alongside the web app (same CloudFront
  /// origin) under /geo/. The nearest boundary year is chosen per REQ UI-4.
  static const String geoBasePath = String.fromEnvironment(
    'GEO_BASE_PATH',
    defaultValue: '/geo',
  );

  /// Full local mode (mirrors the backend CURIA_LOCAL flag). Set with:
  ///   flutter run --dart-define=LOCAL=true
  /// When true, EVERYTHING that would come from the API comes from bundled assets
  /// instead: the file list, every analysis file and the GeoJSON. No API/auth at all.
  /// Populate the assets with tools/prepare_local_ui_assets.py.
  static const bool local = bool.fromEnvironment('LOCAL', defaultValue: false);

  /// Optional: preselect a single bundled analysis file. Implies local mode.
  ///   --dart-define=LOCAL_FILENAME=analysis-....json
  static const String localFilename = String.fromEnvironment(
    'LOCAL_FILENAME',
    defaultValue: '',
  );

  static bool get isLocal => local || localFilename.isNotEmpty;

  /// Skip the Cognito login screen (e.g. developing against a localhost API with no
  /// authorizer). Set with --dart-define=SKIP_AUTH=true. Bundled-asset local mode
  /// (LOCAL_FILENAME) already implies this.
  static const bool skipAuth = bool.fromEnvironment(
    'SKIP_AUTH',
    defaultValue: false,
  );

  /// Whether the login screen / Cognito flow is required at all.
  static bool get requiresAuth => !isLocal && !skipAuth;

  static String get filesEndpoint => '$apiBaseUrl/files';
}
