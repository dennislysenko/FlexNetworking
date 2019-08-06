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
    public func runRequestWithoutHooks(path: String, method: String, body: RequestBody?, headers: [String: String] = [:], dataObserver: AnyObserver<Data>? = nil, progressObserver: AnyObserver<Float>? = nil) -> Single<Response> {
        return Single<Response>.create(subscribe: { observer in
            do {
                let id = UUID().uuidString
                let request: ReplaySubject<Response> = ReplaySubject.createUnbounded()
                self.flex.responseObservers[id] = { response, error in
                    if let response = response {
                        dataObserver?.onCompleted()

                        request.onNext(response)
                        request.onCompleted()
                    } else if let error = error {
                        dataObserver?.onError(error)

                        request.onError(error)
                    } else {
                        assert(false)
                    }
                }
                self.flex.requestParamatersMap[id] = (session: self.flex.session, path: path, method: method, body: body, headers: headers)
                if let dataObserver = dataObserver {
                    self.flex.dataObservers[id] = { data in
                        dataObserver.onNext(data)
                    }
                }
                if let progressObserver = progressObserver {
                    self.flex.progressObservers[id] = { progress in
                        progressObserver.onNext(progress)
                        if progress == 1 {
                            progressObserver.onCompleted()
                        }
                    }
                }

                let task = try self.flex.getTaskForRequest(
                    session: self.flex.session,
                    path: path,
                    method: method,
                    body: body,
                    headers: headers,
                    completionHandler: nil
                )
                task.taskDescription = id
                task.resume()

                return request
                    .do(onDispose: { [weak task] in
                        task?.cancel()
                    })
                    .asSingle().subscribe(observer)
            } catch let error {
                observer(.error(error))
                return Disposables.create()
            }
        }).subscribeOn(ConcurrentDispatchQueueScheduler(queue: self.flex.dispatchQueue))
    }

    ///
    /// Creates a Single observable corresponding to the result of a FlexNetworking request.
    /// When the returned Single is disposed, it cancels the task corresponding to the request initiated by the observable.
    ///
    public func runRequest(path: String, method: String, body: RequestBody?, headers: [String: String] = [:], progressObserver: AnyObserver<Float>? = nil) -> Single<Response> {
        let getFinalRequestParameters = Single<RequestParameters>.create(subscribe: { observer in
            do {
                let startingRequestParameters: RequestParameters = (self.flex.session, path, method, body, headers)
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
                path: finalRequestParameters.path,
                method: finalRequestParameters.method,
                body: finalRequestParameters.body,
                headers: finalRequestParameters.headers,
                progressObserver: progressObserver
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
                case .makeNewRequest(let (_, path, method, body, headers)):
                    let nextResponse = self.runRequestWithoutHooks(path: path, method: method, body: body, headers: headers, progressObserver: progressObserver)
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
        encoder: JSONEncoder? = nil,
        contentType: String = "application/json",
        decoder: JSONDecoder? = nil,
        path: String,
        method: String,
        codableBody body: InputDTO,
        headers: [String: String] = [:],
        progressObserver: AnyObserver<Float>? = nil
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
            return self.runRequest(path: path, method: method, body: body, headers: headers, progressObserver: progressObserver)
        })

        let output = response
            .observeOn(ConcurrentDispatchQueueScheduler(queue: DispatchQueue.global(qos: .default)))
            .map({ response -> OutputDTO in
                do {
                    let output = try OutputDTO.decode(from: response, using: usableDecoder)
                    return output
                } catch let error {
                    throw DecodingError(outputDTOTypeName: String(describing: OutputDTO.self), error: error, response: response)
                }
            })

        return output.observeOn(MainScheduler.instance)
    }

    ///
    /// Creates a Single observable corresponding to the result of a FlexNetworking request where the result is automatically decoded as a specified Decodable type.
    /// When the returned Single is disposed, it cancels the task corresponding to the request initiated by the observable.
    ///
    /// You can specify a `decoder` to customize JSON decoding behavior.
    /// If nil, or omitted (equivalent), the default decoder from the parent FlexNetworking instance will simply be used.
    ///
    public func requestCodable<OutputDTO: Decodable>(
        decoder: JSONDecoder? = nil,
        path: String,
        method: String,
        body: RequestBody?,
        headers: [String: String] = [:],
        progressObserver: AnyObserver<Float>? = nil
    ) -> Single<OutputDTO> {

        let usableDecoder = decoder ?? self.flex.defaultDecoder

        let response = self.runRequest(path: path, method: method, body: body, headers: headers, progressObserver: progressObserver)

        let output = response
            .observeOn(ConcurrentDispatchQueueScheduler(queue: DispatchQueue.global(qos: .default)))
            .map({ response -> OutputDTO in
                do {
                    let output = try OutputDTO.decode(from: response, using: usableDecoder)
                    return output
                } catch let error {
                    throw DecodingError(outputDTOTypeName: String(describing: OutputDTO.self), error: error, response: response)
                }
            })

        return output.observeOn(MainScheduler.instance)
    }
}
