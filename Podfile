use_frameworks!
inhibit_all_warnings!

def common_pods
    pod "SwiftyJSON", "~> 5"
    pod "RxSwift", "~> 5"
end

target 'FlexNetworking' do
    common_pods
    platform :ios, '10.0'
end

target 'Example' do
    platform :ios, '10.0'
end

target 'FlexNetworkingMac' do
    common_pods
    platform :osx, '10.10'
end

target 'ExampleMac' do
    platform :osx, '10.10'
end

target 'FlexNetworkingTests' do
    platform :ios, '10.0'

    pod "OHHTTPStubs/Swift", "~> 6.1.0"
end
