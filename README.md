# Installation

## Cocoapods

```ruby
pod 'FlexNetworking', '~> 1.0'

# optionally:

pod 'FlexNetworking/SwiftyJSON', '~> 1.0' 
# automatically parses JSON responses using SwiftyJSON

pod 'FlexNetworking/RxSwift', '~> 1.0'
# provides properly disposable Single operations for making requests
```

# What is FlexNetworking?

FlexNetworking is a modern, convenient, Codable-optimized, Rx-enabled networking library that is built specifically for apps that make safe calls to APIs while avoiding boilerplate. We, the developers, have been using it in production since the very first version for networking-heavy client apps and constantly evolving it to fit what we do better. So far, it has been used in three social networking apps and two team-based content creation apps.

Let's keep this short and check out some usage first.

# Usage

```swift
// asynchronous usage
AppNetworking.runRequestAsync(path: "/conversations/\(conversation.id)/messages", method: "POST", body: ["text": text]) { result in 
    // note that you did not have to pass your api endpoint or auth info to your networking instance 
    // because you have configured this FlexNetworking instance for your API.

    switch result {
    case .success(let response) where response.status == 200:
        // use response.asJSON, response.asString, or response.rawData
        if let id = response.asJSON?["id"].string, let text = response.asJSON?["text"].string {
            self.messages.append(Message(id: id, text: text))
        }
    case .success(let response):
        // probably internal server error, bad request error or permission/auth error

        print("bad response: \(response)")
        // ^ this logs response status, body, and request details to help diagnose
    case .failure(let error):
        switch error {
        case RequestError.noInternet:
            SVProgressHUD.showError(withStatus: "No internet. Please check your connection and try again")

        case RequestError.cancelledByCaller:
            break // do not show error if cancelled by user

        default:
            print("error making request: \(error)")
            SVProgressHUD.showError(withStatus: "Error. Please try again later")
        }
    }
}

// synchronous usage
let response = try AppNetworking.runRequest(path: "/users/\(user.id)/profile-picture", method: "GET", body: nil)
if response.status == 200, let data = response.rawData {
    profileImageView.image = UIImage(data: data) // this is a really bad example, please use SDWebImage for images...
} else {
    print("Bad response status getting user's profile picture; details in \(response)")
}

// rx + codable usage. this is where flex really shines
struct SearchFilters: Codable {
    var query: String? = nil
    var minimumScore: Int = 0
}

let userDefinedFilters = SearchFilters(query: "programming", minimumScore: 1)

FlexNetworking.rx.requestCodable(path: "/users/\(user.id)/posts/search", method: "GET", codableBody: userDefinedFilters)
    .subscribe(onSuccess: { [weak self] (posts: [Post]) in 
        // automatically called on main queue, but you can of course change this by calling observeOn(_:) with another scheduler
        guard let `self` = self else { return }
        self.posts = posts
        self.collectionView.reloadData()
    }, onError: { (error) in
        Log.e("Error getting posts with search filters:", error)
        // SEE: section labeled "Benefit: Detailed Errors" below
    }).disposed(by: viewModel.disposeBag)

```

These are the parameters you can pass to request methods:
- `session`: a `URLSession` to run the request on
- `path`: the URL of the page you want to request
- `method`: any HTTP method (GET, POST, PUT, PATCH, DELETE...)
- `body`: 
  - for a querystring (GET) request: a `Dictionary` instance
  - for any other request: a `Dictionary`, `RawBody(data:contentType:)`, or `JSON` (if `FlexNetworking/SwiftyJSON subpod is installed`).
- `headers`: dictionary of request headers

You can either call everything like `FlexNetworking().runRequest` or create an instance like:

```
let APINetworking = FlexNetworking(...)
```

and call things with `APINetworking.runRequest(...)`. The latter option is much better in practice because it allows you to keep several instances with their own configurations and hooks...more on that later. For now, I have to tell you about why I made yet another networking library.

# Why??

The original motivation three or four years ago was simple. We hated boilerplate. We loved Swift. I disliked libraries that didn't use Swift effectively. 

