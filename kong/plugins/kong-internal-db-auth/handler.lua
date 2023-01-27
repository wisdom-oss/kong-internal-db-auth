local re_gmatch = ngx.re.gmatch
local http = require "resty.http"
local cjson = require "cjson"
local plugin = {
    PRIORITY = 1000,
    VERSION = "1.0.3"
}

-- run the plugin in the access phase
function plugin:access(plugin_conf)
    kong.log("validating the sent access token with the internal OAuth2.0 service")

    local response, ok, err
    local bearer_token = plugin:get_access_token()

    if not bearer_token then
        return kong.response.exit(401, [[{"httpCode": 401, "httpError": "Unauthorized", "error": "api-gateway.NO_AUTHORIZATION", "errorName": "No Authorization Information", "errorDescription": "The request did not contain the needed authorization information"}]])
    end
    local scheme, host, port, path = unpack(http:parse_uri(plugin_conf.intospection_url))
    local httpc = http.new()
    httpc:set_timeout(10000)
    httpc:connect(host, port)    
    if scheme == "https" then
        ok, err = httpc:ssl_handshake()
        if not ok then
            kong.log.err(err)
            return kong.response.exit(500, [[{"httpCode": 500, "httpError": "Internal Server Error", "error": "api-gateway.INTERNAL_ERROR", "errorName": "Internal Error", "errorDescription": "SSL Handshake failed"}]])
        end
    end

    local auth_request = plugin:new_auth_request(host, port, path, bearer_token)

    response, err = httpc:request(auth_request)

    if not response then
        return kong.response.exit(500, [[{"httpCode": 500, "httpError": "Internal Server Error", "error": "api-gateway.INTERNAL_ERROR", "errorName": "Internal Error", "errorDescription": "No Response received"}]])
    end

    if response.status > 299 then 
        return kong.response.exit(response.status, response.body)
    end

    local response_body = response:read_body()
    local status, response_json = pcall(cjson.decode, response_body)

    if not status then
        return kong.response.exit(500, [[{"httpCode": 500, "httpError": "Internal Server Error", "error": "api-gateway.INTERNAL_ERROR", "errorName": "Internal Error", "errorDescription": "No Response received"}]])
    end

    if not response_json['active'] then
        return kong.response.exit(401, [[{"httpCode": 401, "httpError": "Unauthorized", "error": "api-gateway.UNAUTHORIZED", "errorName": "Unauthorized", "errorDescription": "The bearer token set in the request is not valid"}]])
    end

    if not response_json['scope'] then
        return kong.response.exit(401, [[{"httpCode": 401, "httpError": "Unauthorized", "error": "api-gateway.UNAUTHORIZED", "errorName": "Unauthorized", "errorDescription": "The bearer token set in the request is not valid"}]])
    else
        kong.service.request.set_header("X-Authenticated-Scope", response_json['scope']:gsub(" ", ","))
    end
end

function plugin:new_auth_request(host, port, path, token)
    if not token then
        return nil
    end

    local hostname = host
    if port ~= 80 and port ~= 443 then
        hostname = hostname .. ":" .. tostring(port)
    end

    local headers = {
        charset = "utf-8",
        ["content-type"] = "application/x-www-form-urlencoded; charset=utf-8",
        ["Host"] = hostname,
    }

    local payload = "token=" .. token

    return {
        method = "POST",
        path = path,
        headers = headers,
        body = payload,
        keepalive_timeout = 10000
    }
end

function plugin:get_access_token()
    -- get the authorization header
    local authrorization_header = kong.request.get_header("authorization")
    if authrorization_header then
        local iterator, iterator_err = re_gmatch(authrorization_header, "\\s*[Bb]earer\\s+(.+)")
        if not iterator then
            return nil, iter_err
        end

        local m, err = iterator()
        if err then
            return nil, err
        end
        if m and #m > 0 then
            return m[1]
        end
    end
end

return plugin