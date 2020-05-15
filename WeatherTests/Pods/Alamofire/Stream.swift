
import Foundation

#if !os(watchOS)

@available(iOS 9.0, OSX 10.11, tvOS 9.0, *)
extension Manager {
    private enum Streamable {
        case Stream(String, Int)
        case NetService(NSNetService)
    }

    private func stream(streamable: Streamable) -> Request {
        var streamTask: NSURLSessionStreamTask!

        switch streamable {
        case .Stream(let hostName, let port):
            dispatch_sync(queue) {
                streamTask = self.session.streamTaskWithHostName(hostName, port: port)
            }
        case .NetService(let netService):
            dispatch_sync(queue) {
                streamTask = self.session.streamTaskWithNetService(netService)
            }
        }

        let request = Request(session: session, task: streamTask)

        delegate[request.delegate.task] = request.delegate

        if startRequestsImmediately {
            request.resume()
        }

        return request
    }

    public func stream(hostName hostName: String, port: Int) -> Request {
        return stream(.Stream(hostName, port))
    }

    public func stream(netService netService: NSNetService) -> Request {
        return stream(.NetService(netService))
    }
}


@available(iOS 9.0, OSX 10.11, tvOS 9.0, *)
extension Manager.SessionDelegate: NSURLSessionStreamDelegate {

    public var streamTaskReadClosed: ((NSURLSession, NSURLSessionStreamTask) -> Void)? {
        get {
            return _streamTaskReadClosed as? (NSURLSession, NSURLSessionStreamTask) -> Void
        }
        set {
            _streamTaskReadClosed = newValue
        }
    }

    public var streamTaskWriteClosed: ((NSURLSession, NSURLSessionStreamTask) -> Void)? {
        get {
            return _streamTaskWriteClosed as? (NSURLSession, NSURLSessionStreamTask) -> Void
        }
        set {
            _streamTaskWriteClosed = newValue
        }
    }

    public var streamTaskBetterRouteDiscovered: ((NSURLSession, NSURLSessionStreamTask) -> Void)? {
        get {
            return _streamTaskBetterRouteDiscovered as? (NSURLSession, NSURLSessionStreamTask) -> Void
        }
        set {
            _streamTaskBetterRouteDiscovered = newValue
        }
    }
    public var streamTaskDidBecomeInputStream: ((NSURLSession, NSURLSessionStreamTask, NSInputStream, NSOutputStream) -> Void)? {
        get {
            return _streamTaskDidBecomeInputStream as? (NSURLSession, NSURLSessionStreamTask, NSInputStream, NSOutputStream) -> Void
        }
        set {
            _streamTaskDidBecomeInputStream = newValue
        }
    }

    public func URLSession(session: NSURLSession, readClosedForStreamTask streamTask: NSURLSessionStreamTask) {
        streamTaskReadClosed?(session, streamTask)
    }

    public func URLSession(session: NSURLSession, writeClosedForStreamTask streamTask: NSURLSessionStreamTask) {
        streamTaskWriteClosed?(session, streamTask)
    }

    public func URLSession(session: NSURLSession, betterRouteDiscoveredForStreamTask streamTask: NSURLSessionStreamTask) {
        streamTaskBetterRouteDiscovered?(session, streamTask)
    }

    public func URLSession(
        session: NSURLSession,
        streamTask: NSURLSessionStreamTask,
        didBecomeInputStream inputStream: NSInputStream,
        outputStream: NSOutputStream)
    {
        streamTaskDidBecomeInputStream?(session, streamTask, inputStream, outputStream)
    }
}

#endif
