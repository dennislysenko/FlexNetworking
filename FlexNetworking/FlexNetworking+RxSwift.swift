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
    open class func runRequestRx(urlSession session: URLSession = .shared, path: String, method: String, body: RequestBody?, headers: [String: String] = [:]) -> Single<Response> {
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

    open class func requestCodableRx<Input: Encodable, Output: Decodable>(
        urlSession session: URLSession = .shared,
        encoder: JSONEncoder,
        decoder: JSONDecoder,
        path: String,
        method: String,
        body: Input,
        headers: [String: String] = [:]
    ) -> Single<Output> {

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
        let output = response.flatMap({ response -> Single<Output> in
            do {
                let output = try Output.decode(from: response, using: decoder)
                return Single.just(output)
            } catch let error {
                return Single.error(error)
            }
        })
        return output
    }
}
