//
//  FlexNetworkingTests.swift
//  FlexNetworkingTests
//
//  Created by Andriy Katkov on 11/3/18.
//  Copyright © 2018 Dennis Lysenko. All rights reserved.
//

import XCTest
import OHHTTPStubs
@testable import FlexNetworking

let everything: OHHTTPStubsTestBlock = { _ in true }

@discardableResult func stub(_ condition: @escaping OHHTTPStubsTestBlock, _ response: @escaping OHHTTPStubsResponseBlock) -> OHHTTPStubsDescriptor {
    return stub(condition: condition, response: response)
}

func http(_ statusCode: Int32) -> OHHTTPStubsResponseBlock {
    return { _ in OHHTTPStubsResponse(data: Data(), statusCode: statusCode, headers: nil) }
}

func stringResponse(_ string: String) -> OHHTTPStubsResponseBlock {
    return { _ in OHHTTPStubsResponse(data: string.data(using: .utf8)!, statusCode: 200, headers: nil) }

}

class FlexNetworkingTests: XCTestCase {

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
        networking.runRequestAsync(path: self.sampleURL, method: .get, body: nil) { (result) in
            switch result {
            case .success(let response):
                responseExpecation.fulfill()
                XCTAssertEqual(response.status, 200, "non-200 response status")
            case .failure(let error):
                XCTFail("error: \(error)")
            }
        }
        waitForExpectations(timeout: 1.0, handler: nil)
    }

    func test_runRequestAsync_WithoutHooks() {
        stub(everything, http(200))

        let networking = FlexNetworking()

        let responseExpecation = expectation(description: "responseExpecation")
        networking.runRequestAsync(path: self.sampleURL, method: .get, body: nil) { (result) in
            switch result {
            case .success(let response):
                responseExpecation.fulfill()
                XCTAssertEqual(response.status, 200, "non-200 response status")
            case .failure(let error):
                XCTFail("error: \(error)")
            }
        }
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
        networking.runRequestWithoutHooksAsync(path: self.sampleURL, method: .get, body: nil) { (result) in
            switch result {
            case .success(let response):
                responseExpecation.fulfill()
                XCTAssertEqual(response.status, 200, "non-200 response status")
            case .failure(let error):
                XCTFail("error: \(error)")
            }
        }
        waitForExpectations(timeout: 0.1, handler: nil)
    }

    func test_runRequestWithoutHooksAsync_WithoutHooks() {
        stub(everything, http(200))

        let networking = FlexNetworking()

        // try a normal runRequestAsync with an empty hooks list
        let responseExpecation = expectation(description: "responseExpecation")
        networking.runRequestWithoutHooksAsync(path: self.sampleURL, method: .get, body: nil) { (result) in
            switch result {
            case .success(let response):
                responseExpecation.fulfill()
                XCTAssertEqual(response.status, 200, "non-200 response status")
            case .failure(let error):
                XCTFail("error: \(error)")
            }
        }
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
        networking.requestCodableAsync(path: self.sampleURL, method: .get, body: nil) { (result: Result<TestCodable>) in
            switch result {
            case .success(let testCodable):
                XCTAssertEqual(testCodable.title, "my title")
                XCTAssertEqual(testCodable.number, 300)
                responseExpecation.fulfill()
            case .failure(let error):
                XCTFail("error: \(error)")
            }
        }
        waitForExpectations(timeout: 1.0, handler: nil)
    }

    func test_runRequest_WithProgress() {
        let data = Data.init(count: 100 * 1000)
        stub(everything) { (req) -> OHHTTPStubsResponse in
            return OHHTTPStubsResponse(data: data, statusCode: 200, headers: nil).responseTime(-40)
        }

        let networking = FlexNetworking()

        let progressExpectation = expectation(description: "progressExpectation")
        progressExpectation.expectedFulfillmentCount = 10
        let responseExpecation = expectation(description: "responseExpecation")
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let response = try networking.runRequest(path: self.sampleURL, method: .get, body: nil, progressObserver: { _ in
                    progressExpectation.fulfill()
                })
                XCTAssertEqual(response.status, 200, "non-200 response status")
                XCTAssertEqual(response.rawData, data, "non-matching response data")
                responseExpecation.fulfill()
            } catch let error {
                XCTFail("error: \(error)")
            }
        }
        waitForExpectations(timeout: 5.0, handler: nil)
    }

    func test_getQueryString() {
        let body1 = ["test": "test2"]
        XCTAssertEqual(body1.getQueryString(), "test=test2")

        let dict1: [String: Any] = ["test": 2]
        XCTAssertEqual(dict1.getQueryString(), "test=2")

        let dict2: [String: Any?] = ["test": 2]
        XCTAssertEqual(dict2.getQueryString(), "test=2")
    }
}
