//
//  AuthorizationCodeGrantFlow.swift
//  MHIdentityKit
//
//  Created by Milen Halachev on 27.03.18.
//  Copyright © 2018 Milen Halachev. All rights reserved.
//

import Foundation

//https://tools.ietf.org/html/rfc6749#section-4.1
open class AuthorizationCodeGrantFlow: AuthorizationGrantFlow {
    
    open let authorizationEndpoint: URL
    open let tokenEndpoint: URL
    open let clientID: String
    open let redirectURI: URL?
    open let scope: Scope?
    open let state: AnyHashable?
    open let clientAuthorizer: RequestAuthorizer?
    open let userAgent: UserAgent
    open let networkClient: NetworkClient

    public init(authorizationEndpoint: URL, tokenEndpoint: URL, clientID: String, redirectURI: URL?, scope: Scope?, state: AnyHashable?, clientAuthorizer: RequestAuthorizer?, userAgent: UserAgent, networkClient: NetworkClient = _defaultNetworkClient) {

        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.scope = scope
        self.state = state
        self.clientAuthorizer = clientAuthorizer
        self.userAgent = userAgent
        self.networkClient = networkClient
    }
    
    //MARK: - Flow logic
    
    open func parameters(from authorizationRequest: AuthorizationRequest) -> [String: Any] {
        
        return authorizationRequest.dictionary
    }
    
    open func parameters(from accessTokenRequest: AccessTokenRequest) -> [String: Any] {
        
        return accessTokenRequest.dictionary
    }
    
    open func data(from parameters: [String: Any]) -> Data? {
        
        return parameters.urlEncodedParametersData
    }
    
    open func urlRequest(from authorizationRequest: AuthorizationRequest) -> URLRequest {
        
        let parameters = self.parameters(from: authorizationRequest)
        let url = self.authorizationEndpoint +?! parameters
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        return request
    }
    
    open func urlRequest(from accessTokenRequest: AccessTokenRequest) -> URLRequest {
        
        var request = URLRequest(url: self.tokenEndpoint)
        request.httpMethod = "POST"
        request.httpBody = self.data(from: self.parameters(from: accessTokenRequest))
        
        return request
    }
    
    open func authorize(accesTokenURLRequest: URLRequest, handler: @escaping (URLRequest, Error?) -> Void) {
        
        guard let clientAuthorizer = self.clientAuthorizer else {
            
            handler(accesTokenURLRequest, nil)
            return
        }

        clientAuthorizer.authorize(request: accesTokenURLRequest, handler: handler)
    }
    
    open func perform(_ request: URLRequest, redirectURI: URL?, redirectionHandler: @escaping (URLRequest) throws -> Bool) {
        
        self.userAgent.perform(request, redirectURI: redirectURI, redirectionHandler: redirectionHandler)
    }
    
    open func perform(_ request: URLRequest, completion: @escaping (NetworkResponse) -> Void) {
        
        self.networkClient.perform(request, completion: completion)
    }
    
    open func authorizationResponse(from request: URLRequest) throws -> AuthorizationResponse {
        
        guard
        let url = request.url,
        let parameters = url.query?.urlDecodedParameters
        else {
            
            throw MHIdentityKitError.authenticationFailed(reason: MHIdentityKitError.Reason.invalidAuthorizationResponse)
        }
        
        //if the error is one of the defined in the OAuth2 framework - throw it
        if let error = ErrorResponse(parameters: parameters) {
            
            throw error
        }
        
        guard let code = parameters["code"] else {
            
            throw MHIdentityKitError.authenticationFailed(reason: MHIdentityKitError.Reason.invalidAuthorizationResponse)
        }
        
        let state = parameters["state"]
        let response = AuthorizationResponse(code: code, state: state)
        return response
    }
    
    open func accessTokenResponse(from networkResponse: NetworkResponse) throws -> AccessTokenResponse {
        
        return try AccessTokenResponseHandler().handle(response: networkResponse)
    }
    
    open func canHandle(redirectRequest: URLRequest) -> Bool {
        
        //if redirectURI is provided
        if let redirectURI = self.redirectURI {
            
            //it must match with the url of the request, by ignoring the query parameters
            guard redirectURI.scheme == redirectRequest.url?.scheme, redirectURI.host == redirectRequest.url?.host, redirectURI.path == redirectRequest.url?.path else {
                
                return false
            }
        }
        
        //the request url must contain either `code` or `error` query parameter
        let parameters = redirectRequest.url?.query?.urlDecodedParameters
        guard parameters?["code"] != nil || parameters?["error"] != nil else {
            
            return false
        }
        
        return true
    }
    
    open func validate(_ accessTokenResponse: AccessTokenResponse) throws {
        
        //nothing to validate here
    }
    
