
import Foundation

class ConcurrentOperation: NSOperation {



    enum State {
        case Ready
        case Executing
        case Finished

        var keyPath: String {
            switch self {
            case Ready:
                return "isReady"
            case Executing:
                return "isExecuting"
            case Finished:
                return "isFinished"
            }
        }
    }

    var state = State.Ready {
        willSet {
            willChangeValueForKey(newValue.keyPath)
            willChangeValueForKey(state.keyPath)
        }
        didSet {
            didChangeValueForKey(oldValue.keyPath)
            didChangeValueForKey(state.keyPath)
        }
    }

    // MARK: - NSOperation

    override var ready: Bool {
        return super.ready && state == .Ready
    }

    override var executing: Bool {
        return state == .Executing
    }

    override var finished: Bool {
        return state == .Finished
    }

    override var asynchronous: Bool {
        return true
    }

}
