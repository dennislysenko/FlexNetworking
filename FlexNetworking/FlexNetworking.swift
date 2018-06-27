//
//  FlexNetworking
//
//  A common sense sync-or-async networking lib with an ability to get results flexibly.
//

import Foundation

public enum Result<T>: CustomStringConvertible {
    case success(T)
    case failure(Error)
    
    public var description: String {
        switch self {
        case .success(let value):
            return "Success(\(value))"
        case .failure(let error):
            return "Failure(\(String(reflecting: error)))"
        }
    }
}

public typealias ResultBlock = (Result<Response>) -> ()

public enum RequestError: Error, CustomNSError {
    case noInternet(Error)
    case miscURLSessionError(Error)
    case invalidURL(message: String)
    case emptyResponseError(Response)
    case cancelledByCaller
    case unknownError(message: String)

    public var localizedDescription: String {
        switch self {
        case .noInternet(let error):
            return "No internet (underlying error: \(error))"
        case .miscURLSessionError(let error):
            return "Miscellaneous URL session error. Underlying error code: \((error as NSError).code)\n\(error.localizedDescription)"
        case .invalidURL(let message):
            return "Invalid URL. Message: \(message)"
        case .emptyResponseError(let response):
            return "Response had no data; status was \(response.status)"
        case .cancelledByCaller:
            return "Request was cancelled by the caller"
        case .unknownError(let message):
            return "Unknown error. Message: \(message)"
        }
    }

    public static var errorDomain: String {
        return "RequestError"
    }

    public var errorCode: Int {
        return 1
    }

    public var errorUserInfo: [String : Any] {
        return ["description": self.localizedDescription]
    }
}

public protocol RequestBody {
    /// Called for GET requests.
    func getQueryString() -> String?
    
    /// Called for POST requests.
    func getHTTPBody() -> Data?
    
    /// Called for POST requests only.
    func getContentType() -> String
}

let disallowedCharactersSet = CharacterSet(charactersIn: "!*'();:@&=+$,/?%#[] <>")
extension String {
    internal func urlEncoded() -> String? {
        return self.addingPercentEncoding(withAllowedCharacters: disallowedCharactersSet.inverted)
    }
}

extension Dictionary {
    internal func getSerialization() -> String {
        var serialization: [String] = []
        for (key, value) in self {
            let mirror = Mirror(reflecting: value)
            var valueString = "\(value)"
            if let displayStyle = mirror.displayStyle {
                switch displayStyle {
                case .optional:
                    if let some = mirror.children.first {
                        valueString = "\(some.value)"
                    }
                default: break
                }
            }
            
            guard let encodedKey = "\(key)".urlEncoded(), let encodedValue = valueString.urlEncoded() else {
                assert(false, "Error URLEncoding key or value.")
                continue
            }
            
            serialization.append("\(encodedKey)=\(encodedValue)")
        }

        return serialization.joined(separator: "&")
    }
}

extension Dictionary: RequestBody {
    public func getQueryString() -> String? {
        return self.getSerialization()
    }
    
    public func getHTTPBody() -> Data? {
        return self.getSerialization().data(using: .utf8)
    }
    
    public func getContentType() -> String {
        return "application/x-www-form-urlencoded"
    }
}

@available (*, deprecated, message: "Pass Dictionary instance directly instead of wrapping it in a DictionaryBody() constructor.")
public struct DictionaryBody: RequestBody {
    private let queryDict: [String: Any]
    
    public init(_ queryDict: [String: Any]) {
        self.queryDict = queryDict
    }
    
    public func getQueryString() -> String? {
        return self.queryDict.getSerialization()
    }
    
    public func getHTTPBody() -> Data? {
        return self.getQueryString()?.data(using: .utf8)
    }
    
    public func getContentType() -> String {
        return queryDict.getContentType()
    }
}

/// RawBody allows you to specify data bytes with a given content-type, so you can pass any request body (incl. multipart form data).
/// NB: On a GET request, a RawData body WILL be ignored.
public struct RawBody: RequestBody {
    public let data: Data
    public let contentType: String
    
    public init(data: Data, contentType: String) {
        self.data = data
        self.contentType = contentType
    }
    
    public func getQueryString() -> String? {
        assert(false, "Do not use RawData with a GET request")
        return nil
    }
    
    public func getHTTPBody() -> Data? {
        return self.data
    }
    
    public func getContentType() -> String {
        return self.contentType
    }
}

public struct Response: CustomStringConvertible {
    public let status: Int
    
    public let rawData: Data?
    public let asString: String?

    public let requestParameters: RequestParameters
    
    public var description: String {
        let bodyDescription: String
        if let string = self.asString {
            bodyDescription = string
        } else if let data = self.rawData {
            bodyDescription = "\(data.count) bytes"
        } else {
            bodyDescription = "(null body)"
        }
        
        return "Response(status=\(self.status)):\n\(bodyDescription)"
    }
}

public typealias RequestParameters = (urlSession: URLSession, path: String, method: String, body: RequestBody?, headers: [String: String])

public protocol PreRequestHook {
    func execute(on requestParameters: RequestParameters) throws -> RequestParameters
}

public struct BlockPreRequestHook: PreRequestHook {
    public typealias Block = (RequestParameters) throws -> RequestParameters

    public let block: Block

    public init(block: @escaping Block) {
        self.block = block
    }

    public func execute(on requestParameters: RequestParameters) throws -> RequestParameters {
        return try block(requestParameters)
    }
}

public enum PostRequestHookResult {
    /// Continues to the next hook in the chain, passing the unmodified last response as input to it.
    case `continue`

