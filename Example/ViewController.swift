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

    @IBOutlet weak var statusLabel: UILabel!

    private let bigDownloadURL = "https://16683.mc.tritondigital.com/NPR_510289/media-session/6b5a9388-72c8-4aee-b30b-6a58bc893ae7/anon.npr-mp3/npr/pmoney/2018/03/20180316_pmoney_pmpod454rerun.mp3?orgId=1&d=1274&p=510289&story=594317012&t=podcast&e=594317012&ft=pod&f=510289"

    private var disposeBag = DisposeBag()
    private var hasStartedDownload = false

    @IBAction func startDownloadTapped(_ sender: Any) {
        guard !self.hasStartedDownload else {
            return
        }
        self.hasStartedDownload = true

        let progressObserver2_rx = AnyObserver<Float>.init { (event) in
            switch event {
            case .next(let progress):
                self.statusLabel.text = "Progress: \(Int(100 * progress))%"
            default:
                break
            }
        }

        FlexNetworking().rx.runRequest(path: self.bigDownloadURL, method: .get, body: nil, progressObserver: progressObserver2_rx)
            .subscribe(onSuccess: { [weak self] (response) in
                guard let sSelf = self else { return }
                sSelf.statusLabel.text = "Download successful!"
                sSelf.hasStartedDownload = false
            }, onError: { [weak self] (error) in
                guard let sSelf = self else { return }
                sSelf.statusLabel.text = "Download failed!"
                sSelf.hasStartedDownload = false
                print("error downloading file: ", error)
            }).disposed(by: self.disposeBag)
    }

    private var task: FlexTask?
    @IBAction func startNormalDownloadTapped(_ sender: Any) {
        self.task = FlexNetworking().runRequestWithoutHooksAsync(path: self.bigDownloadURL, method: .get, body: nil, progressObserver: { progress in
            self.statusLabel.text = "Progress: \(Int(100 * progress))%"
        }, completion: { (result) in
            switch result {
            case .success(let response):
                print("downloaded file: ", response)
            case .failure(let error):
                print("error downloading file: ", error)
            }
        })
    }

    @IBAction func cancelDownloadTapped(_ sender: Any) {
        guard self.hasStartedDownload else {
            return
        }
        self.hasStartedDownload = false
        self.task?.cancel()
        self.disposeBag = DisposeBag()
        DispatchQueue.main.async {
            self.statusLabel.text = "Download cancelled!"
        }
    }
}

