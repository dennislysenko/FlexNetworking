//
//  RequestError.swift
//  FlexNetworking
//
//  Created by Dennis Lysenko on 6/27/18.
//  Copyright © 2018 Dennis Lysenko. All rights reserved.
//

import Foundation

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

public struct DecodingError: Error, CustomNSError {
    public let outputDTOTypeName: String
    public let error: Error
    public let response: Response

    public static var errorDomain: String {
        return "DecodingError"
    }

    public var errorCode: Int {
        return 1
    }

    public var errorUserInfo: [String : Any] {
        return [
            "outputDTOTypeName": outputDTOTypeName,
            "underlyingError": String(describing: error),
            "underlyingErrorDescription": error.localizedDescription,
            "response": String(describing: response)
        ]
    }
}
