import Flutter
import StripeTerminal
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let tapToPayChannel = "nexora/tap_to_pay"
  private let tapToPayBridge = NexoraTapToPayBridge()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NexoraTapToPayBridge") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: tapToPayChannel,
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler(tapToPayBridge.handle)
  }
}

private final class NexoraTapToPayBridge: NSObject, ConnectionTokenProvider, DiscoveryDelegate,
  TapToPayReaderDelegate, TerminalDelegate
{
  private var queuedConnectionToken: String?
  private var discoveredReaders: [Reader] = []
  private var discoveryTask: Task<Void, Never>?

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "checkAvailability":
      handleCheckAvailability(result: result)
    case "startPayment":
      handleStartPayment(call.arguments, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func fetchConnectionToken(_ completion: @escaping ConnectionTokenCompletionBlock) {
    guard let token = queuedConnectionToken, token.isEmpty == false else {
      completion(nil, bridgeError("Token di connessione Stripe Terminal non disponibile."))
      return
    }
    completion(token, nil)
  }

  func terminal(_ terminal: Terminal, didUpdateDiscoveredReaders readers: [Reader]) {
    discoveredReaders = readers
  }

  func terminal(_ terminal: Terminal, didChangeConnectionStatus status: ConnectionStatus) {}

  func terminal(_ terminal: Terminal, didChangePaymentStatus status: PaymentStatus) {}

  func reader(_ reader: Reader, didDisconnect reason: DisconnectReason) {}

  func reader(
    _ reader: Reader,
    didStartReconnect cancelable: Cancelable,
    disconnectReason: DisconnectReason
  ) {}

  func readerDidSucceedReconnect(_ reader: Reader) {}

  func readerDidFailReconnect(_ reader: Reader) {}

  func tapToPayReader(
    _ reader: Reader,
    didStartInstallingUpdate update: ReaderSoftwareUpdate,
    cancelable: Cancelable?
  ) {}

  func tapToPayReader(_ reader: Reader, didReportReaderSoftwareUpdateProgress progress: Float) {}

  func tapToPayReader(
    _ reader: Reader,
    didFinishInstallingUpdate update: ReaderSoftwareUpdate?,
    error: Error?
  ) {}

  func tapToPayReader(_ reader: Reader, didRequestReaderInput inputOptions: ReaderInputOptions) {}

  func tapToPayReader(
    _ reader: Reader,
    didRequestReaderDisplayMessage displayMessage: ReaderDisplayMessage
  ) {}

  func tapToPayReaderDidAcceptTermsOfService(_ reader: Reader) {}

  func tapToPayReader(
    _ reader: Reader,
    didRequestPaymentMethodSelection paymentIntent: PaymentIntent,
    availablePaymentOptions: [PaymentOption],
    completion: @escaping PaymentMethodSelectionCompletionBlock
  ) {
    completion(availablePaymentOptions.first, nil)
  }

  func tapToPayReader(
    _ reader: Reader,
    didRequestQrCodeDisplay paymentIntent: PaymentIntent,
    qrData: QrCodeDisplayData,
    completion: @escaping QrCodeDisplayCompletionBlock
  ) {
    completion(nil)
  }

  private func handleCheckAvailability(result: @escaping FlutterResult) {
    guard UIDevice.current.userInterfaceIdiom == .phone else {
      result([
        "supported": false,
        "platform": "ios",
        "reason": "Tap to Pay su iPhone richiede un iPhone compatibile.",
      ])
      return
    }

    #if targetEnvironment(simulator)
      result([
        "supported": true,
        "platform": "ios",
        "reason": "Modalita simulata attiva nel simulatore iOS.",
      ])
      return
    #else
      guard #available(iOS 16.4, *) else {
        result([
          "supported": false,
          "platform": "ios",
          "reason": "Tap to Pay richiede iOS 16.4 o superiore su iPhone.",
        ])
        return
      }
      result([
        "supported": true,
        "platform": "ios",
        "reason": "Tap to Pay pronto. Serve entitlement Apple attivo sul profilo di firma per i pagamenti reali.",
      ])
    #endif
  }

  private func handleStartPayment(_ arguments: Any?, result: @escaping FlutterResult) {
    guard
      let args = arguments as? [String: Any],
      let connectionToken = args["connectionToken"] as? String,
      let session = args["session"] as? [String: Any]
    else {
      result(
        FlutterError(
          code: "invalid_arguments",
          message: "Parametri Tap to Pay non validi.",
          details: nil
        )
      )
      return
    }

    guard
      let clientSecret = session["clientSecret"] as? String,
      clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    else {
      result(
        FlutterError(
          code: "missing_client_secret",
          message: "Client secret Stripe mancante.",
          details: nil
        )
      )
      return
    }

    guard
      let locationId = (session["terminalLocationId"] as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
      locationId.isEmpty == false
    else {
      result(
        FlutterError(
          code: "missing_terminal_location",
          message: "Location Stripe Terminal mancante. Completa la configurazione POS del team.",
          details: nil
        )
      )
      return
    }

    queuedConnectionToken = connectionToken

    Task { @MainActor in
      do {
        try self.ensureTerminalInitialized()
        let reader = try await self.ensureConnectedReader(for: session, locationId: locationId)
        let paymentIntent = try await self.retrievePaymentIntent(clientSecret: clientSecret)
        _ = try await Terminal.shared.collectPaymentMethod(paymentIntent)
        let confirmedIntent = try await Terminal.shared.confirmPaymentIntent(paymentIntent)
        result([
          "ok": true,
          "reader": [
            "serialNumber": reader.serialNumber,
            "simulated": reader.simulated,
            "locationId": reader.locationId ?? locationId,
          ],
          "paymentIntentId": confirmedIntent.stripeId,
          "status": "confirmed",
        ])
      } catch {
        result(
          FlutterError(
            code: "tap_to_pay_failed",
            message: self.userFacingMessage(for: error),
            details: String(describing: error)
          )
        )
      }
    }
  }

  @MainActor
  private func ensureTerminalInitialized() throws {
    if Terminal.isInitialized() {
      Terminal.shared.delegate = self
      Terminal.shared.logLevel = .verbose
      return
    }
    Terminal.initWithTokenProvider(
      self,
      delegate: self,
      offlineDelegate: nil,
      logLevel: .verbose
    )
  }

  @MainActor
  private func ensureConnectedReader(for session: [String: Any], locationId: String) async throws -> Reader {
    if let connected = Terminal.shared.connectedReader {
      if connected.locationId == locationId || connected.locationId?.isEmpty != false {
        return connected
      }
      try await disconnectReaderIfNeeded()
    }

    let reader = try await discoverReader()
    let companyName = (session["companyName"] as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let accountId = (session["connectedAccountId"] as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)

    let builder = TapToPayConnectionConfigurationBuilder(delegate: self, locationId: locationId)
      .setMerchantDisplayName(companyName?.isEmpty == false ? companyName : "Nexora")
      .setTosAcceptancePermitted(true)
      .setReturnReadResultImmediatelyEnabled(true)
      .setAutoReconnectOnUnexpectedDisconnect(true)
    if let accountId, accountId.isEmpty == false {
      _ = builder.setOnBehalfOf(accountId)
    }
    let config = try builder.build()

    return try await withCheckedThrowingContinuation { continuation in
      Terminal.shared.connectReader(reader, connectionConfig: config) { connectedReader, error in
        if let error {
          continuation.resume(throwing: error)
        } else if let connectedReader {
          continuation.resume(returning: connectedReader)
        } else {
          continuation.resume(throwing: self.bridgeError("Reader Tap to Pay non disponibile."))
        }
      }
    }
  }

  @MainActor
  private func discoverReader() async throws -> Reader {
    discoveryTask?.cancel()
    discoveredReaders = []

    let config = try TapToPayDiscoveryConfigurationBuilder()
      .setSimulated(isSimulator)
      .build()

    let stream = Terminal.shared.discoverReaders(config)
    for try await readers in stream {
      discoveredReaders = readers
      if let reader = readers.first {
        discoveryTask?.cancel()
        return reader
      }
    }
    throw bridgeError("Nessun reader Tap to Pay disponibile su questo dispositivo.")
  }

  @MainActor
  private func retrievePaymentIntent(clientSecret: String) async throws -> PaymentIntent {
    try await withCheckedThrowingContinuation { continuation in
      Terminal.shared.retrievePaymentIntent(clientSecret: clientSecret) { paymentIntent, error in
        if let error {
          continuation.resume(throwing: error)
        } else if let paymentIntent {
          continuation.resume(returning: paymentIntent)
        } else {
          continuation.resume(
            throwing: self.bridgeError("Impossibile recuperare il PaymentIntent Stripe.")
          )
        }
      }
    }
  }

  @MainActor
  private func disconnectReaderIfNeeded() async throws {
    guard Terminal.shared.connectedReader != nil else { return }
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      Terminal.shared.disconnectReader { error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: ())
        }
      }
    }
  }

  private var isSimulator: Bool {
    #if targetEnvironment(simulator)
      true
    #else
      false
    #endif
  }

  private func bridgeError(_ message: String) -> NSError {
    NSError(domain: "app.nexora.tapToPay", code: 1, userInfo: [
      NSLocalizedDescriptionKey: message,
    ])
  }

  private func userFacingMessage(for error: Error) -> String {
    let nsError = error as NSError
    let message = nsError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    if message.isEmpty == false {
      return message
    }
    return "Pagamento Tap to Pay non completato."
  }
}
