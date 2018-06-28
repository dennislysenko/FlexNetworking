//
//  RequestBody.swift
//  FlexNetworking
//
//  Created by Dennis Lysenko on 6/27/18.
//  Copyright © 2018 Dennis Lysenko. All rights reserved.
//

import Foundation

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
