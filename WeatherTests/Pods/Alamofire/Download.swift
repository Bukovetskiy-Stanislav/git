

import Foundation

extension Manager {
    private enum Downloadable {
        case Request(NSURLRequest)
        case ResumeData(NSData)
    }

    private func download(downloadable: Downloadable, destination: Request.DownloadFileDestination) -> Request {
        var downloadTask: NSURLSessionDownloadTask!

        switch downloadable {
        case .Request(let request):
            dispatch_sync(queue) {
                downloadTask = self.session.downloadTaskWithRequest(request)
            }
        case .ResumeData(let resumeData):
            dispatch_sync(queue) {
                downloadTask = self.session.downloadTaskWithResumeData(resumeData)
            }
        }

        let request = Request(session: session, task: downloadTask)

        if let downloadDelegate = request.delegate as? Request.DownloadTaskDelegate {
            downloadDelegate.downloadTaskDidFinishDownloadingToURL = { session, downloadTask, URL in
                return destination(URL, downloadTask.response as! NSHTTPURLResponse)
            }
        }

        delegate[request.delegate.task] = request.delegate

        if startRequestsImmediately {
            request.resume()
        }

        return request
    }


    public func download(
        method: Method,
        _ URLString: URLStringConvertible,
        parameters: [String: AnyObject]? = nil,
        encoding: ParameterEncoding = .URL,
        headers: [String: String]? = nil,
        destination: Request.DownloadFileDestination)
        -> Request
    {
        let mutableURLRequest = URLRequest(method, URLString, headers: headers)
        let encodedURLRequest = encoding.encode(mutableURLRequest, parameters: parameters).0

        return download(encodedURLRequest, destination: destination)
    }

    public func download(URLRequest: URLRequestConvertible, destination: Request.DownloadFileDestination) -> Request {
        return download(.Request(URLRequest.URLRequest), destination: destination)
    }


    public func download(resumeData: NSData, destination: Request.DownloadFileDestination) -> Request {
        return download(.ResumeData(resumeData), destination: destination)
    }
}

// MARK: -

extension Request {

    public typealias DownloadFileDestination = (NSURL, NSHTTPURLResponse) -> NSURL


    public class func suggestedDownloadDestination(
        directory directory: NSSearchPathDirectory = .DocumentDirectory,
        domain: NSSearchPathDomainMask = .UserDomainMask)
        -> DownloadFileDestination
    {
        return { temporaryURL, response -> NSURL in
            let directoryURLs = NSFileManager.defaultManager().URLsForDirectory(directory, inDomains: domain)

            if !directoryURLs.isEmpty {
                return directoryURLs[0].URLByAppendingPathComponent(response.suggestedFilename!)
            }

            return temporaryURL
        }
    }

    public var resumeData: NSData? {
        var data: NSData?

        if let delegate = delegate as? DownloadTaskDelegate {
            data = delegate.resumeData
        }

        return data
    }


    class DownloadTaskDelegate: TaskDelegate, NSURLSessionDownloadDelegate {
        var downloadTask: NSURLSessionDownloadTask? { return task as? NSURLSessionDownloadTask }
        var downloadProgress: ((Int64, Int64, Int64) -> Void)?

        var resumeData: NSData?
        override var data: NSData? { return resumeData }


        var downloadTaskDidFinishDownloadingToURL: ((NSURLSession, NSURLSessionDownloadTask, NSURL) -> NSURL)?
        var downloadTaskDidWriteData: ((NSURLSession, NSURLSessionDownloadTask, Int64, Int64, Int64) -> Void)?
        var downloadTaskDidResumeAtOffset: ((NSURLSession, NSURLSessionDownloadTask, Int64, Int64) -> Void)?

        // MARK: Delegate Methods

        func URLSession(
            session: NSURLSession,
            downloadTask: NSURLSessionDownloadTask,
            didFinishDownloadingToURL location: NSURL)
        {
            if let downloadTaskDidFinishDownloadingToURL = downloadTaskDidFinishDownloadingToURL {
                do {
                    let destination = downloadTaskDidFinishDownloadingToURL(session, downloadTask, location)
                    try NSFileManager.defaultManager().moveItemAtURL(location, toURL: destination)
                } catch {
                    self.error = error as NSError
                }
            }
        }

        func URLSession(
            session: NSURLSession,
            downloadTask: NSURLSessionDownloadTask,
            didWriteData bytesWritten: Int64,
            totalBytesWritten: Int64,
            totalBytesExpectedToWrite: Int64)
        {
            if initialResponseTime == nil { initialResponseTime = CFAbsoluteTimeGetCurrent() }

            if let downloadTaskDidWriteData = downloadTaskDidWriteData {
                downloadTaskDidWriteData(
                    session,
                    downloadTask,
                    bytesWritten,
                    totalBytesWritten, 
                    totalBytesExpectedToWrite
                )
            } else {
                progress.totalUnitCount = totalBytesExpectedToWrite
                progress.completedUnitCount = totalBytesWritten

                downloadProgress?(bytesWritten, totalBytesWritten, totalBytesExpectedToWrite)
            }
        }

        func URLSession(
            session: NSURLSession,
            downloadTask: NSURLSessionDownloadTask,
            didResumeAtOffset fileOffset: Int64,
            expectedTotalBytes: Int64)
        {
            if let downloadTaskDidResumeAtOffset = downloadTaskDidResumeAtOffset {
                downloadTaskDidResumeAtOffset(session, downloadTask, fileOffset, expectedTotalBytes)
            } else {
                progress.totalUnitCount = expectedTotalBytes
                progress.completedUnitCount = fileOffset
            }
        }
    }
}
