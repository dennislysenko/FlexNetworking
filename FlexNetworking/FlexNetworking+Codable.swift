//
//  FlexNetworking+Codable.swift
//  FlexNetworking
//
//  Created by Dennis Lysenko on 5/16/18.
//  Copyright © 2018 Dennis Lysenko. All rights reserved.
//

import Foundation

public struct JSONEncodable<E: Encodable>: RequestBody {
    public let data: Data

    public init(_ encodable: E, using encoder: JSONEncoder) throws {
        self.data = try encoder.encode(encodable)
    }

    public func getQueryString() -> String? {
        assert(false, "Do not use JSONEncodable with a GET request")
        return nil
    }

    public func getHTTPBody() -> Data? {
        return self.data
    }

    public func getContentType() -> String {
        return "application/json"
    }
}

extension Decodable {
    public static func decode(from response: Response, using decoder: JSONDecoder) throws -> Self {
        guard let data = response.rawData else {
            throw RequestError.emptyResponseError(response)
        }

        return try decoder.decode(Self.self, from: data)
    }
}
