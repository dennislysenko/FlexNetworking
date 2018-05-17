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

public enum RequestError: Error {
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

open class FlexNetworking {
    open class func getTaskForRequest(urlSession session: URLSession, path: String, method: String, body: RequestBody?, headers: [String: String] = [:], completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) throws -> URLSessionTask {
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

    open class func parseNetworkResponse(responseData: Data?, httpURLResponse: HTTPURLResponse?, requestError: Error?) throws -> Response {
        if let httpURLResponse = httpURLResponse {
            return Response(
                status: httpURLResponse.statusCode,
                rawData: responseData,
                asString: responseData.flatMap({ data in String(data: data, encoding: .utf8) })
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

    open class func runRequest(urlSession session: URLSession, path: String, method: String, body: RequestBody?, headers: [String: String] = [:]) throws -> Response {
        let sema = DispatchSemaphore(value: 0)

        var httpURLResponse: HTTPURLResponse?
        var requestError: Error?
        var responseData: Data?
        let task = try self.getTaskForRequest(urlSession: session, path: path, method: method, body: body, headers: headers) { (data: Data?, urlResponse: URLResponse?, error: Error?) -> Void in
            responseData = data
            httpURLResponse = urlResponse as? HTTPURLResponse
            requestError = error

            sema.signal()
        }

        task.resume()
        let _ = sema.wait(timeout: DispatchTime.distantFuture)

        return try self.parseNetworkResponse(responseData: responseData, httpURLResponse: httpURLResponse, requestError: requestError)
    }
}

// MARK: - Async Network Methods
extension FlexNetworking {
    public class func runRequestAsync(_ urlSession: URLSession, path: String, method: String, body: RequestBody?, headers: [String: String] = [:], completion: ResultBlock?) {
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
}
