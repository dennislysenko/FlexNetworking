//
//  ViewController.swift
//  Example
//
//  Created by Dennis Lysenko on 9/18/17.
//  Copyright © 2017 Dennis Lysenko. All rights reserved.
//

import UIKit
import FlexNetworking
import SwiftyJSON
import RxSwift

/// Basically where we house unit tests because Xcode is being so difficult about testing a framework.
class ViewController: UIViewController {

    private let smallDownloadURL = "http://example.org/"
    private let bigDownloadURL = "https://16683.mc.tritondigital.com/NPR_510289/media-session/6b5a9388-72c8-4aee-b30b-6a58bc893ae7/anon.npr-mp3/npr/pmoney/2018/03/20180316_pmoney_pmpod454rerun.mp3?orgId=1&d=1274&p=510289&story=594317012&t=podcast&e=594317012&ft=pod&f=510289"

    private let disposeBag = DisposeBag()

    override func viewDidLoad() {
        super.viewDidLoad()
        
        test()
    }
    
    func test() {
        let body1 = ["test": "test2"]
        assert(body1.getQueryString() == "test=test2")
        
        let dict1: [String: Any] = ["test": 2]
        assert(dict1.getQueryString() == "test=2")
        
        let dict2: [String: Any?] = ["test": 2]
        assert(dict2.getQueryString() == "test=2")

        let progressObserver1 = BehaviorSubject<Float>(value: 0)
        progressObserver1
            .observeOn(MainScheduler.asyncInstance)
            .subscribe(onNext: { (progress) in
                print(progress)
            }).disposed(by: self.disposeBag)

        FlexNetworking.default.rx.runRequest(path: self.smallDownloadURL, method: "GET", body: nil, progressObserver: progressObserver1.asObserver())
            .subscribe(onSuccess: { (response) in
                print("default: \(response)")
            }, onError: { (error) in
                print("error: ", error)
            }).disposed(by: self.disposeBag)

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            let progressObserver2 = BehaviorSubject<Float>(value: 0)
            progressObserver2
                .observeOn(MainScheduler.asyncInstance)
                .subscribe(onNext: { (progress) in
                    print(progress)
                }).disposed(by: self.disposeBag)

            FlexNetworking().rx.runRequest(path: self.bigDownloadURL, method: "GET", body: nil, progressObserver: progressObserver2.asObserver())
                .subscribe(onSuccess: { (response) in
                    print("new: \(response)")
                }, onError: { (error) in
                    print("error: ", error)
                }).disposed(by: self.disposeBag)
        }
    }
}

