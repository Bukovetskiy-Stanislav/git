
#if !os(watchOS)

import Foundation
import SystemConfiguration


public class NetworkReachabilityManager {

    public enum NetworkReachabilityStatus {
        case Unknown
        case NotReachable
        case Reachable(ConnectionType)
    }

    public enum ConnectionType {
        case EthernetOrWiFi
        case WWAN
    }


    public typealias Listener = NetworkReachabilityStatus -> Void

    public var isReachable: Bool { return isReachableOnWWAN || isReachableOnEthernetOrWiFi }


    public var isReachableOnWWAN: Bool { return networkReachabilityStatus == .Reachable(.WWAN) }

    public var isReachableOnEthernetOrWiFi: Bool { return networkReachabilityStatus == .Reachable(.EthernetOrWiFi) }

    public var networkReachabilityStatus: NetworkReachabilityStatus {
        guard let flags = self.flags else { return .Unknown }
        return networkReachabilityStatusForFlags(flags)
    }

    public var listenerQueue: dispatch_queue_t = dispatch_get_main_queue()

    public var listener: Listener?

    private var flags: SCNetworkReachabilityFlags? {
        var flags = SCNetworkReachabilityFlags()

        if SCNetworkReachabilityGetFlags(reachability, &flags) {
            return flags
        }

        return nil
    }

    private let reachability: SCNetworkReachability
    private var previousFlags: SCNetworkReachabilityFlags


    public convenience init?(host: String) {
        guard let reachability = SCNetworkReachabilityCreateWithName(nil, host) else { return nil }
        self.init(reachability: reachability)
    }

    public convenience init?() {
        var address = sockaddr_in()
        address.sin_len = UInt8(sizeofValue(address))
        address.sin_family = sa_family_t(AF_INET)

        guard let reachability = withUnsafePointer(&address, {
            SCNetworkReachabilityCreateWithAddress(nil, UnsafePointer($0))
        }) else { return nil }

        self.init(reachability: reachability)
    }

    private init(reachability: SCNetworkReachability) {
        self.reachability = reachability
        self.previousFlags = SCNetworkReachabilityFlags()
    }

    deinit {
        stopListening()
    }

    public func startListening() -> Bool {
        var context = SCNetworkReachabilityContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        context.info = UnsafeMutablePointer(Unmanaged.passUnretained(self).toOpaque())

        let callbackEnabled = SCNetworkReachabilitySetCallback(
            reachability,
            { (_, flags, info) in
                let reachability = Unmanaged<NetworkReachabilityManager>.fromOpaque(COpaquePointer(info)).takeUnretainedValue()
                reachability.notifyListener(flags)
            },
            &context
        )

        let queueEnabled = SCNetworkReachabilitySetDispatchQueue(reachability, listenerQueue)

        dispatch_async(listenerQueue) {
            self.previousFlags = SCNetworkReachabilityFlags()
            self.notifyListener(self.flags ?? SCNetworkReachabilityFlags())
        }

        return callbackEnabled && queueEnabled
    }

    public func stopListening() {
        SCNetworkReachabilitySetCallback(reachability, nil, nil)
        SCNetworkReachabilitySetDispatchQueue(reachability, nil)
    }

    func notifyListener(flags: SCNetworkReachabilityFlags) {
        guard previousFlags != flags else { return }
        previousFlags = flags

        listener?(networkReachabilityStatusForFlags(flags))
    }


    func networkReachabilityStatusForFlags(flags: SCNetworkReachabilityFlags) -> NetworkReachabilityStatus {
        guard flags.contains(.Reachable) else { return .NotReachable }

        var networkStatus: NetworkReachabilityStatus = .NotReachable

        if !flags.contains(.ConnectionRequired) { networkStatus = .Reachable(.EthernetOrWiFi) }

        if flags.contains(.ConnectionOnDemand) || flags.contains(.ConnectionOnTraffic) {
            if !flags.contains(.InterventionRequired) { networkStatus = .Reachable(.EthernetOrWiFi) }
        }

        #if os(iOS)
            if flags.contains(.IsWWAN) { networkStatus = .Reachable(.WWAN) }
        #endif

        return networkStatus
    }
}



extension NetworkReachabilityManager.NetworkReachabilityStatus: Equatable {}

public func ==(
    lhs: NetworkReachabilityManager.NetworkReachabilityStatus,
    rhs: NetworkReachabilityManager.NetworkReachabilityStatus)
    -> Bool
{
    switch (lhs, rhs) {
    case (.Unknown, .Unknown):
        return true
    case (.NotReachable, .NotReachable):
        return true
    case let (.Reachable(lhsConnectionType), .Reachable(rhsConnectionType)):
        return lhsConnectionType == rhsConnectionType
    default:
        return false
    }
}

#endif
