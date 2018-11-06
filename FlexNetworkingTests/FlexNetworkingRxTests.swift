//
//  FlexNetworkingRxTests.swift
//  FlexNetworkingTests
//
//  Created by Andriy Katkov on 11/3/18.
//  Copyright © 2018 Dennis Lysenko. All rights reserved.
//

import XCTest
import OHHTTPStubs
@testable import FlexNetworking

class FlexNetworkingRxTests: XCTestCase {

    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        OHHTTPStubs.removeAllStubs()
    }

    let sampleURL = "http://example.org/"

    func test_runRequestAsync_WithHooks() {
        let preRequestHookExpectation = expectation(description: "preRequestHookExpectation")
        let postRequestHookExpectation = expectation(description: "postRequestHookExpectation")

        stub(everything, http(200))

        let networking = FlexNetworking(
            preRequestHooks: [
                BlockPreRequestHook(block: { (requestParameters) -> RequestParameters in
                    preRequestHookExpectation.fulfill()
                    return requestParameters
                })
            ],
            postRequestHooks: [
                BlockPostRequestHook(block: { (response, requestParameters) -> PostRequestHookResult in
                    postRequestHookExpectation.fulfill()
                    return .continue
                })
            ]
        )

        let responseExpecation = expectation(description: "responseExpecation")
        _ = networking.rx.runRequest(path: self.sampleURL, method: .get, body: nil)
            .subscribe(onSuccess: { (response) in
                responseExpecation.fulfill()
                XCTAssertEqual(response.status, 200, "non-200 response status")
            }, onError: { error in
                XCTFail("error: \(error)")
            })
        waitForExpectations(timeout: 1.0, handler: nil)
    }

    func test_runRequestAsync_WithoutHooks() {
        stub(everything, http(200))

        let networking = FlexNetworking()

        let responseExpecation = expectation(description: "responseExpecation")
        _ = networking.rx.runRequest(path: self.sampleURL, method: .get, body: nil)
            .subscribe(onSuccess: { (response) in
                responseExpecation.fulfill()
                XCTAssertEqual(response.status, 200, "non-200 response status")
            }, onError: { error in
                XCTFail("error: \(error)")
            })
        waitForExpectations(timeout: 1.0, handler: nil)
    }

    func test_runRequestWithoutHooksAsync_WithHooks() {
        let preRequestHookExpectation = expectation(description: "preRequestHookExpectation")
        preRequestHookExpectation.isInverted = true
        let postRequestHookExpectation = expectation(description: "postRequestHookExpectation")
        postRequestHookExpectation.isInverted = true

        stub(everything, http(200))

        let networking = FlexNetworking(
            preRequestHooks: [
                BlockPreRequestHook(block: { (requestParameters) -> RequestParameters in
                    preRequestHookExpectation.fulfill()
                    return requestParameters
                })
            ],
            postRequestHooks: [
                BlockPostRequestHook(block: { (response, requestParameters) -> PostRequestHookResult in
                    postRequestHookExpectation.fulfill()
                    return .continue
                })
            ]
        )

        let responseExpecation = expectation(description: "responseExpecation")
        _ = networking.rx.runRequestWithoutHooks(path: self.sampleURL, method: .get, body: nil)
            .subscribe(onSuccess: { (response) in
                responseExpecation.fulfill()
                XCTAssertEqual(response.status, 200, "non-200 response status")
            }, onError: { error in
                XCTFail("error: \(error)")
            })
        waitForExpectations(timeout: 0.1, handler: nil)
    }

    func test_runRequestWithoutHooksAsync_WithoutHooks() {
        stub(everything, http(200))

        let networking = FlexNetworking()

        // try a normal runRequestAsync with an empty hooks list
        let responseExpecation = expectation(description: "responseExpecation")
        _ = networking.rx.runRequestWithoutHooks(path: self.sampleURL, method: .get, body: nil)
            .subscribe(onSuccess: { (response) in
                responseExpecation.fulfill()
                XCTAssertEqual(response.status, 200, "non-200 response status")
            }, onError: { error in
                XCTFail("error: \(error)")
            })
        waitForExpectations(timeout: 1.0, handler: nil)
    }

    struct TestCodable: Codable {
        let title: String
        let number: Int
    }

    func test_requestCodable() {
        let jsonString = "{\"title\":\"my title\",\"number\":300}"
        stub(everything, stringResponse(jsonString))

        let networking = FlexNetworking()

        // try a normal runRequestAsync with an empty hooks list
        let responseExpecation = expectation(description: "responseExpecation")
        _ = networking.rx.requestCodable(path: self.sampleURL, method: .get, body: nil)
            .subscribe(onSuccess: { (testCodable: TestCodable) in
                responseExpecation.fulfill()
                XCTAssertEqual(testCodable.title, "my title")
                XCTAssertEqual(testCodable.number, 300)
            }, onError: { error in
                XCTFail("error: \(error)")
            })
        waitForExpectations(timeout: 1.0, handler: nil)
    }

}
