//
//  Result.swift
//  FlexNetworking
//
//  Created by Dennis Lysenko on 6/27/18.
//  Copyright © 2018 Dennis Lysenko. All rights reserved.
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
