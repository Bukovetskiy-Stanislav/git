
import Foundation

#if os(iOS) || os(watchOS) || os(tvOS)
import MobileCoreServices
#elseif os(OSX)
import CoreServices
#endif


public class MultipartFormData {

    // MARK: - Helper Types

    struct EncodingCharacters {
        static let CRLF = "\r\n"
    }

    struct BoundaryGenerator {
        enum BoundaryType {
            case Initial, Encapsulated, Final
        }

        static func randomBoundary() -> String {
            return String(format: "alamofire.boundary.%08x%08x", arc4random(), arc4random())
        }

        static func boundaryData(boundaryType boundaryType: BoundaryType, boundary: String) -> NSData {
            let boundaryText: String

            switch boundaryType {
            case .Initial:
                boundaryText = "--\(boundary)\(EncodingCharacters.CRLF)"
            case .Encapsulated:
                boundaryText = "\(EncodingCharacters.CRLF)--\(boundary)\(EncodingCharacters.CRLF)"
            case .Final:
                boundaryText = "\(EncodingCharacters.CRLF)--\(boundary)--\(EncodingCharacters.CRLF)"
            }

            return boundaryText.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false)!
        }
    }

    class BodyPart {
        let headers: [String: String]
        let bodyStream: NSInputStream
        let bodyContentLength: UInt64
        var hasInitialBoundary = false
        var hasFinalBoundary = false

        init(headers: [String: String], bodyStream: NSInputStream, bodyContentLength: UInt64) {
            self.headers = headers
            self.bodyStream = bodyStream
            self.bodyContentLength = bodyContentLength
        }
    }


    public var contentType: String { return "multipart/form-data; boundary=\(boundary)" }

    public var contentLength: UInt64 { return bodyParts.reduce(0) { $0 + $1.bodyContentLength } }

    public let boundary: String

    private var bodyParts: [BodyPart]
    private var bodyPartError: NSError?
    private let streamBufferSize: Int


    public init() {
        self.boundary = BoundaryGenerator.randomBoundary()
        self.bodyParts = []


        self.streamBufferSize = 1024
    }


    public func appendBodyPart(data data: NSData, name: String) {
        let headers = contentHeaders(name: name)
        let stream = NSInputStream(data: data)
        let length = UInt64(data.length)

        appendBodyPart(stream: stream, length: length, headers: headers)
    }


    public func appendBodyPart(data data: NSData, name: String, mimeType: String) {
        let headers = contentHeaders(name: name, mimeType: mimeType)
        let stream = NSInputStream(data: data)
        let length = UInt64(data.length)

        appendBodyPart(stream: stream, length: length, headers: headers)
    }

    public func appendBodyPart(data data: NSData, name: String, fileName: String, mimeType: String) {
        let headers = contentHeaders(name: name, fileName: fileName, mimeType: mimeType)
        let stream = NSInputStream(data: data)
        let length = UInt64(data.length)

        appendBodyPart(stream: stream, length: length, headers: headers)
    }

    public func appendBodyPart(fileURL fileURL: NSURL, name: String) {
        if let
            fileName = fileURL.lastPathComponent,
            pathExtension = fileURL.pathExtension
        {
            let mimeType = mimeTypeForPathExtension(pathExtension)
            appendBodyPart(fileURL: fileURL, name: name, fileName: fileName, mimeType: mimeType)
        } else {
            let failureReason = "Failed to extract the fileName of the provided URL: \(fileURL)"
            setBodyPartError(code: NSURLErrorBadURL, failureReason: failureReason)
        }
    }


    public func appendBodyPart(fileURL fileURL: NSURL, name: String, fileName: String, mimeType: String) {
        let headers = contentHeaders(name: name, fileName: fileName, mimeType: mimeType)

        guard fileURL.fileURL else {
            let failureReason = "The file URL does not point to a file URL: \(fileURL)"
            setBodyPartError(code: NSURLErrorBadURL, failureReason: failureReason)
            return
        }

        var isReachable = true

        if #available(OSX 10.10, *) {
            isReachable = fileURL.checkPromisedItemIsReachableAndReturnError(nil)
        }

        guard isReachable else {
            setBodyPartError(code: NSURLErrorBadURL, failureReason: "The file URL is not reachable: \(fileURL)")
            return
        }

        var isDirectory: ObjCBool = false

        guard let
            path = fileURL.path
            where NSFileManager.defaultManager().fileExistsAtPath(path, isDirectory: &isDirectory) && !isDirectory else
        {
            let failureReason = "The file URL is a directory, not a file: \(fileURL)"
            setBodyPartError(code: NSURLErrorBadURL, failureReason: failureReason)
            return
        }

        var bodyContentLength: UInt64?

        do {
            if let
                path = fileURL.path,
                fileSize = try NSFileManager.defaultManager().attributesOfItemAtPath(path)[NSFileSize] as? NSNumber
            {
                bodyContentLength = fileSize.unsignedLongLongValue
            }
        } catch {
        }

        guard let length = bodyContentLength else {
            let failureReason = "Could not fetch attributes from the file URL: \(fileURL)"
            setBodyPartError(code: NSURLErrorBadURL, failureReason: failureReason)
            return
        }

        guard let stream = NSInputStream(URL: fileURL) else {
            let failureReason = "Failed to create an input stream from the file URL: \(fileURL)"
            setBodyPartError(code: NSURLErrorCannotOpenFile, failureReason: failureReason)
            return
        }

        appendBodyPart(stream: stream, length: length, headers: headers)
    }


    public func appendBodyPart(
        stream stream: NSInputStream,
        length: UInt64,
        name: String,
        fileName: String,
        mimeType: String)
    {
        let headers = contentHeaders(name: name, fileName: fileName, mimeType: mimeType)
        appendBodyPart(stream: stream, length: length, headers: headers)
    }


    public func appendBodyPart(stream stream: NSInputStream, length: UInt64, headers: [String: String]) {
        let bodyPart = BodyPart(headers: headers, bodyStream: stream, bodyContentLength: length)
        bodyParts.append(bodyPart)
    }


    public func encode() throws -> NSData {
        if let bodyPartError = bodyPartError {
            throw bodyPartError
        }

        let encoded = NSMutableData()

        bodyParts.first?.hasInitialBoundary = true
        bodyParts.last?.hasFinalBoundary = true

        for bodyPart in bodyParts {
            let encodedData = try encodeBodyPart(bodyPart)
            encoded.appendData(encodedData)
        }

        return encoded
    }

    public func writeEncodedDataToDisk(fileURL: NSURL) throws {
        if let bodyPartError = bodyPartError {
            throw bodyPartError
        }

        if let path = fileURL.path where NSFileManager.defaultManager().fileExistsAtPath(path) {
            let failureReason = "A file already exists at the given file URL: \(fileURL)"
            throw Error.error(domain: NSURLErrorDomain, code: NSURLErrorBadURL, failureReason: failureReason)
        } else if !fileURL.fileURL {
            let failureReason = "The URL does not point to a valid file: \(fileURL)"
            throw Error.error(domain: NSURLErrorDomain, code: NSURLErrorBadURL, failureReason: failureReason)
        }

        let outputStream: NSOutputStream

        if let possibleOutputStream = NSOutputStream(URL: fileURL, append: false) {
            outputStream = possibleOutputStream
        } else {
            let failureReason = "Failed to create an output stream with the given URL: \(fileURL)"
            throw Error.error(domain: NSURLErrorDomain, code: NSURLErrorCannotOpenFile, failureReason: failureReason)
        }

        outputStream.open()

        self.bodyParts.first?.hasInitialBoundary = true
        self.bodyParts.last?.hasFinalBoundary = true

        for bodyPart in self.bodyParts {
            try writeBodyPart(bodyPart, toOutputStream: outputStream)
        }

        outputStream.close()
    }


    private func encodeBodyPart(bodyPart: BodyPart) throws -> NSData {
        let encoded = NSMutableData()

        let initialData = bodyPart.hasInitialBoundary ? initialBoundaryData() : encapsulatedBoundaryData()
        encoded.appendData(initialData)

        let headerData = encodeHeaderDataForBodyPart(bodyPart)
        encoded.appendData(headerData)

        let bodyStreamData = try encodeBodyStreamDataForBodyPart(bodyPart)
        encoded.appendData(bodyStreamData)

        if bodyPart.hasFinalBoundary {
            encoded.appendData(finalBoundaryData())
        }

        return encoded
    }

    private func encodeHeaderDataForBodyPart(bodyPart: BodyPart) -> NSData {
        var headerText = ""

        for (key, value) in bodyPart.headers {
            headerText += "\(key): \(value)\(EncodingCharacters.CRLF)"
        }
        headerText += EncodingCharacters.CRLF

        return headerText.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false)!
    }

    private func encodeBodyStreamDataForBodyPart(bodyPart: BodyPart) throws -> NSData {
        let inputStream = bodyPart.bodyStream
        inputStream.open()

        var error: NSError?
        let encoded = NSMutableData()

        while inputStream.hasBytesAvailable {
            var buffer = [UInt8](count: streamBufferSize, repeatedValue: 0)
            let bytesRead = inputStream.read(&buffer, maxLength: streamBufferSize)

            if inputStream.streamError != nil {
                error = inputStream.streamError
                break
            }

            if bytesRead > 0 {
                encoded.appendBytes(buffer, length: bytesRead)
            } else if bytesRead < 0 {
                let failureReason = "Failed to read from input stream: \(inputStream)"
                error = Error.error(domain: NSURLErrorDomain, code: .InputStreamReadFailed, failureReason: failureReason)
                break
            } else {
                break
            }
        }

        inputStream.close()

        if let error = error {
            throw error
        }

        return encoded
    }

    // MARK: - Private - Writing Body Part to Output Stream

    private func writeBodyPart(bodyPart: BodyPart, toOutputStream outputStream: NSOutputStream) throws {
        try writeInitialBoundaryDataForBodyPart(bodyPart, toOutputStream: outputStream)
        try writeHeaderDataForBodyPart(bodyPart, toOutputStream: outputStream)
        try writeBodyStreamForBodyPart(bodyPart, toOutputStream: outputStream)
        try writeFinalBoundaryDataForBodyPart(bodyPart, toOutputStream: outputStream)
    }

    private func writeInitialBoundaryDataForBodyPart(
        bodyPart: BodyPart,
        toOutputStream outputStream: NSOutputStream)
        throws
    {
        let initialData = bodyPart.hasInitialBoundary ? initialBoundaryData() : encapsulatedBoundaryData()
        return try writeData(initialData, toOutputStream: outputStream)
    }

    private func writeHeaderDataForBodyPart(bodyPart: BodyPart, toOutputStream outputStream: NSOutputStream) throws {
        let headerData = encodeHeaderDataForBodyPart(bodyPart)
        return try writeData(headerData, toOutputStream: outputStream)
    }

    private func writeBodyStreamForBodyPart(bodyPart: BodyPart, toOutputStream outputStream: NSOutputStream) throws {
        let inputStream = bodyPart.bodyStream
        inputStream.open()

        while inputStream.hasBytesAvailable {
            var buffer = [UInt8](count: streamBufferSize, repeatedValue: 0)
            let bytesRead = inputStream.read(&buffer, maxLength: streamBufferSize)

            if let streamError = inputStream.streamError {
                throw streamError
            }

            if bytesRead > 0 {
                if buffer.count != bytesRead {
                    buffer = Array(buffer[0..<bytesRead])
                }

                try writeBuffer(&buffer, toOutputStream: outputStream)
            } else if bytesRead < 0 {
                let failureReason = "Failed to read from input stream: \(inputStream)"
                throw Error.error(domain: NSURLErrorDomain, code: .InputStreamReadFailed, failureReason: failureReason)
            } else {
                break
            }
        }

        inputStream.close()
    }

    private func writeFinalBoundaryDataForBodyPart(
        bodyPart: BodyPart,
        toOutputStream outputStream: NSOutputStream)
        throws
    {
        if bodyPart.hasFinalBoundary {
            return try writeData(finalBoundaryData(), toOutputStream: outputStream)
        }
    }


    private func writeData(data: NSData, toOutputStream outputStream: NSOutputStream) throws {
        var buffer = [UInt8](count: data.length, repeatedValue: 0)
        data.getBytes(&buffer, length: data.length)

        return try writeBuffer(&buffer, toOutputStream: outputStream)
    }

    private func writeBuffer(inout buffer: [UInt8], toOutputStream outputStream: NSOutputStream) throws {
        var bytesToWrite = buffer.count

        while bytesToWrite > 0 {
            if outputStream.hasSpaceAvailable {
                let bytesWritten = outputStream.write(buffer, maxLength: bytesToWrite)

                if let streamError = outputStream.streamError {
                    throw streamError
                }

                if bytesWritten < 0 {
                    let failureReason = "Failed to write to output stream: \(outputStream)"
                    throw Error.error(domain: NSURLErrorDomain, code: .OutputStreamWriteFailed, failureReason: failureReason)
                }

                bytesToWrite -= bytesWritten

                if bytesToWrite > 0 {
                    buffer = Array(buffer[bytesWritten..<buffer.count])
                }
            } else if let streamError = outputStream.streamError {
                throw streamError
            }
        }
    }

    private func mimeTypeForPathExtension(pathExtension: String) -> String {
        if let
            id = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, pathExtension, nil)?.takeRetainedValue(),
            contentType = UTTypeCopyPreferredTagWithClass(id, kUTTagClassMIMEType)?.takeRetainedValue()
        {
            return contentType as String
        }

        return "application/octet-stream"
    }

    private func contentHeaders(name name: String) -> [String: String] {
        return ["Content-Disposition": "form-data; name=\"\(name)\""]
    }

    private func contentHeaders(name name: String, mimeType: String) -> [String: String] {
        return [
            "Content-Disposition": "form-data; name=\"\(name)\"",
            "Content-Type": "\(mimeType)"
        ]
    }

    private func contentHeaders(name name: String, fileName: String, mimeType: String) -> [String: String] {
        return [
            "Content-Disposition": "form-data; name=\"\(name)\"; filename=\"\(fileName)\"",
            "Content-Type": "\(mimeType)"
        ]
    }

    private func initialBoundaryData() -> NSData {
        return BoundaryGenerator.boundaryData(boundaryType: .Initial, boundary: boundary)
    }

    private func encapsulatedBoundaryData() -> NSData {
        return BoundaryGenerator.boundaryData(boundaryType: .Encapsulated, boundary: boundary)
    }

    private func finalBoundaryData() -> NSData {
        return BoundaryGenerator.boundaryData(boundaryType: .Final, boundary: boundary)
    }


    private func setBodyPartError(code code: Int, failureReason: String) {
        guard bodyPartError == nil else { return }
        bodyPartError = Error.error(domain: NSURLErrorDomain, code: code, failureReason: failureReason)
    }
}
