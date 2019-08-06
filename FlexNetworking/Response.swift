//
//  Response.swift
//  FlexNetworking
//
//  Created by Dennis Lysenko on 6/27/18.
//  Copyright © 2018 Dennis Lysenko. All rights reserved.
//

import Foundation

public struct Response: CustomStringConvertible {
    public let status: Int

    public let rawData: Data?
    // allows to get case-insensitive headers -- see: https://bugs.swift.org/browse/SR-2429
    public let headers: NSDictionary
    public let asString: String?

    public let requestParameters: RequestParameters

    public var description: String {
        let bodyDescription: String
        if let string = self.asString {
            let trimmedString = String(string.prefix(4096))
            bodyDescription = "\(trimmedString)\(string.count > 4096 ? "..." : "")"
        } else if let data = self.rawData {
            bodyDescription = "\(data.count) bytes"
        } else {
            bodyDescription = "(null body)"
        }

        return "Response(status=\(self.status)):\n\(bodyDescription)"
    }
}
