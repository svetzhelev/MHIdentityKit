//
//  AccessTokenResponseHandler.swift
//  MHIdentityKit
//
//  Created by Milen Halachev on 6/1/17.
//  Copyright © 2017 Milen Halachev. All rights reserved.
//

import Foundation

//https://tools.ietf.org/html/rfc6749#section-5.1
//https://tools.ietf.org/html/rfc6749#section-5.2

///Handles an HTTP response in attempt to produce an access token or error as defined
public struct AccessTokenResponseHandler {
    
    public func handle(data: Data?, response: URLResponse?, error: Error?) throws -> AccessTokenResponse {
        
        //if there is an error - throw it
        if let error = error {
            
            throw error
        }
        
        //if response is unknown - throw an error
        guard let response = response as? HTTPURLResponse else {
            
            throw MHIdentityKitError.Reason.unknownURLResponse
        }
        
        //parse the data
        guard
        let data = data,
        let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        else {
            
            throw MHIdentityKitError.Reason.unableToParseData
        }
        
        //if the error is one of the defined in the OAuth2 framework - throw it
        if let error = ErrorResponse(json: json) {
            
            throw error
        }
        
        //make sure the response code is success 2xx
        guard (200..<300).contains(response.statusCode) else {
            
            throw MHIdentityKitError.Reason.unknownHTTPResponse(code: response.statusCode)
        }
        
        //parse the access token
        guard let accessTokenResponse = AccessTokenResponse(json: json) else {
            
            throw MHIdentityKitError.Reason.unableToParseAccessToken
        }
        
        return accessTokenResponse
    }
}