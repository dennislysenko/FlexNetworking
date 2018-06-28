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
