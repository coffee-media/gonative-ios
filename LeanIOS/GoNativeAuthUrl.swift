//
//  GoNativeAuthUrl.swift
//  GoNativeIOS
//
//  Created by Weiyin He on 7/11/16.
//  Copyright © 2016 GoNative.io LLC. All rights reserved.
//

import Foundation

public class GoNativeAuthUrl : NSObject {
    var currentUrl: NSURL?
    var allowedUrlRegexes: [NSPredicate]
    
    override init() {
        let appConfig = GoNativeAppConfig.sharedAppConfig()
        self.allowedUrlRegexes = LEANUtilities.createRegexArrayFromStrings(appConfig.authAllowedUrls);
    }
    
    func isUrlAllowed(url: String?) -> Bool {
        if (url == nil) {
            return true
        }
        
        for regex in self.allowedUrlRegexes {
            if regex.evaluateWithObject(url) {
                return true
            }
        }
        
        return false
    }
    
    @objc
    func handleUrl(url: NSURL, callback: (postUrl: String?, postData: [String:AnyObject]?)->Void) -> Void {
        if url.scheme != "gonative" || url.host != "auth" {
            return
        }
        
        if url.path == nil {
            return
        }
        
        if self.currentUrl != nil {
            // check current url against allowed
            let currentUrlString = self.currentUrl!.absoluteString
            if (!self.isUrlAllowed(currentUrlString)) {
                NSLog("URL not allowed to access auth: %@", currentUrlString)
                return
            }
        }
        
        var queryDict = [String:String]()
        let query = url.query
        if query != nil {
            let queryComponents = query!.componentsSeparatedByString("&")
            for keyValue in queryComponents {
                let pairComponents = keyValue.componentsSeparatedByString("=")
                if pairComponents.count != 2 {
                    continue
                }
                
                let key = pairComponents.first?.stringByRemovingPercentEncoding
                let value = pairComponents.last?.stringByRemovingPercentEncoding
                
                queryDict.updateValue(value!, forKey: key!)
            }
        }
        
        let callbackUrl = queryDict["callback"]
        // check callback url
        if callbackUrl != nil {
            let callbackAbsoluteUrl = NSURL.init(string: callbackUrl!, relativeToURL: self.currentUrl)
            
            if callbackAbsoluteUrl != nil && !self.isUrlAllowed(callbackAbsoluteUrl?.absoluteString) {
                NSLog("Callback URL not allowed to access auth: %@", callbackAbsoluteUrl!.absoluteString)
                return
            }
        }
        
        let path = url.path
        if path == "/status" {
            if (callbackUrl == nil) {
                return
            }
            
            GoNativeKeychain().getStatusAsync({ (statusData:[String : AnyObject]) -> (Void) in
                callback(postUrl: callbackUrl, postData: statusData)
                return
            })
        }
        else if path == "/save" {
            let secret = queryDict["secret"]
            if secret == nil {
                return
            }
            
            GoNativeKeychain().saveSecretAsync(secret!, callback: { (result) -> (Void) in
                if callbackUrl != nil {
                    if result == KeychainOperationResult.Success {
                        callback(postUrl: callbackUrl, postData: ["success": true])
                    } else {
                        callback(postUrl: callbackUrl, postData: [
                            "success": false,
                            "error": result.rawValue
                        ])
                    }
                }
            })
        }
        else if path == "/get" {
            if (callbackUrl == nil) {
                return
            }
            
            let prompt = queryDict["prompt"]
            let callbackOnCancel = queryDict["callbackOnCancel"]
            var doCallbackOnCancel = false
            if callbackOnCancel != nil {
                let lower = callbackOnCancel?.lowercaseString
                if lower != "0" && lower != "false" &&
                    lower != "no" {
                    doCallbackOnCancel = true
                }
            }
            
            GoNativeKeychain().getSecretAsync(prompt) { (result, secret) -> (Void) in
                if result == .Success {
                    callback(postUrl: callbackUrl, postData: [
                        "success": true,
                        "secret": secret == nil ? "" : secret!
                    ])
                } else if !(result == KeychainOperationResult.UserCanceled && !doCallbackOnCancel) {
                    callback(postUrl: callbackUrl, postData: [
                        "success": false,
                        "error": result.rawValue
                    ])
                }
            }
        }
        else if path == "/delete" {
            GoNativeKeychain().deleteSecretAsync({ (result) -> (Void) in
                if callbackUrl != nil {
                    if result == .Success {
                        callback(postUrl: callbackUrl, postData: ["success": true])
                    } else {
                        callback(postUrl: callbackUrl, postData: [
                            "success": false,
                            "error": result.rawValue
                        ])
                    }
                }
            })
        }
    }
}