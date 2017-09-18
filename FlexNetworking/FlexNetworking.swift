//
//  FlexNetworking
//
//  A common sense sync-or-async networking lib with an ability to get results flexibly.
//

import Foundation
import SwiftyJSON

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
    case unknownError
}

public protocol RequestBody {
    /// Called for GET requests.
    func getQueryString() -> String?
    
    /// Called for POST requests.
    func getHTTPBody() -> Data?
    
    /// Called for POST requests only.
    func getContentType() -> String
}

/// Convenience to let you easily pass a JSON object as a request body. JSON should only be used with non-GET requests.
extension JSON: RequestBody {
    public func getQueryString() -> String? {
        assert(false, "Do not use JSON with GET requests.")
        return nil
    }
    public func getHTTPBody() -> Data? {
        return self.rawString()?.data(using: .utf8, allowLossyConversion: false)
    }
    public func getContentType() -> String {
        return "application/json"
    }
}

let disallowedCharactersSet = CharacterSet(charactersIn: "!*'();:@&=+$,/?%#[] <>")
extension String {
    func urlEncoded() -> String? {
        return self.addingPercentEncoding(withAllowedCharacters: disallowedCharactersSet.inverted)
    }
}

extension Dictionary {
    fileprivate func getSerialization() -> String {
        var serialization = ""
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
            
            serialization += "\(encodedKey)=\(encodedValue)&"
        }
        
        if serialization.characters.count > 0 {
            serialization = serialization.substring(to: serialization.characters.index(before: serialization.endIndex))
        }
        
        return serialization
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

public struct DictionaryBody: RequestBody {
    fileprivate var queryDict: [String: Any]
    
    public init(_ queryDict: [String: Any]) {
        self.queryDict = queryDict
    }
    
    public func getQueryString() -> String? {
        return self.queryDict.getSerialization()
    }
    
    public func getHTTPBody() -> Data? {
        return self.getQueryString()?.data(using: String.Encoding.utf8)
    }
    
    public func getContentType() -> String {
        return "application/x-www-form-urlencoded"
    }
}

/// RawData is a special case. It is always directly written to the HTTP body and you must specify your own Content-Type. This gives you full control over the body of the request.
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
    public let asJSON: JSON?
    
    public var description: String {
        let bodyDescription: String
        if let json = self.asJSON {
            bodyDescription = "\(json)"
        } else if let string = self.asString {
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
    open class func runRequest(urlSession session: URLSession, path: String, method: String, body: RequestBody?) throws -> Response {
        let sema = DispatchSemaphore(value: 0)
        
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
        
        var httpURLResponse: HTTPURLResponse?
        var requestError: Error?
        var responseData: Data?
        let task = session.dataTask(with: request, completionHandler: { (data: Data?, urlResponse: URLResponse?, error: Error?) -> Void in
            responseData = data
            httpURLResponse = urlResponse as? HTTPURLResponse
            requestError = error
            
            sema.signal()
        }) 
        
        task.resume()
        let _ = sema.wait(timeout: DispatchTime.distantFuture)
        
        let response: Response
        if let httpURLResponse = httpURLResponse {
            let status = httpURLResponse.statusCode
            var asString: String? = nil
            var asJSON: JSON? = nil
            
            if let responseData = responseData {
                if let stringResponse = NSString(data: responseData, encoding: String.Encoding.utf8.rawValue) {
                    asString = String(stringResponse)
                }
                
                if let jsonSerialization = try? JSONSerialization.jsonObject(with: responseData, options: .allowFragments) {
                    asJSON = JSON(jsonSerialization)
                }
            }
            
            response = Response(status: status, rawData: responseData, asString: asString, asJSON: asJSON)
        } else if let requestError = requestError {
            if (requestError as NSError).code == -1020 {
                // No Internet code
                throw RequestError.noInternet(requestError)
            } else {
                throw RequestError.miscURLSessionError(requestError)
            }
        } else {
            assert(false, "Nil response and nil error :(")
            throw RequestError.unknownError
        }
        
        return response
    }
}

// MARK: - Async Network Methods
extension FlexNetworking {
    public class func runRequestAsync(_ urlSession: URLSession, path: String, method: String, body: RequestBody?, completion: ResultBlock?) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let response = try self.runRequest(urlSession: urlSession, path: path, method: method, body: body)
                DispatchQueue.main.async { completion?(.success(response)) }
            } catch let error {
                DispatchQueue.main.async { completion?(.failure(error)) }
            }
        }
    }
}
