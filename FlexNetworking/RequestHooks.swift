//
//  RequestHooks.swift
//  FlexNetworking
//
//  Created by Dennis Lysenko on 6/27/18.
//  Copyright © 2018 Dennis Lysenko. All rights reserved.
//

import Foundation

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
