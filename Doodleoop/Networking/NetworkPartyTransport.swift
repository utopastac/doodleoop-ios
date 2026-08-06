import Foundation
import Network

/// Bonjour + TCP peer transport with length-prefixed JSON frames.
/// Host runs an `NWListener`; joiners browse and open `NWConnection`s.
///
/// On Simulator, Bonjour between instances is unreliable, so discovery uses a
/// shared file bridge under the Mac host home and TCP joins go over 127.0.0.1.
@MainActor
final class NetworkPartyTransport: PartyTransport {
  let serviceType: String
  let displayName: String

  weak var delegate: PartyTransportDelegate?

  private let queue = DispatchQueue(label: "co.utopastac.doodleoop.network")
  private var listener: NWListener?
  private var browser: NWBrowser?
  private var connections: [String: PeerConnection] = [:]
  private var endpointsByPeerId: [String: NWEndpoint] = [:]
  /// Simulator-only: loopback port for each discovered peer id.
  private var loopbackPortsByPeerId: [String: UInt16] = [:]
  private var discovered: [DiscoveredPeer] = []
  private var hostingInfo: [String: String] = [:]
  private var isHosting = false
  private var connectAttemptTasks: [String: Task<Void, Never>] = [:]

  #if targetEnvironment(simulator)
  private var simulatorDiscoveryTimer: Timer?
  #endif

  init(displayName: String, serviceType: String) {
    self.displayName = String(displayName.prefix(63))
    self.serviceType = serviceType
  }

  func startHosting(discoveryInfo: [String: String]) {
    stopBrowsingOnly()
    clearConnections()
    hostingInfo = discoveryInfo
    isHosting = true
    restartListener()
  }

  func refreshHosting(discoveryInfo: [String: String]) {
    var next = discoveryInfo
    #if targetEnvironment(simulator)
    if let port = hostingInfo["port"] {
      next["port"] = port
    }
    #endif
    hostingInfo = next
    isHosting = true
    if listener == nil {
      restartListener()
      return
    }
    #if targetEnvironment(simulator)
    publishBoundPortIfNeeded()
    #else
    listener?.service = NWListener.Service(
      name: Self.sanitizedServiceName(hostingInfo["room"] ?? displayName),
      type: "_\(serviceType)._tcp",
      txtRecord: NWTXTRecord(hostingInfo)
    )
    #endif
  }

  func startBrowsing() {
    #if targetEnvironment(simulator)
    Self.clearSimulatorHost(metadata: hostingInfo)
    #endif
    stopHostingOnly(preservingConnections: false)
    isHosting = false
    hostingInfo = [:]
    discovered = []
    endpointsByPeerId = [:]
    loopbackPortsByPeerId = [:]
    publishDiscovered()
    startBrowser()
  }

  func ensureBrowsing() {
    #if targetEnvironment(simulator)
    if simulatorDiscoveryTimer != nil {
      pollSimulatorHosts()
      return
    }
    #else
    guard browser == nil else { return }
    #endif
    startBrowser()
  }

  /// Browse without tearing down an active host listener (successor detection).
  func ensureBrowsingAlongsideHosting() {
    guard isHosting else {
      ensureBrowsing()
      return
    }
    #if targetEnvironment(simulator)
    if simulatorDiscoveryTimer != nil {
      pollSimulatorHosts()
      return
    }
    #else
    guard browser == nil else { return }
    #endif
    startBrowser()
  }

  func connect(to peer: DiscoveredPeer) {
    cancelConnectAttempts(for: peer.id)
    startConnection(to: peer, attempt: 0)
  }

  func send(_ data: Data, to peerKey: String?) {
    let framed = MessageFraming.encode(data)
    if let peerKey {
      connections[peerKey]?.send(framed)
    } else {
      for peer in connections.values {
        peer.send(framed)
      }
    }
  }

  func disconnectPeer(_ peerKey: String) {
    guard let peer = connections.removeValue(forKey: peerKey) else { return }
    peer.cancel()
    delegate?.transport(self, peer: peerKey, didChange: .notConnected)
  }

  func stop() {
    isHosting = false
    #if targetEnvironment(simulator)
    Self.clearSimulatorHost(metadata: hostingInfo)
    #endif
    stopHostingOnly(preservingConnections: false)
    stopBrowsingOnly()
    clearConnections()
    cancelAllConnectAttempts()
    discovered = []
    endpointsByPeerId = [:]
    loopbackPortsByPeerId = [:]
    hostingInfo = [:]
  }

