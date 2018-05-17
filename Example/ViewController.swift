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

/// Basically where we house unit tests because Xcode is being so difficult about testing a framework.
class ViewController: UIViewController {

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
    }
}