    open func validate(_ authorizationResponse: AuthorizationResponse) throws {
        
        guard authorizationResponse.state == self.state else {
            
            throw MHIdentityKitError.authenticationFailed(reason: MHIdentityKitError.Reason.invalidAuthorizationResponse)
        }
    }
    
    //MARK: - AuthorizationGrantFlow
    
    open func authenticate(handler: @escaping (AccessTokenResponse?, Error?) -> Void) {

        let authorizationRequest = AuthorizationRequest(clientID: self.clientID, redirectURI: self.redirectURI, scope: self.scope, state: self.state)
        let authorizationURLRequest = self.urlRequest(from: authorizationRequest)
        
        self.perform(authorizationURLRequest, redirectURI: self.redirectURI) { [weak self] (redirectRequest) throws -> Bool in

            //utility to fail and complete
            func fail(with error: Error) -> Error  {
                
                handler(nil, error)
                return error
            }
            
            //utility to try or fail and complete
            func orFail<T>(_ closure: @autoclosure () throws -> T) throws -> T {
                
                do {
                    
                    return try closure()
                }
                catch {
                    
                    throw fail(with: error)
                }
            }

            //if self was deallocated, there is no point to continue
            guard let _self = self else {
                
                throw fail(with: MHIdentityKitError.authenticationFailed(reason: MHIdentityKitError.Reason.general(message: "Flow was deallocated")))
            }
            
            //check if the redirectRequest can be handled
            guard _self.canHandle(redirectRequest: redirectRequest) else {
                
                return false
            }
            
            //create the authorizagtion response and validate it
            let authorizationResponse = try orFail(_self.authorizationResponse(from: redirectRequest))
            try orFail(_self.validate(authorizationResponse))
            
            //prepare for authentication
            let clientID = _self.clientAuthorizer == nil ? _self.clientID : nil
            let accesTokenRequest = AccessTokenRequest(code: authorizationResponse.code, redirectURI: _self.redirectURI, clientID: clientID)
            let accesTokenURLRequest = _self.urlRequest(from: accesTokenRequest)
            
            //authorize the token request
            _self.authorize(accesTokenURLRequest: accesTokenURLRequest, handler: { (accesTokenURLRequest, error) in
                
                guard error == nil else {
                    
                    DispatchQueue.main.async {
                        
                        handler(nil, error)
                    }
                    
                    return
                }
                
                //perform the token request
                _self.perform(accesTokenURLRequest, completion: { (networkResponse) in
                    
                    do {
                        
                        let accessTokenResponse = try _self.accessTokenResponse(from: networkResponse)
                        try _self.validate(accessTokenResponse)
                        
                        DispatchQueue.main.async {
                            
                            handler(accessTokenResponse, nil)
                        }
                    }
                    catch {
                        
                        DispatchQueue.main.async {
                            
                            handler(nil, error)
                        }
                    }
                })
            })
            
            return true
        }
    }
}

//Models
extension AuthorizationCodeGrantFlow {
    
    //https://tools.ietf.org/html/rfc6749#section-4.1.1
    public struct AuthorizationRequest {
        
        public let responseType: AuthorizationResponseType = .code
        public var clientID: String
        public var redirectURI: URL?
        public var scope: Scope?
        public var state: AnyHashable?
        
        public init(clientID: String, redirectURI: URL?, scope: Scope? = nil, state: AnyHashable? = nil) {
            
            self.clientID = clientID
            self.redirectURI = redirectURI
            self.scope = scope
            self.state = state
        }
        
        public var dictionary: [String: Any] {
            
            var dictionary = [String: Any]()
            dictionary["response_type"] = self.responseType.rawValue
            dictionary["client_id"] = self.clientID
            dictionary["redirect_uri"] = self.redirectURI
            dictionary["scope"] = self.scope?.value
            dictionary["state"] = self.state
            
            return dictionary
        }
    }
    
    //https://tools.ietf.org/html/rfc6749#section-4.1.2
    public struct AuthorizationResponse {
        
        public let code: String
        public let state: AnyHashable?
        
        public init(code: String, state: AnyHashable?) {
            
            self.code = code
            self.state = state
        }
    }
    
    //https://tools.ietf.org/html/rfc6749#section-4.1.3
    public struct AccessTokenRequest {
        
        public let grantType: GrantType = .authorizationCode
        public var code: String
        public var redirectURI: URL?
        public var clientID: String?
        
        public init(code: String, redirectURI: URL?, clientID: String?) {
            
            self.code = code
            self.redirectURI = redirectURI
            self.clientID = clientID
        }
        
        public var dictionary: [String: Any] {
            
            var dictionary = [String: Any]()
            dictionary["grant_type"] = self.grantType.rawValue
            dictionary["code"] = self.code
            dictionary["redirect_uri"] = self.redirectURI
            dictionary["client_id"] = self.clientID
            
            return dictionary
        }
    }
}