  private func clearConnections() {
    for key in Array(connections.keys) {
      connections[key]?.cancel()
    }
    connections.removeAll()
  }

  // MARK: - Listener / browser

  private func restartListener() {
    let old = listener
    listener = nil
    old?.cancel()

    do {
      let parameters = Self.makeParameters()
      #if targetEnvironment(simulator)
      // Match joiner connects to 127.0.0.1. Safe because we skip Bonjour on Simulator.
      parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
        host: "127.0.0.1",
        port: .any
      )
      #endif
      let listener = try NWListener(using: parameters)
      #if targetEnvironment(simulator)
      // Bonjour between Simulator instances is flaky; discovery uses the file bridge.
      listener.service = nil
      #else
      listener.service = NWListener.Service(
        name: Self.sanitizedServiceName(hostingInfo["room"] ?? displayName),
        type: "_\(serviceType)._tcp",
        txtRecord: NWTXTRecord(hostingInfo)
      )
      #endif
      listener.stateUpdateHandler = { [weak self] state in
        Task { @MainActor in
          self?.handleListenerState(state)
        }
      }
      listener.newConnectionHandler = { [weak self] connection in
        Task { @MainActor in
          self?.acceptInbound(connection)
        }
      }
      self.listener = listener
      listener.start(queue: queue)
      #if targetEnvironment(simulator)
      for delay in [0.25, 0.75, 1.5] {
        Task { @MainActor in
          try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
          self.publishBoundPortIfNeeded()
        }
      }
      #endif
    } catch {
      delegate?.transportDidFailToAdvertise(self, error: error)
    }
  }

  private func handleListenerState(_ state: NWListener.State) {
    switch state {
    case .ready:
      #if targetEnvironment(simulator)
      publishBoundPortIfNeeded()
      #else
      if let port = listener?.port?.rawValue {
        hostingInfo["port"] = String(port)
        listener?.service = NWListener.Service(
          name: Self.sanitizedServiceName(hostingInfo["room"] ?? displayName),
          type: "_\(serviceType)._tcp",
          txtRecord: NWTXTRecord(hostingInfo)
        )
      }
      #endif
    case .failed(let error):
      #if targetEnvironment(simulator)
      Self.clearSimulatorHost(metadata: hostingInfo)
      #endif
      delegate?.transportDidFailToAdvertise(self, error: error)
    case .cancelled:
      break
    default:
      break
    }
  }

  private func acceptInbound(_ connection: NWConnection) {
    let peerKey = UUID().uuidString
    let peer = PeerConnection(
      key: peerKey,
      connection: connection,
      endpoint: connection.endpoint,
      isOutbound: false,
      onEvent: { [weak self] event in
        self?.handlePeerEvent(event)
      }
    )
    connections[peerKey] = peer
    peer.start(on: queue)
  }

  private func startBrowser() {
    #if targetEnvironment(simulator)
    browser?.cancel()
    browser = nil
    startSimulatorDiscoveryPolling()
    pollSimulatorHosts()
    #else
    browser?.cancel()
    let parameters = Self.makeParameters()
    // `.bonjourWithTXTRecord` is required — plain `.bonjour` never returns TXT.
    let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(
      type: "_\(serviceType)._tcp",
      domain: nil
    )
    let browser = NWBrowser(for: descriptor, using: parameters)
    browser.stateUpdateHandler = { [weak self] state in
      Task { @MainActor in
        self?.handleBrowserState(state)
      }
    }
    browser.browseResultsChangedHandler = { [weak self] results, _ in
      Task { @MainActor in
        self?.handleBrowseResults(results)
      }
    }
    self.browser = browser
    browser.start(queue: queue)
    #endif
  }

  private func handleBrowserState(_ state: NWBrowser.State) {
    switch state {
    case .failed(let error):
      delegate?.transportDidFailToBrowse(self, error: error)
    default:
      break
    }
  }

  private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
    var next: [DiscoveredPeer] = []
    var endpoints: [String: NWEndpoint] = [:]
    for result in results {
      let endpoint = result.endpoint
      let id = Self.endpointId(endpoint)
      var display: String
      var roomId: String?
      var epoch: Int?
      var hostDeviceId: String?
      if case .bonjour(let txt) = result.metadata {
        if let host = txt["host"], !host.isEmpty {
          display = host
        } else if case .service(let name, _, _, _) = endpoint {
          display = name
        } else {
          display = id
        }
        roomId = txt["room"]
        if let epochText = txt["epoch"], let value = Int(epochText) {
          epoch = value
        }
        hostDeviceId = txt["hostDevice"]
      } else if case .service(let name, _, _, _) = endpoint {
        display = name
      } else {
        display = id
      }
      // Don't list ourselves when browsing alongside hosting.
      if isHosting, let hostDeviceId, hostDeviceId == hostingInfo["hostDevice"] {
        continue
      }
      if let roomId, !roomId.isEmpty, roomId == hostingInfo["room"] {
        continue
      }
      if display == displayName, isHosting, hostDeviceId == nil {
        continue
      }
      next.append(
        DiscoveredPeer(
          id: id,
          displayName: display,
          roomId: roomId,
          epoch: epoch,
          hostDeviceId: hostDeviceId
        )
      )
      endpoints[id] = endpoint
    }
    next.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    endpointsByPeerId = endpoints
    discovered = next
    publishDiscovered()
  }

  private func publishDiscovered() {
    delegate?.transport(self, discoveredPeersDidChange: discovered)
  }

  private func stopHostingOnly(preservingConnections: Bool) {
    listener?.cancel()
    listener = nil
    if !preservingConnections {
      let inbound = connections.filter { !$0.value.isOutbound }
      for (key, peer) in inbound {
        peer.cancel()
        connections.removeValue(forKey: key)
        delegate?.transport(self, peer: key, didChange: .notConnected)
      }
    }
  }

  private func stopBrowsingOnly() {
    #if targetEnvironment(simulator)
    stopSimulatorDiscoveryPolling()
    #endif
    browser?.cancel()
    browser = nil
  }

  private func handlePeerEvent(_ event: PeerConnection.Event) {
    switch event {
    case .connected(let key):
      delegate?.transport(self, peer: key, didChange: .connected)
    case .disconnected(let key):
      connections.removeValue(forKey: key)
      delegate?.transport(self, peer: key, didChange: .notConnected)
    case .received(let key, let data):
      delegate?.transport(self, didReceive: data, fromPeerKey: key)
    }
  }

  private func startConnection(to peer: DiscoveredPeer, attempt: Int) {
    #if targetEnvironment(simulator)
    let portValue =
      loopbackPortsByPeerId[peer.id]
      ?? peer.roomId.flatMap { Self.readSimulatorPort(roomId: $0) }

    if let portValue, let port = NWEndpoint.Port(rawValue: portValue) {
      // Replace any prior outbound attempt to this loopback port.
      let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: port)
      for (key, existing) in connections where existing.isOutbound {
        existing.cancel()
        connections.removeValue(forKey: key)
      }
      // Plain TCP params for loopback — custom NWParameters have been flaky here.
      let connection = NWConnection(
        host: NWEndpoint.Host("127.0.0.1"),
        port: port,
        using: .tcp
      )
      let peerKey = UUID().uuidString
      let peerConnection = PeerConnection(
        key: peerKey,
        connection: connection,
        endpoint: endpoint,
        isOutbound: true,
        onEvent: { [weak self] event in
          self?.handlePeerEvent(event)
        }
      )
      connections[peerKey] = peerConnection
      peerConnection.start(on: queue)
      return
    }

    // Host port file may not exist until the listener is `.ready`.
    if attempt < 40 {
      connectAttemptTasks[peer.id] = Task { @MainActor in
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard !Task.isCancelled else { return }
        self.startConnection(to: peer, attempt: attempt + 1)
      }
      return
    }
    return
    #else
    guard let endpoint = endpointsByPeerId[peer.id] else { return }
    for (key, existing) in connections where existing.isOutbound && existing.endpoint == endpoint {
      existing.cancel()
      connections.removeValue(forKey: key)
    }
    let peerKey = UUID().uuidString
    let connection = NWConnection(to: endpoint, using: Self.makeParameters())
    let peerConnection = PeerConnection(
      key: peerKey,
      connection: connection,
      endpoint: endpoint,
      isOutbound: true,
      onEvent: { [weak self] event in
        self?.handlePeerEvent(event)
      }
    )
    connections[peerKey] = peerConnection
    peerConnection.start(on: queue)
    #endif
  }

  private func cancelConnectAttempts(for peerId: String) {
    connectAttemptTasks[peerId]?.cancel()
    connectAttemptTasks[peerId] = nil
  }

  private func cancelAllConnectAttempts() {
    for task in connectAttemptTasks.values {
      task.cancel()
    }
    connectAttemptTasks.removeAll()
  }

  private static func makeParameters() -> NWParameters {
    let tcp = NWProtocolTCP.Options()
    tcp.noDelay = true
    let parameters = NWParameters(tls: nil, tcp: tcp)
    #if targetEnvironment(simulator)
    // Peer-to-peer Wi‑Fi breaks Simulator loopback joins.
    parameters.includePeerToPeer = false
    #else
    parameters.includePeerToPeer = true
    #endif
    parameters.allowLocalEndpointReuse = true
    return parameters
  }

  private static func endpointId(_ endpoint: NWEndpoint) -> String {
    switch endpoint {
    case .service(let name, let type, let domain, _):
      return "\(name).\(type).\(domain)"
    default:
      return String(describing: endpoint)
    }
  }

  private static func sanitizedServiceName(_ raw: String) -> String {
    let stripped = raw
      .replacingOccurrences(of: "-", with: "")
      .replacingOccurrences(of: " ", with: "")
      .filter { $0.isLetter || $0.isNumber }
    let clipped = String(stripped.prefix(48))
    return clipped.isEmpty ? "doodleoop\(Int.random(in: 1000...9999))" : clipped
  }

  // MARK: - Simulator file bridge

  #if targetEnvironment(simulator)
  private static var simulatorPortDirectory: URL {
    let hostHome = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"]
      ?? "/Users/\(NSUserName())"
    return URL(fileURLWithPath: hostHome, isDirectory: true)
      .appendingPathComponent("Library/Caches/doodleoop-sim-ports", isDirectory: true)
  }

  private static var simulatorBridgeDirectories: [URL] {
    [
      simulatorPortDirectory,
      URL(fileURLWithPath: "/tmp/doodleoop-sim-ports", isDirectory: true),
    ]
  }

  private func publishBoundPortIfNeeded() {
    guard let port = listener?.port?.rawValue else { return }
    hostingInfo["port"] = String(port)
    Self.publishSimulatorHost(metadata: hostingInfo)
  }

  private func startSimulatorDiscoveryPolling() {
    guard simulatorDiscoveryTimer == nil else { return }
    let timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.pollSimulatorHosts()
      }
    }
    RunLoop.main.add(timer, forMode: .common)
    simulatorDiscoveryTimer = timer
  }

  private func stopSimulatorDiscoveryPolling() {
    simulatorDiscoveryTimer?.invalidate()
    simulatorDiscoveryTimer = nil
  }

  private func pollSimulatorHosts() {
    let ownRoom = hostingInfo["room"] ?? ""
    let ownHostDevice = hostingInfo["hostDevice"] ?? ""
    var next: [DiscoveredPeer] = []
    var endpoints: [String: NWEndpoint] = [:]
    var ports: [String: UInt16] = [:]

    for host in Self.loadSimulatorHosts() {
      if !ownRoom.isEmpty, host.peer.roomId == ownRoom { continue }
      if !ownHostDevice.isEmpty, host.peer.hostDeviceId == ownHostDevice { continue }
      next.append(host.peer)
      if let port = host.port, let nwPort = NWEndpoint.Port(rawValue: port) {
        endpoints[host.peer.id] = NWEndpoint.hostPort(host: "127.0.0.1", port: nwPort)
        ports[host.peer.id] = port
      }
    }
    next.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    endpointsByPeerId = endpoints
    loopbackPortsByPeerId = ports
    discovered = next
    publishDiscovered()
  }

  private struct SimulatorHost {
    let peer: DiscoveredPeer
    let port: UInt16?
  }

  private static func publishSimulatorHost(metadata: [String: String]) {
    guard let roomId = metadata["room"], !roomId.isEmpty else { return }
    guard metadata["port"] != nil else { return }
    let id = sanitizedServiceName(roomId)
    guard let data = try? JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]) else {
      return
    }
    for directory in simulatorBridgeDirectories {
      do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Drop stale ads from previous Simulator runs so joiners don't hit dead ports.
        if let files = try? FileManager.default.contentsOfDirectory(
          at: directory,
          includingPropertiesForKeys: nil
        ) {
          for file in files {
            let name = file.deletingPathExtension().lastPathComponent
            if name != id, file.pathExtension == "json" || file.pathExtension == "port" {
              try? FileManager.default.removeItem(at: file)
            }
          }
        }
        try data.write(to: directory.appendingPathComponent("\(id).json"), options: .atomic)
        if let port = metadata["port"] {
          try port.data(using: .utf8)?.write(
            to: directory.appendingPathComponent("\(id).port"),
            options: .atomic
          )
        }
      } catch {
        continue
      }
    }
  }

  private static func clearSimulatorHost(metadata: [String: String]) {
    guard let roomId = metadata["room"], !roomId.isEmpty else { return }
    let id = sanitizedServiceName(roomId)
    for directory in simulatorBridgeDirectories {
      try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(id).json"))
      try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(id).port"))
    }
  }

  private static func readSimulatorPort(roomId: String) -> UInt16? {
    let id = sanitizedServiceName(roomId)
    guard !id.isEmpty else { return nil }
    for directory in simulatorBridgeDirectories {
      let json = directory.appendingPathComponent("\(id).json")
      if let data = try? Data(contentsOf: json),
         let object = try? JSONSerialization.jsonObject(with: data) as? [String: String],
         let port = object["port"].flatMap(UInt16.init) {
        return port
      }
      let portFile = directory.appendingPathComponent("\(id).port")
      if let text = try? String(contentsOf: portFile, encoding: .utf8),
         let port = UInt16(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
        return port
      }
    }
    return nil
  }

  private static func loadSimulatorHosts() -> [SimulatorHost] {
    var hosts: [SimulatorHost] = []
    var seenRooms = Set<String>()
    for directory in simulatorBridgeDirectories {
      guard let files = try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
      ) else { continue }

      for file in files where file.pathExtension == "json" {
        guard let data = try? Data(contentsOf: file),
              let metadata = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let roomId = metadata["room"], !roomId.isEmpty,
              let portText = metadata["port"], let port = UInt16(portText),
              seenRooms.insert(roomId).inserted else { continue }
        let id = "sim:\(sanitizedServiceName(roomId))"
        let peer = DiscoveredPeer(
          id: id,
          displayName: metadata["host"] ?? "Host",
          roomId: roomId,
          epoch: metadata["epoch"].flatMap(Int.init),
          hostDeviceId: metadata["hostDevice"]
        )
        hosts.append(SimulatorHost(peer: peer, port: port))
      }
    }
    return hosts
  }
  #endif
}

