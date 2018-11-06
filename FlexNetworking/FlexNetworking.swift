//
//  FlexNetworking
//
//  A common sense sync-or-async networking lib with an ability to get results flexibly.
//

import Foundation

private let SwiftNSURLResponseUnknownLength: Int64 = -1

/// All the context that goes into making a request. Useful for troubleshooting, as this is included with all responses.
public typealias RequestParameters = (session: URLSession, path: String, method: RequestMethod, body: RequestBody?, headers: [String: String])

public class FlexNetworking: NSObject {
    public let preRequestHooks: [PreRequestHook]
    public let postRequestHooks: [PostRequestHook]

    public let defaultEncoder: JSONEncoder
    public let defaultDecoder: JSONDecoder

    internal let dispatchQueue: DispatchQueue
    private let operationQueue: OperationQueue
    internal lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: self.operationQueue)

    internal var requestParamatersMap: [String: RequestParameters] = [:]
    private var dataSoFar: [String: Data] = [:]
    private var expectedDataLength: [String: Int64] = [:]
    internal var responseObservers: [String: (Response?, Error?) -> Void] = [:]
    internal var dataObservers: [String: (Data) -> Void] = [:]
    internal var progressObservers: [String: (Float) -> Void] = [:]

    public static let `default` = FlexNetworking()

    public init(preRequestHooks: [PreRequestHook] = [],
        postRequestHooks: [PostRequestHook] = [],
        defaultEncoder: JSONEncoder = JSONEncoder(),
        defaultDecoder: JSONDecoder = JSONDecoder()) {

        self.preRequestHooks = preRequestHooks
        self.postRequestHooks = postRequestHooks
        self.defaultEncoder = defaultEncoder
        self.defaultDecoder = defaultDecoder

        self.dispatchQueue = DispatchQueue(label: "\(type(of: self)).dispatchQueue)")
        self.operationQueue = OperationQueue()
        self.operationQueue.underlyingQueue = self.dispatchQueue

        super.init()
    }

    // MARK: - Request Methods

    ///
    /// Creates a URLSessionTask for a single HTTP request with request parameters specified in FlexNetworking notation.
    ///
    public func getTaskForRequest(path: String, method: RequestMethod, body: RequestBody?, headers: [String: String] = [:]) throws -> URLSessionTask {
        guard let url = URL(string: path) else {
            throw RequestError.invalidURL(message: "Invalid URL \(path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue

        if method == .get {
            if let queryString = body?.getQueryString() {
                let newPath = "\(path)?\(queryString)"
                if let newURL = URL(string: newPath) {
                    request.url = newURL
                } else {
                    throw RequestError.invalidURL(message: "Invalid URL \(newPath)")
                }
            }
        } else {
            request.httpBody = body?.getHTTPBody()
            if let contentType = body?.getContentType() {
                request.addValue(contentType, forHTTPHeaderField: "Content-Type")
            }
        }

        headers.forEach { (header, value) in
            request.setValue(value, forHTTPHeaderField: header)
        }

        return session.dataTask(with: request)
    }

    ///
    /// Parses the result of a URLSessionTask completion handler into a Flex-standard `Response`, or throws a `RequestError`.
    ///
    public func parseNetworkResponse(originalRequestParameters: RequestParameters, responseData: Data?, httpURLResponse: HTTPURLResponse?, requestError: Error?) throws -> Response {
        if let httpURLResponse = httpURLResponse {
            return Response(
                status: httpURLResponse.statusCode,
                rawData: responseData,
                headers: httpURLResponse.allHeaderFields,
                asString: responseData.flatMap({ data in String(data: data, encoding: .utf8) }),
                requestParameters: originalRequestParameters
            )
        } else if let requestError = requestError {
            if (requestError as NSError).code == NSURLErrorDataNotAllowed || (requestError as NSError).code == NSURLErrorNotConnectedToInternet {
                // No Internet code
                throw RequestError.noInternet(requestError)
            } else if (requestError as NSError).code == NSURLErrorCancelled {
                // Cancelled NSError code
                throw RequestError.cancelledByCaller
            } else if (requestError as NSError).code == NSURLErrorTimedOut {
                throw RequestError.requestTimedOut
            } else {
                throw RequestError.miscURLSessionError(requestError)
            }
        } else {
            assert(false, "nil response and nil error")
            throw RequestError.unknownError(message: "Nil response and nil error in completion handler")
        }
    }

    ///
    /// Runs a synchronous HTTP request.
    ///
    /// You may specify any `method` supported by `URLRequest`.
    /// The `path` should be an absolute URL, or else a `RequestError.invalidURL` error will be thrown.
    ///
    /// For a GET request body, you may pass:
    /// - nil, corresponding to a lack of a query string.
    /// - A shallow dictionary, which will be serialized into a URL-encoded query string.
    ///
    /// For a POST/PATCH request body, you may pass:
    /// - nil, corresponding to an empty request body.
    /// - A shallow dictionary, which will be interpreted as URL-encoded form data, with the 'Content-Type' header defaulting to `application/x-www-form-urlencoded` unless otherwise specified in `headers`.
    /// - An instance of `JSONEncodable`, which is populated with an instance of an `Encodable`-conforming type. The instance will be encoded and passed as JSON data, with the 'Content-Type' header defaulting to `application/json` unless otherwise specified in `headers`.
    /// - An instance of `RawBody`, which will pass through a `Data` object, with the 'Content-Type' header set to whatever is specified in the RawBody instance, unless otherwise specified in `headers`.
    /// - (*if the 'FlexNetworking/SwiftyJSON' subpod is installed*) A deep `JSON` instance, which will be passed as JSON data, with the 'Content-Type' header defaulting to `application/json` unless otherwise specified in `headers`.
    ///
    /// Headers are specified as a dictionary.
    /// If a 'Content-Type' header is specified, it will overwrite the 'Content-Type' taken from the `body` parameter, if present.
    ///
    /// Returns a `Response` or throws a miscellaneous error, which may be a `RequestError`, or any error thrown from a member of `preRequestHooks` or `postRequestHooks`.
    ///
    /// Authorization and a default endpoint URL can be implemented via `preRequestHooks`.
    /// Token refresh can be implemented via `postRequestHooks`.
    /// Custom functionality that does not fit in `preRequestHooks` or `postRequestHooks` can be implemented by creating an extension of FlexNetworking with methods adopting the signatures you need, and delegating to internal FlexNetworking methods from those extension methods.
    ///
    public func runRequest(path: String, method: RequestMethod, body: RequestBody?, headers: [String: String] = [:], progressObserver: ((Float) -> Void)? = nil) throws -> Response {
        let sema = DispatchSemaphore(value: 0)
        var blockResult: Result<Response>!
        self.runRequestAsync(path: path, method: method, body: body, headers: headers, progressObserver: progressObserver) { (result) in
            blockResult = result
            sema.signal()
        }
        sema.wait()
        guard let actualResult = blockResult else {
            assert(false, "failure")
            throw RequestError.unknownError(message: "wtf")
        }
        switch actualResult {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        }
    }

    ///
    /// Runs a synchronous HTTP request, skipping any hooks defined in `preRequestHooks` or `postRequestHooks`.
    ///
    /// You may specify any `method` supported by `URLRequest`.
    /// The `path` should be an absolute URL, or else a `RequestError.invalidURL` error will be thrown.
    ///
    /// For a GET request body, you may pass:
    /// - nil, corresponding to a lack of a query string.
    /// - A shallow dictionary, which will be serialized into a URL-encoded query string.
    ///
    /// For a POST/PATCH request body, you may pass:
    /// - nil, corresponding to an empty request body.
    /// - A shallow dictionary, which will be interpreted as URL-encoded form data, with the 'Content-Type' header defaulting to `application/x-www-form-urlencoded` unless otherwise specified in `headers`.
    /// - An instance of `JSONEncodable`, which is populated with an instance of an `Encodable`-conforming type. The instance will be encoded and passed as JSON data, with the 'Content-Type' header defaulting to `application/json` unless otherwise specified in `headers`.
    /// - An instance of `RawBody`, which will pass through a `Data` object, with the 'Content-Type' header set to whatever is specified in the RawBody instance, unless otherwise specified in `headers`.
    /// - (*if the 'FlexNetworking/SwiftyJSON' subpod is installed*) A deep `JSON` instance, which will be passed as JSON data, with the 'Content-Type' header defaulting to `application/json` unless otherwise specified in `headers`.
    ///
    /// Headers are specified as a dictionary.
    /// If a 'Content-Type' header is specified, it will overwrite the 'Content-Type' taken from the `body` parameter, if present.
    ///
    /// Returns a `Response` or throws a `RequestError`.
    ///
    public func runRequestWithoutHooks(session: URLSession, path: String, method: RequestMethod, body: RequestBody?, headers: [String: String] = [:], progressObserver: ((Float) -> Void)? = nil) throws -> Response {
        let sema = DispatchSemaphore(value: 0)
        var blockResult: Result<Response>!
        self.runRequestWithoutHooksAsync(path: path, method: method, body: body, headers: headers, progressObserver: progressObserver) { (result) in
            blockResult = result
            sema.signal()
        }
        sema.wait()
        guard let actualResult = blockResult else {
            assert(false, "failure")
            throw RequestError.unknownError(message: "wtf")
        }
        switch actualResult {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        }
    }

    public func runRequestWithoutHooksAsync(path: String, method: RequestMethod, body: RequestBody?, headers: [String: String] = [:], progressObserver: ((Float) -> Void)? = nil, completion: ResultBlock?) {
        let wrapperCompletion: ResultBlock = { result in
            DispatchQueue.main.async {
                completion?(result)
            }
        }

        self.dispatchQueue.async {
            do {
                let id = UUID().uuidString
                self.responseObservers[id] = { response, error in
                    if let response = response {
                        wrapperCompletion(.success(response))
                    } else if let error = error {
                        wrapperCompletion(.failure(error))
                    } else {
                        assert(false)
                    }
                }
                self.requestParamatersMap[id] = (session: self.session, path: path, method: method, body: body, headers: headers)
                if let progressObserver = progressObserver {
                    self.progressObservers[id] = { progress in
                        DispatchQueue.main.async {
                            progressObserver(progress)
                        }
                    }
                }

                let task = try self.getTaskForRequest(
                    path: path,
                    method: method,
                    body: body,
                    headers: headers
                )
                task.taskDescription = id
                task.resume()
            } catch let error {
                wrapperCompletion(.failure(error))
            }
        }
    }

    ///
    /// Runs an HTTP request asynchronously with no cancel mechanism.
    ///
    /// You may specify any `method` supported by `URLRequest`.
    /// The `path` should be an absolute URL, or else a `RequestError.invalidURL` error will be thrown.
    ///
    /// For a GET request body, you may pass:
    /// - nil, corresponding to a lack of a query string.
    /// - A shallow dictionary, which will be serialized into a URL-encoded query string.
    ///
    /// For a POST/PATCH request body, you may pass:
    /// - nil, corresponding to an empty request body.
    /// - A shallow dictionary, which will be interpreted as URL-encoded form data, with the 'Content-Type' header defaulting to `application/x-www-form-urlencoded` unless otherwise specified in `headers`.
    /// - An instance of `JSONEncodable`, which is populated with an instance of an `Encodable`-conforming type. The instance will be encoded and passed as JSON data, with the 'Content-Type' header defaulting to `application/json` unless otherwise specified in `headers`.
    /// - An instance of `RawBody`, which will pass through a `Data` object, with the 'Content-Type' header set to whatever is specified in the RawBody instance, unless otherwise specified in `headers`.
    /// - (*if the 'FlexNetworking/SwiftyJSON' subpod is installed*) A deep `JSON` instance, which will be passed as JSON data, with the 'Content-Type' header defaulting to `application/json` unless otherwise specified in `headers`.
    ///
    /// Headers are specified as a dictionary.
    /// If a 'Content-Type' header is specified, it will overwrite the 'Content-Type' taken from the `body` parameter, if present.
    ///
    /// `completion` will be called exactly once with a `Result<Response>` monad encoding either a `Response` or a miscellaneous error, which may be a `RequestError`, or any error thrown from a member of `preRequestHooks` or `postRequestHooks`.
    ///
    /// Authorization and a default endpoint URL can be implemented via `preRequestHooks`.
    /// Token refresh can be implemented via `postRequestHooks`.
    /// Custom functionality that does not fit in `preRequestHooks` or `postRequestHooks` can be implemented by creating an extension of FlexNetworking with methods adopting the signatures you need, and delegating to internal FlexNetworking methods from those extension methods.
    /// If you need a cancel mechanism, look into the 'FlexNetworking/RxSwift' subpod.
    ///
    public func runRequestAsync(path: String, method: RequestMethod, body: RequestBody?, headers: [String: String] = [:], progressObserver: ((Float) -> Void)? = nil, completion: ResultBlock?) {
        let wrapperCompletion: ResultBlock = { result in
            DispatchQueue.main.async {
                completion?(result)
            }
        }

        self.dispatchQueue.async {
            do {
                let startingRequestParameters: RequestParameters = (self.session, path, method, body, headers)
                let finalRequestParameters = try self.preRequestHooks.reduce(startingRequestParameters) { (requestParameters, hook) -> RequestParameters in
                    return try hook.execute(on: startingRequestParameters)
                }

                var responseHandler: ((Response, Int) throws -> Void)!
                responseHandler = { response, index in
                    guard index < self.postRequestHooks.count else {
                        wrapperCompletion(.success(response))
                        return
                    }
                    let hook = self.postRequestHooks[index]
                    let result = try hook.execute(lastResponse: response, originalRequestParameters: finalRequestParameters)

                    switch result {
                    case .completed:
                        wrapperCompletion(.success(response))
                    case .continue:
                        try responseHandler(response, index + 1)
                    case .makeNewRequest(let (_, path, method, body, headers)):
                        self.runRequestWithoutHooksAsync(path: path, method: method, body: body, headers: headers, progressObserver: progressObserver, completion: { result in
                            do {
                                switch result {
                                case .success(let response):
                                    try responseHandler(response, index + 1)
                                case .failure(let error):
                                    wrapperCompletion(.failure(error))
                                }
                            } catch let error {
                                wrapperCompletion(.failure(error))
                            }
                        })
                    }
                }

                self.runRequestWithoutHooksAsync(
                    path: finalRequestParameters.path,
                    method: finalRequestParameters.method,
                    body: finalRequestParameters.body,
                    headers: finalRequestParameters.headers,
                    progressObserver: progressObserver,
                    completion: { result in
                        do {
                            switch result {
                            case .success(let response):
                                try responseHandler(response, 0)
                            case .failure(let error):
                                wrapperCompletion(.failure(error))
                            }
                        } catch let error {
                            wrapperCompletion(.failure(error))
                        }
                    }
                )
            } catch let error {
                wrapperCompletion(.failure(error))
            }
        }
    }

    ///
    /// Creates a Single observable corresponding to the result of a FlexNetworking request where the request body is specified as a JSON-encoded Codable.
    /// When the returned Single is disposed, it cancels the task corresponding to the request initiated by the observable.
    ///
    /// You can specify an `encoder` or `decoder` to customize JSON encoding and decoding behavior.
    /// If either is nil, or omitted (equivalent), the default encoder from the parent FlexNetworking instance will simply be used.
    ///
    /// If you specify a non-JSONEncoder instance for `encoder`, please ensure you specify a corresponding `contentType` as well, as the `Content-Type` header will otherwise be overwritten by `application/json`.
    ///
    public func requestCodableAsync<InputDTO: Encodable, OutputDTO: Decodable>(
        encoder: JSONEncoder? = nil,
        contentType: String = "application/json",
        decoder: JSONDecoder? = nil,
        path: String,
        method: RequestMethod,
        codableBody body: InputDTO,
        headers: [String: String] = [:],
        progressObserver: ((Float) -> Void)? = nil,
        completion: ((Result<OutputDTO>) -> Void)?
    ) {
        let wrapperCompletion = { (result: Result<OutputDTO>) in
            DispatchQueue.main.async {
                completion?(result)
            }
        }

        let usableEncoder = encoder ?? self.defaultEncoder
        let usableDecoder = decoder ?? self.defaultDecoder

        do {
            let data = try usableEncoder.encode(body)
            let body: RequestBody = RawBody(data: data, contentType: contentType)
            self.runRequestAsync(path: path, method: method, body: body, headers: headers, progressObserver: progressObserver) { (result) in
                switch result {
                case .success(let response):
                    do {
                        let output = try OutputDTO.decode(from: response, using: usableDecoder)
                        wrapperCompletion(.success(output))
                    } catch let error {
                        let wrappedError = DecodingError(outputDTOTypeName: String(describing: OutputDTO.self), error: error, response: response)
                        wrapperCompletion(.failure(wrappedError))
                    }
                case .failure(let error):
                    wrapperCompletion(.failure(error))
                }
            }
        } catch let error {
            wrapperCompletion(.failure(error))
        }
    }

    ///
    /// Creates a Single observable corresponding to the result of a FlexNetworking request where the result is automatically decoded as a specified Decodable type.
    /// When the returned Single is disposed, it cancels the task corresponding to the request initiated by the observable.
    ///
    /// You can specify a `decoder` to customize JSON decoding behavior.
    /// If nil, or omitted (equivalent), the default decoder from the parent FlexNetworking instance will simply be used.
    ///
    public func requestCodableAsync<OutputDTO: Decodable>(
        decoder: JSONDecoder? = nil,
        path: String,
        method: RequestMethod,
        body: RequestBody?,
        headers: [String: String] = [:],
        progressObserver: ((Float) -> Void)? = nil,
        completion: ((Result<OutputDTO>) -> Void)?
    ) {
        let wrapperCompletion = { (result: Result<OutputDTO>) in
            DispatchQueue.main.async {
                completion?(result)
            }
        }

        let usableDecoder = decoder ?? self.defaultDecoder

        self.runRequestAsync(path: path, method: method, body: body, headers: headers, progressObserver: progressObserver) { (result) in
            switch result {
            case .success(let response):
                do {
                    let output = try OutputDTO.decode(from: response, using: usableDecoder)
                    wrapperCompletion(.success(output))
                } catch let error {
                    let wrappedError = DecodingError(outputDTOTypeName: String(describing: OutputDTO.self), error: error, response: response)
                    wrapperCompletion(.failure(wrappedError))
                }
            case .failure(let error):
                wrapperCompletion(.failure(error))
            }
        }
    }

    // MARK: - Rx Stub

    /// Provides reactive versions of `FlexNetworking` methods.
    /// Accessed via the `rx` property on a `FlexNetworking` instance, which is only available if the 'FlexNetworking/RxSwift' subpod is installed.
    public class Rx {
        internal let flex: FlexNetworking

        internal init(flex: FlexNetworking) {
            self.flex = flex
        }
    }

    internal lazy var _rx = Rx(flex: self)
}

extension FlexNetworking: URLSessionDataDelegate, URLSessionDownloadDelegate {

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let taskID = downloadTask.taskDescription else {
            return
        }

        self.progressObservers[taskID]?(Float(totalBytesWritten) / Float(totalBytesExpectedToWrite))
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let taskID = dataTask.taskDescription, response.expectedContentLength != SwiftNSURLResponseUnknownLength {
            self.expectedDataLength[taskID] = response.expectedContentLength
        }
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let taskID = dataTask.taskDescription else {
            return
        }

        if self.dataSoFar[taskID] == nil {
            self.dataSoFar[taskID] = Data()
        }
        self.dataSoFar[taskID]?.append(data)
        let progress: Float
        if let expectedLength = self.expectedDataLength[taskID] {
            progress = Float(self.dataSoFar[taskID]?.count ?? 0) / Float(expectedLength)
        } else {
            progress = -1
        }

        // only forward data to the observer if it comes from a "successful" response
        // defined as 200 <= status < 400; however, progress is reported on all statuses
        if let statusCode = (dataTask.response as? HTTPURLResponse)?.statusCode, 200 ..< 400 ~= statusCode {
            self.dataObservers[taskID]?(data)
        }
        self.progressObservers[taskID]?(progress)
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let taskID = downloadTask.taskDescription else {
            return
        }

        guard let originalRequestParameters = self.requestParamatersMap[taskID] else {
            assert(false, "originalRequestParameters are missing for \(taskID)")
            return
        }

        do {
            let response = try self.parseNetworkResponse(
                originalRequestParameters: originalRequestParameters,
                responseData: try Data(contentsOf: location),
                httpURLResponse: downloadTask.response as? HTTPURLResponse,
                requestError: nil
            )
            self.responseObservers[taskID]?(response, nil)
        } catch let error {
            self.responseObservers[taskID]?(nil, error)
        }
        self.cleanup(taskID: taskID)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let taskID = task.taskDescription else {
            return
        }

        guard let originalRequestParameters = self.requestParamatersMap[taskID] else {
            assert(false, "originalRequestParameters are missing for \(taskID)")
            return
        }

        guard error != nil || !(task is URLSessionDownloadTask) else {
            // completion will be handled in didFinishDownloadTo
            return
        }

        do {
            let response = try self.parseNetworkResponse(
                originalRequestParameters: originalRequestParameters,
                responseData: self.dataSoFar[taskID],
                httpURLResponse: task.response as? HTTPURLResponse,
                requestError: error
            )
            self.responseObservers[taskID]?(response, nil)
        } catch let error {
            self.responseObservers[taskID]?(nil, error)
        }
        self.cleanup(taskID: taskID)
    }

    private func cleanup(taskID: String) {
        self.requestParamatersMap[taskID] = nil
        self.dataSoFar[taskID] = nil
        self.expectedDataLength[taskID] = nil
        self.responseObservers[taskID] = nil
        self.dataObservers[taskID] = nil
        self.progressObservers[taskID] = nil
    }

}

public enum RequestMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
    case head = "HEAD"
    case options = "OPTIONS"
    case connect = "CONNECT"
    case trace = "TRACE"
}
