use_frameworks!

def common_pods
    pod "SwiftyJSON", "~> 3.1.0"
    pod "RxSwift", "~> 4.1.2"
end

target 'FlexNetworking' do
    common_pods
    platform :ios, '10.0'
end

target 'Example' do
    common_pods
    platform :ios, '10.0'
end

target 'FlexNetworkingMac' do
    common_pods
    platform :osx, '10.10'
end

target 'ExampleMac' do
    platform :osx, '10.10'
    common_pods
end