// MARK: - Per-connection framing

@MainActor
private final class PeerConnection {
  enum Event {
    case connected(String)
    case disconnected(String)
    case received(String, Data)
  }

  let key: String
  let connection: NWConnection
  let endpoint: NWEndpoint
  let isOutbound: Bool
  private let onEvent: @MainActor (Event) -> Void
  private var decoder = MessageFraming.Decoder()
  private var didAnnounceConnected = false
  private var isCancelled = false

  init(
    key: String,
    connection: NWConnection,
    endpoint: NWEndpoint,
    isOutbound: Bool,
    onEvent: @escaping @MainActor (Event) -> Void
  ) {
    self.key = key
    self.connection = connection
    self.endpoint = endpoint
    self.isOutbound = isOutbound
    self.onEvent = onEvent
  }

  func start(on queue: DispatchQueue) {
    connection.stateUpdateHandler = { [weak self] state in
      Task { @MainActor in
        self?.handleState(state)
      }
    }
    connection.start(queue: queue)
    receiveLoop()
  }

  func send(_ framed: Data) {
    guard !isCancelled else { return }
    connection.send(content: framed, completion: .contentProcessed { _ in })
  }

  func cancel() {
    isCancelled = true
    connection.stateUpdateHandler = nil
    connection.cancel()
  }

  private func handleState(_ state: NWConnection.State) {
    switch state {
    case .ready:
      guard !didAnnounceConnected else { return }
      didAnnounceConnected = true
      onEvent(.connected(key))
    case .failed, .cancelled:
      guard !isCancelled else {
        return
      }
      isCancelled = true
      onEvent(.disconnected(key))
    default:
      break
    }
  }

  private func receiveLoop() {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] content, _, isComplete, error in
      Task { @MainActor in
        guard let self, !self.isCancelled else { return }
        if let content, !content.isEmpty {
          do {
            let messages = try self.decoder.append(content)
            for message in messages {
              self.onEvent(.received(self.key, message))
            }
          } catch {
            self.isCancelled = true
            self.connection.cancel()
            self.onEvent(.disconnected(self.key))
            return
          }
        }
        if isComplete || error != nil {
          if !self.isCancelled {
            self.isCancelled = true
            self.onEvent(.disconnected(self.key))
          }
          return
        }
        self.receiveLoop()
      }
    }
  }
}
