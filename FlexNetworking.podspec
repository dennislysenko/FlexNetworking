#
# Be sure to run `pod lib lint FlexNetworking.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'FlexNetworking'
  s.version          = '0.2.0'
  s.summary          = 'A common sense sync-or-async networking lib with an ability to get results flexibly.'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
Unlike other libraries which are either inflexible or not swifty enough (by our standards), Flex allows you to run any type of network request, any way you want it, in the Swiftiest way possible.
Examples will be added to README later. I'm just putting this up so I can use it in a project because I've tried the networking alternatives and they all have glaring issues for my use case.
Reach out to Dennis via email (dennis.s.lysenko AT gmail.com) if you have any question about how to do something using this lib and I\'ll add it to the README.
                       DESC

  s.homepage         = 'https://github.com/riffdigital/FlexNetworking'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Dennis Lysenko' => 'dennis.s.lysenko@gmail.com' }
  s.source           = { :git => 'https://github.com/riffdigital/FlexNetworking.git', :tag => s.version.to_s }
  s.social_media_url = 'https://twitter.com/dennislysenko'

  s.ios.deployment_target = '8.0'

  s.source_files = 'FlexNetworking/FlexNetworking.swift'
  
  # s.resource_bundles = {
  #   'FlexNetworking' => ['FlexNetworking/Assets/*.png']
  # }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  # s.frameworks = 'UIKit', 'MapKit'
  s.dependency 'SwiftyJSON', '~> 3.1.0'
end