    /// Skips the rest of the chain, passing the current response to whatever completion handler was specified on the initial request.
    case completed

    /// Makes a new request, and passes the result of that request to the next post-request hook.
    case makeNewRequest(RequestParameters)
}

public protocol PostRequestHook {
    func execute(lastResponse: Response, originalRequestParameters: RequestParameters) throws -> PostRequestHookResult
}

public struct BlockPostRequestHook: PostRequestHook {
    public typealias Block = (_ lastResponse: Response, _ originalRequestParameters: RequestParameters) throws -> PostRequestHookResult

    public let block: Block

    public init(block: @escaping Block) {
        self.block = block
    }

    public func execute(lastResponse: Response, originalRequestParameters: RequestParameters) throws -> PostRequestHookResult {
        return try block(lastResponse, originalRequestParameters)
    }
}

public class FlexNetworking {
    public let preRequestHooks: [PreRequestHook]
    public let postRequestHooks: [PostRequestHook]

    public let defaultEncoder: JSONEncoder
    public let defaultDecoder: JSONDecoder

    static let `default` = FlexNetworking()

    public init(preRequestHooks: [PreRequestHook] = [],
        postRequestHooks: [PostRequestHook] = [],
        defaultEncoder: JSONEncoder = JSONEncoder(),
        defaultDecoder: JSONDecoder = JSONDecoder()) {

        self.preRequestHooks = preRequestHooks
        self.postRequestHooks = postRequestHooks
        self.defaultEncoder = defaultEncoder
        self.defaultDecoder = defaultDecoder
    }

    // MARK: - Request Methods

    ///
    /// Creates a URLSessionTask for a single HTTP request with request parameters specified in FlexNetworking notation.
    ///
    public func getTaskForRequest(urlSession session: URLSession, path: String, method: String, body: RequestBody?, headers: [String: String] = [:], completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) throws -> URLSessionTask {
        guard let url = URL(string: path) else {
            throw RequestError.invalidURL(message: "Invalid URL \(path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method

        if method == "GET" {
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

        return session.dataTask(with: request, completionHandler: completionHandler)
    }

    ///
    /// Parses the result of a URLSessionTask completion handler into a Flex-standard `Response`, or throws a `RequestError`.
    ///
    public func parseNetworkResponse(originalRequestParameters: RequestParameters, responseData: Data?, httpURLResponse: HTTPURLResponse?, requestError: Error?) throws -> Response {
        if let httpURLResponse = httpURLResponse {
            return Response(
                status: httpURLResponse.statusCode,
                rawData: responseData,
                asString: responseData.flatMap({ data in String(data: data, encoding: .utf8) }),
                requestParameters: originalRequestParameters
            )
        } else if let requestError = requestError {
            if (requestError as NSError).code == -1020 {
                // No Internet code
                throw RequestError.noInternet(requestError)
            } else if (requestError as NSError).code == -999 {
                // Cancelled NSError code
                throw RequestError.cancelledByCaller
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
    public func runRequest(urlSession session: URLSession, path: String, method: String, body: RequestBody?, headers: [String: String] = [:]) throws -> Response {
        let startingRequestParameters: RequestParameters = (session, path, method, body, headers)
        let finalRequestParameters = try preRequestHooks.reduce(startingRequestParameters) { (requestParameters, hook) -> RequestParameters in
            return try hook.execute(on: startingRequestParameters)
        }

        let initialResponse = try self.runRequestWithoutHooks(
            urlSession: finalRequestParameters.urlSession,
            path: finalRequestParameters.path,
            method: finalRequestParameters.method,
            body: finalRequestParameters.body,
            headers: finalRequestParameters.headers)

        var lastResponse = initialResponse

        for hook in self.postRequestHooks {
            let result = try hook.execute(lastResponse: lastResponse, originalRequestParameters: finalRequestParameters)

            var breakLoop = false

            switch result {
            case .completed:
                breakLoop = true
            case .continue:
                continue
            case .makeNewRequest(let (urlSession, path, method, body, headers)):
                lastResponse = try self.runRequestWithoutHooks(urlSession: urlSession, path: path, method: method, body: body, headers: headers)
            }

            if breakLoop {
                break
            }
        }

        let finalResponse = lastResponse

        return finalResponse
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
    public func runRequestWithoutHooks(urlSession session: URLSession, path: String, method: String, body: RequestBody?, headers: [String: String] = [:]) throws -> Response {
        let sema = DispatchSemaphore(value: 0)

        var httpURLResponse: HTTPURLResponse?
        var requestError: Error?
        var responseData: Data?

        let task = try self.getTaskForRequest(
            urlSession: session,
            path: path,
            method: method,
            body: body,
            headers: headers,
            completionHandler: { (data: Data?, urlResponse: URLResponse?, error: Error?) -> Void in
                responseData = data
                httpURLResponse = urlResponse as? HTTPURLResponse
                requestError = error

                sema.signal()
            }
        )

        task.resume()
        let _ = sema.wait(timeout: DispatchTime.distantFuture)

        return try self.parseNetworkResponse(
            originalRequestParameters: (session, path, method, body, headers),
            responseData: responseData,
            httpURLResponse: httpURLResponse,
            requestError: requestError
        )
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
    public func runRequestAsync(_ urlSession: URLSession, path: String, method: String, body: RequestBody?, headers: [String: String] = [:], completion: ResultBlock?) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let response = try self.runRequest(urlSession: urlSession, path: path, method: method, body: body)
                DispatchQueue.main.async {
                    completion?(.success(response))
                }
            } catch let error {
                DispatchQueue.main.async {
                    completion?(.failure(error))
                }
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