Unlike other libraries which were either inflexible or not "swifty" enough... *(looking at you, Alamofire, with your optional-arg, objective-C style callbacks, where you aren't technically guaranteed to have data OR an error, and everyone deals with this one of three different ways, often within the same project even though the Swift team made a fantastic, powerful enum implementation 🙄)*
... Flex would allow you to run any type of network request, any way you want it, in the Swiftiest way possible: with an enum-backed `Result` monad for asynchronous calls, and a throwing non-optional return value for synchronous calls.

Later, we found ourselves using a LOT of `Codable` and a LOT of `Rx` and decided to build them into this library as first class citizens, so we basically can't even fathom using any other library for our Rx-based and Codable-based apps now.

Finally, the error handling is amazing and a lot better than other libs we've used in the past. We have specifically built the thrown errors and the `Response` structs so that it is easy to diagnose what exactly went wrong by just logging the error or the response, because we were pissed about opaque errors that didn't provide enough information to diagnose based on logs, leading to bugs being shelved and left unresolved ("no repro case"). Hours of troubleshooting can be avoided with 5 minutes of work on the implementation (that's literally how long adding the requestParameters to the response struct took me, and it has already saved me hours and tons of frustration).

Logging an error will give you its specific category (including "noInternet" instead of `code == -1020` and "cancelledByCaller" instead of `code == -999`) so you can handle certain ones specifically (e.g. queue an operation to retry if the internet connection cuts out) or just log them so troubleshooting is easier when issues eventually do crop up. 

Logging a response will tell you its status, body, and all original parameters that formed the URL request that was actually executed.

## More Detail on Detailed Errors

The basic process of making a request throws a closed set of errors (UNLESS you throw your own errors in pre-and-post- request hooks. more on that later)

These are members of the enum `RequestError` and fall into six categories:
- `.noInternet(Error)`
- `.cancelledByCaller`
- `.miscURLSessionError(Error)` (wraps an error directly from URLSession unless one of the two above)
- `.invalidURL(message: String)` (will specify the invalid URL string)
- `.emptyResponseError(Response)` (includes response status + request parameters)
- `.unknownError(message: String)`

`FlexNetworking+RxSwift` expands upon this by also introducing a `DecodingError` struct, which is used in `.rx.requestCodable`. If an error is encountered while decoding the output type you were expecting from the request, an instance of `DecodingError` will be cascaded down the observer chain. **Printing this instance will give you context about the request parameters, the response (including status), and the exact error that the decoder ran into while attempting to decode the output type.**

# Configuration

Flex also lets you specify pre- and post- request hooks on a per-instance basis. 

## Pre-request hooks

**Pre-request hooks** let you globally modify the request parameters (URL session, request URL, HTTP method, request body, and request headers) before a request is made. Common use cases include:
- prepending an API endpoint to all requests made by an instance of `FlexNetworking` specifically made for API calls
- passing token headers to all requests made by an instance of `FlexNetworking` specifically made for API calls
- logging request parameters

Pre-request hooks simply conform to the `PreRequestHook` protocol and define a function that maps one value of `RequestParameters` to another. The predefined conforming class is `BlockPreRequestHook` which takes a custom block, allowing you to implement your own logic. Pre-request hooks are run in the order in which they are passed to `FlexNetworking.init`. If you want to apply more sophisticated pre-request logic, you may define your own type that conforms to the `PreRequestHook` protocol. There will be one instance of your hook, and it will live through the lifetime of the `FlexNetworking` instance it is hooked to, so you can use this to your advantage if you need to maintain additional state between requests. 

## Post-request hooks

**Post-request hooks** let you implement post-request logic that handles when a request is successfully executed but returns a recoverable error that you would like to automatically recover from. Common use cases include:
- initiating token refresh automatically when a request fails due to an expired token and retrying the original request that surfaced the fact that the token expired (semi-transactional)
- exponential backoff in the event of rate limiting
- logging notable responses

Post-request hooks simply conform to the `PostRequestHook` protocol and define a function that maps the latest `Response` and the initial `RequestParameters` (from the pre-request hooks) to one of three actions: 
- `continue` - continue to the next item in the chain, passing the response through to the next hook. *(you might use this to apply some side effects and be on your merry way with the same response)*
- `makeNewRequest(RequestParameters)` - make a new request and run the next hook on the response from this request. *(if the request fails to complete, no more hooks will run.)*
- `completed` - skip the rest of the chain, passing the latest response all the way through to the original caller.

The predefined conforming class is `BlockPostRequestHook`, which, as before, takes a custom block. Post-request hooks are run in the order in which they are passed to `FlexNetworking.init`, with the caveat that part of the chain will be skipped if it ever encounters the `.completed` command. 

If you want to apply more sophisticated post-request logic than a simple block allows, you may define your own type that conforms to the `PostRequestHook` protocol. Bear in mind that there will be one instance of your hook, and it will live through the lifetime of the `FlexNetworking` instance it is hooked to, so you can use this to your advantage if you need to maintain additional state between requests. 

**Note that requests made from post-request hooks do not have pre-request hooks run on them.**

**NB:** Both the Rx and standard bindings use concurrent dispatch queues for scheduling the hooks so if you sleep within a hook, you will only block the (non-main) thread on which the request is being made. If you develop more sophisticated hooks, **please make sure that their `execute` methods are thread-safe**, and please follow good concurrency practices: synchronize access where necessary, but keep synchronized operations to a minimum to avoid bottlenecks.

**Tip:** you may throw at any point in pre- and post-request hooks, which will halt the request then and there and bubble the error all the way back up to the caller.

## Why request hooks?? Why don't we just make custom methods that call FlexNetworking in the body?

These request hooks, especially the post-request hooks, are designed such that they are a series of well-defined operations on clearly structured input data producing clearly structured output data, making them potentially agnostic to the actual implementation you use make the request. 

In simpler terms, whether you use the normal throwing synchronous request method, the asynchronous request method, or the Rx bindings (really, Rx is the crucial part), all your pre- and post-request hooks will run without having to change any of the logic. They are simply things that return a changed version of immutable data. They may keep their own state which, again, is 100% agnostic of the internal methods you are using to make HTTP requests.

You can still make custom methods that call FlexNetworking in the body, I don't mind - but using pre- and post- request hooks means that, not only can you mix Rx and non-Rx without any method overriding, but we can also keep adding new bindings (like the Rx one) and new method signatures in the future and you will be able to use them out of the box forever, as long as we don't change the definition of "request parameters". *(And even if we do, you will only have one place to change it per hook.)*

## Examples of hooks doing useful stuff

Here are examples of pre- and post-request hooks that implement some of the use cases above (**prepending an endpoint, passing token headers, and initiating token refresh automatically**).

```swift
// with flex, you can specify encoders and decoders for Codable requests.
// if we are using a JSON Spring backend, for example, we may want to pass Date objects as millisecond timestamps.
let defaultEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .millisecondsSince1970
    return encoder
}()

let defaultDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    return decoder
}()

let AppNetworking = FlexNetworking(
    preRequestHooks: [
        BlockPreRequestHook { (requestParameters) in
            // mutate path to allow us to use relative API paths
            // and send authorization header with every request when present
            let (session, path, method, body, headers) = requestParameters

            var additionalHeaders = headers

            if ActiveUser.isLoggedIn {
                additionalHeaders["Authorization"] = "Bearer \(ActiveUser.token)"
            }

            return (session, Constants.apiEndpoint.appending(path), method, body, additionalHeaders)
        }
    ],
    postRequestHooks: [
        BlockPostRequestHook { (response, originalRequestParameters) -> PostRequestHookResult in
            let (session, path, _, _, _) = originalRequestParameters

            if response.status == 401, let refreshToken = ActiveUser.refreshToken {
                // do token refresh if we got a 401
                let loginRequestParameters: RequestParameters = (
                    session: session,
                    path: Constants.apiEndpoint.appending("/token-refresh"),
                    method: "POST",
                    body: ["refreshToken": refreshToken],
                    headers: [:]
                )

                return .makeNewRequest(loginRequestParameters)
            } else {
                return .completed
            }
        },
        BlockPostRequestHook { (tokenRefreshResponse, originalRequestParameters) -> PostRequestHookResult in
            guard let rawData = loginResponse.rawData else {
                throw SimpleError(message: "no data in token refresh login response")
            }

            do {
                let tokenRefreshDTO = try defaultDecoder.decode(TokenRefreshDTO.self, from: rawData)

                let token = tokenRefreshDTO.token
                ActiveUser.token = token

                var headers = originalRequestParameters.headers
                headers["Authorization"] = "Bearer \(token)"

                // copy the original request from before the token refresh, 
                // but add the new token to the headers
                var retryRequestParameters = originalRequestParameters
                retryRequestParameters.headers = headers

                return .makeNewRequest(retryRequestParameters)
            } catch let error {
                Log.e(error)

                // TODO: kick the user back to a login screen

                throw error // rethrow to caller
            }
        }
    ],
    defaultEncoder: defaultEncoder,
    defaultDecoder: defaultDecoder
)
```

# TODO

- The Rx integration has really good handling of request cancellation, but the non-Rx version does not. We should explore ways to address that.
- Eventually address authentication in a more comprehensive way, and possibly bundle common hooks that are useful for common auth schemes
- Codable request/response integration for non-Rx
- MULTIPART!!!
- **Whatever you think is important: please leave an issue!**

# Authors

- [Dennis Lysenko](https://github.com/dennislysenko)
- [Andriy Katkov](https://github.com/akatkov7/Peasants-Medieval-Siege)
