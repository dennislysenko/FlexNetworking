//
//  FlexNetworking+RxSwift.swift
//  FlexNetworking
//
//  Created by Dennis Lysenko on 5/16/18.
//  Copyright © 2018 Dennis Lysenko. All rights reserved.
//

import Foundation
import RxSwift

// This extension ensures that the public `rx` sub-namespace is only accessible when sub-pod 'FlexNetworking/RxSwift' is installed.
extension FlexNetworking {
    ///
    /// Returns a clone of FlexNetworking that provides RxSwift-compatible bindings for all request functions.
    ///
    public var rx: FlexNetworking.Rx {
        return _rx
    }
}

extension FlexNetworking.Rx {
    ///
    /// Creates a Single observable corresponding to the result of a FlexNetworking request where pre-request and post-request hooks are omitted.
    /// When the returned Single is disposed, it cancels the task corresponding to the request initiated by the observable.
    ///
    public func runRequestWithoutHooks(urlSession session: URLSession = .shared, path: String, method: String, body: RequestBody?, headers: [String: String] = [:]) -> Single<Response> {
        return Single<Response>.create(subscribe: { observer in
            do {
                let task = try self.flex.getTaskForRequest(
                    urlSession: session,
                    path: path,
                    method: method,
                    body: body,
                    headers: headers,
                    completionHandler: { (data, response, error) in
                        do {
                            observer(.success(try self.flex.parseNetworkResponse(
                                originalRequestParameters: (session, path, method, body, headers),
                                responseData: data,
                                httpURLResponse: response as? HTTPURLResponse,
                                requestError: error)))
                        } catch let error {
                            observer(.error(error))
                        }
                    }
                )

                task.resume()
                
                return Disposables.create(with: { [weak task] in
                    task?.cancel()
                })
            } catch let error {
                observer(.error(error))
                return Disposables.create()
            }
        })
    }

    ///
    /// Creates a Single observable corresponding to the result of a FlexNetworking request.
    /// When the returned Single is disposed, it cancels the task corresponding to the request initiated by the observable.
    ///
    public func runRequest(urlSession session: URLSession = .shared, path: String, method: String, body: RequestBody?, headers: [String: String] = [:]) -> Single<Response> {
        let getFinalRequestParameters = Single<RequestParameters>.create(subscribe: { observer in
            do {
                let startingRequestParameters: RequestParameters = (session, path, method, body, headers)
                let finalRequestParameters = try self.flex.preRequestHooks.reduce(startingRequestParameters) { (requestParameters, hook) -> RequestParameters in
                    return try hook.execute(on: requestParameters)
                }
                observer(.success(finalRequestParameters))
            } catch let error {
                observer(.error(error))
            }

            return Disposables.create()
        })

        let getInitialResponse = getFinalRequestParameters.flatMap { finalRequestParameters -> Single<(Response, RequestParameters)> in
            return self.runRequestWithoutHooks(
                urlSession: finalRequestParameters.urlSession,
                path: finalRequestParameters.path,
                method: finalRequestParameters.method,
                body: finalRequestParameters.body,
                headers: finalRequestParameters.headers
            ).map({ response in (response, finalRequestParameters) })
        }

        var lastResponse: Single<(Response, originalRequestParameters: RequestParameters, shouldContinue: Bool)> =
            getInitialResponse.map { (response, originalRequestParameters) in (response, originalRequestParameters, true) }

        for hook in self.flex.postRequestHooks {
            lastResponse = lastResponse.flatMap { (response, originalRequestParameters, shouldContinue) in
                guard shouldContinue else {
                    return Single.just((response, originalRequestParameters, false))
                }

                let result = try hook.execute(lastResponse: response, originalRequestParameters: originalRequestParameters)
                switch result {
                case .completed:
                    return Single.just((response, originalRequestParameters, false))
                case .continue:
                    return Single.just((response, originalRequestParameters, true))
                case .makeNewRequest(let (urlSession, path, method, body, headers)):
                    let nextResponse = self.runRequestWithoutHooks(urlSession: urlSession, path: path, method: method, body: body, headers: headers)
                    return nextResponse.map { response in (response, originalRequestParameters, true) }
                }
            }
        }

        let finalResponse = lastResponse

        return finalResponse
            .map { (response, _, _) in response }
            .observeOn(MainScheduler.instance)
            .subscribeOn(ConcurrentDispatchQueueScheduler(queue: DispatchQueue.global(qos: .default)))
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

    ///
    /// Creates a Single observable corresponding to the result of a FlexNetworking request where the request body is specified as a JSON-encoded Codable.
    /// When the returned Single is disposed, it cancels the task corresponding to the request initiated by the observable.
    ///
    /// You can specify an `encoder` or `decoder` to customize JSON encoding and decoding behavior.
    /// If either is nil, or omitted (equivalent), the default encoder from the parent FlexNetworking instance will simply be used.
    ///
    /// If you specify a non-JSONEncoder instance for `encoder`, please ensure you specify a corresponding `contentType` as well, as the `Content-Type` header will otherwise be overwritten by `application/json`.
    ///
    public func requestCodable<InputDTO: Encodable, OutputDTO: Decodable>(
        urlSession session: URLSession = .shared,
        encoder: JSONEncoder? = nil,
        contentType: String = "application/json",
        decoder: JSONDecoder? = nil,
        path: String,
        method: String,
        codableBody body: InputDTO,
        headers: [String: String] = [:]
    ) -> Single<OutputDTO> {

        let usableEncoder = encoder ?? self.flex.defaultEncoder
        let usableDecoder = decoder ?? self.flex.defaultDecoder

        let data: Single<Data>

        do {
            data = Single.just(try usableEncoder.encode(body))
        } catch let error {
            return Single.error(error)
        }

        let response = data.flatMap({ body -> Single<Response> in
            let body: RequestBody = RawBody(data: body, contentType: "application/json")
            return self.runRequest(urlSession: session, path: path, method: method, body: body, headers: headers)
        })

        let output = response.flatMap({ response -> Single<OutputDTO> in
            do {
                let output = try OutputDTO.decode(from: response, using: usableDecoder)
                return Single.just(output)
            } catch let error {
                return Single.error(DecodingError(outputDTOTypeName: String(describing: OutputDTO.self), error: error, response: response))
            }
        })

        return output
    }

    ///
    /// Creates a Single observable corresponding to the result of a FlexNetworking request where the result is automatically decoded as a specified Decodable type.
    /// When the returned Single is disposed, it cancels the task corresponding to the request initiated by the observable.
    ///
    /// You can specify a `decoder` to customize JSON decoding behavior.
    /// If nil, or omitted (equivalent), the default decoder from the parent FlexNetworking instance will simply be used.
    ///
    public func requestCodable<OutputDTO: Decodable>(
        urlSession session: URLSession = .shared,
        decoder: JSONDecoder? = nil,
        path: String,
        method: String,
        body: RequestBody?,
        headers: [String: String] = [:]
    ) -> Single<OutputDTO> {

        let usableDecoder = decoder ?? self.flex.defaultDecoder

        let response = self.runRequest(urlSession: session, path: path, method: method, body: body, headers: headers)

        let output = response.flatMap({ response -> Single<OutputDTO> in
            do {
                let output = try OutputDTO.decode(from: response, using: usableDecoder)
                return Single.just(output)
            } catch let error {
                return Single.error(DecodingError(outputDTOTypeName: String(describing: OutputDTO.self), error: error, response: response))
            }
        })

        return output
    }

}
