//
//  FlexNetworking+RxSwift.swift
//  FlexNetworking
//
//  Created by Dennis Lysenko on 5/16/18.
//  Copyright © 2018 Dennis Lysenko. All rights reserved.
//

import Foundation
import RxSwift

extension FlexNetworking {
    /// Creates a Single observable corresponding to the result of a FlexNetworking request.
    /// When the returned Single is disposed, it cancels the task corresponding to the request initiated by the observable.
    open class func runRequestRxWithoutHooks(urlSession session: URLSession = .shared, path: String, method: String, body: RequestBody?, headers: [String: String] = [:]) -> Single<Response> {
        return Single<Response>.create(subscribe: { observer in
            do {
                let task = try FlexNetworking.getTaskForRequest(
                    urlSession: session,
                    path: path,
                    method: method,
                    body: body,
                    headers: headers,
                    completionHandler: { (data, response, error) in
                        do {
                            observer(.success(try FlexNetworking.parseNetworkResponse(responseData: data, httpURLResponse: response as? HTTPURLResponse, requestError: error)))
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

    open class func runRequestRx(urlSession session: URLSession = .shared, path: String, method: String, body: RequestBody?, headers: [String: String] = [:]) -> Single<Response> {
        let getFinalRequestParameters = Single<RequestParameters>.create(subscribe: { observer in
            do {
                let startingRequestParameters: RequestParameters = (session, path, method, body, headers)
                let finalRequestParameters = try preRequestHooks.reduce(startingRequestParameters) { (requestParameters, hook) -> RequestParameters in
                    return try hook.execute(on: startingRequestParameters)
                }
                observer(.success(finalRequestParameters))
            } catch let error {
                observer(.error(error))
            }

            return Disposables.create()
        })

        let getInitialResponse = getFinalRequestParameters.flatMap { finalRequestParameters -> Single<(Response, RequestParameters)> in
            return self.runRequestRxWithoutHooks(
                urlSession: finalRequestParameters.urlSession,
                path: finalRequestParameters.path,
                method: finalRequestParameters.method,
                body: finalRequestParameters.body,
                headers: finalRequestParameters.headers
            ).map({ response in (response, finalRequestParameters) })
        }

        var lastResponse: Single<(Response, originalRequestParameters: RequestParameters, shouldContinue: Bool)> =
            getInitialResponse.map { (response, originalRequestParameters) in (response, originalRequestParameters, true) }

        for hook in self.postRequestHooks {
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
                    let nextResponse = self.runRequestRxWithoutHooks(urlSession: urlSession, path: path, method: method, body: body, headers: headers)
                    return nextResponse.map { response in (response, originalRequestParameters, true) }
                }
            }
        }

        let finalResponse = lastResponse

        return finalResponse.map { (response, _, _) in response }
    }

    open class func requestCodableRx<InputDTO: Encodable, OutputDTO: Decodable>(
        urlSession session: URLSession = .shared,
        encoder: JSONEncoder = FlexNetworking.defaultEncoder,
        decoder: JSONDecoder = FlexNetworking.defaultDecoder,
        path: String,
        method: String,
        body: InputDTO,
        headers: [String: String] = [:]
    ) -> Single<OutputDTO> {

        let data: Single<Data>

        do {
            data = Single.just(try encoder.encode(body))
        } catch let error {
            return Single.error(error)
        }

        let response = data.flatMap({ body -> Single<Response> in
            let body: RequestBody = RawBody(data: body, contentType: "application/json")
            return runRequestRx(urlSession: session, path: path, method: method, body: body, headers: headers)
        })

        let output = response.flatMap({ response -> Single<OutputDTO> in
            do {
                let output = try OutputDTO.decode(from: response, using: decoder)
                return Single.just(output)
            } catch let error {
                return Single.error(error)
            }
        })

        return output
    }
}
