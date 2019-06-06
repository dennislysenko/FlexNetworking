//
//  FlexNetworking+SwiftyJSON.swift
//  FlexNetworking
//
//  Created by Dennis Lysenko on 5/16/18.
//  Copyright © 2018 Dennis Lysenko. All rights reserved.
//

import Foundation
import SwiftyJSON

extension Response {
    public var asJSON: JSON? {
        return rawData.flatMap({ data in try? JSON(data: data, options: .allowFragments) })
    }
}

/// Convenience to let you easily pass a SwiftyJSONJSON object as a request body.
/// JSON should only be used with non-GET requests. If you need to pass a shallow dictionary, simply pass the dictionary.
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
