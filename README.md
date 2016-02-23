# REST Client -- simple DSL for accessing HTTP and REST resources

[![Gem Downloads](https://img.shields.io/gem/dt/rails.svg)](https://rubygems.org/gems/rest-client)
[![Build Status](https://travis-ci.org/rest-client/rest-client.svg?branch=master)](https://travis-ci.org/rest-client/rest-client)
[![Code Climate](https://codeclimate.com/github/rest-client/rest-client.svg)](https://codeclimate.com/github/rest-client/rest-client)
[![Inline docs](http://inch-ci.org/github/rest-client/rest-client.svg?branch=master)](http://www.rubydoc.info/github/rest-client/rest-client/master)

A simple HTTP and REST client for Ruby, inspired by the Sinatra's microframework style
of specifying actions: get, put, post, delete.

* Main page: https://github.com/rest-client/rest-client
* Mailing list: https://groups.io/g/rest-client

### New mailing list

We have a new email list for announcements, hosted by Groups.io.

* Subscribe on the web: https://groups.io/g/rest-client

* Subscribe by sending an email: mailto:rest-client+subscribe@groups.io

* Open discussion subgroup: https://groups.io/g/rest-client+discuss

The old Librelist mailing list is *defunct*, as Librelist appears to be broken
and not accepting new mail. The old archives are still up, but have been
imported into the new list archives as well.
http://librelist.com/browser/rest.client

## Requirements

MRI Ruby 1.9.3 and newer are supported. Alternative interpreters compatible with
1.9+ should work as well.

Earlier Ruby versions such as 1.8.7 and 1.9.2 are no longer supported. These
versions no longer have any official support, and do not receive security
updates.

The rest-client gem depends on these other gems for usage at runtime:

* [mime-types](http://rubygems.org/gems/mime-types)
* [netrc](http://rubygems.org/gems/netrc)
* [http-cookie](https://rubygems.org/gems/http-cookie)

There are also several development dependencies. It's recommended to use
[bundler](http://bundler.io/) to manage these dependencies for hacking on
rest-client.

## Usage: Raw URL
```ruby
require 'rest-client'

RestClient.get 'http://example.com/resource'

RestClient.get 'http://example.com/resource', {:params => {:id => 50, 'foo' => 'bar'}}

RestClient.get 'https://user:password@example.com/private/resource', {:accept => :json}

RestClient.post 'http://example.com/resource', :param1 => 'one', :nested => { :param2 => 'two' }

RestClient.post "http://example.com/resource", { 'x' => 1 }.to_json, :content_type => :json, :accept => :json

RestClient.delete 'http://example.com/resource'

response = RestClient.get 'http://example.com/resource'
response.code
➔ 200
response.cookies
➔ {"Foo"=>"BAR", "QUUX"=>"QUUUUX"}
response.headers
➔ {:content_type=>"text/html; charset=utf-8", :cache_control=>"private" ...
response.to_str
➔ \n<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML 4.01//EN\"\n   \"http://www.w3.org/TR/html4/strict.dtd\">\n\n<html ....

RestClient.post( url,
  {
    :transfer => {
      :path => '/foo/bar',
      :owner => 'that_guy',
      :group => 'those_guys'
    },
     :upload => {
      :file => File.new(path, 'rb')
    }
  })
```
## Passing advanced options

The top level helper methods like RestClient.get accept a headers hash as
their last argument and don't allow passing more complex options. But these
helpers are just thin wrappers around `RestClient::Request.execute`.

```ruby
RestClient::Request.execute(method: :get, url: 'http://example.com/resource',
                            timeout: 10)

RestClient::Request.execute(method: :get, url: 'http://example.com/resource',
                            ssl_ca_file: 'myca.pem',
                            ssl_ciphers: 'AESGCM:!aNULL')
```
You can also use this to pass a payload for HTTP verbs like DELETE, where the
`RestClient.delete` helper doesn't accept a payload.

```ruby
RestClient::Request.execute(method: :delete, url: 'http://example.com/resource',
                            payload: 'foo', headers: {myheader: 'bar'})
```

Due to unfortunate choices in the original API, the params used to populate the
query string are actually taken out of the headers hash. So if you want to pass
both the params hash and more complex options, use the special key
`:params` in the headers hash. This design may change in a future major
release.

```ruby
RestClient::Request.execute(method: :get, url: 'http://example.com/resource',
                            timeout: 10, headers: {params: {foo: 'bar'}})

➔ GET http://example.com/resource?foo=bar
```

## Multipart

Yeah, that's right!  This does multipart sends for you!

```ruby
RestClient.post '/data', :myfile => File.new("/path/to/image.jpg", 'rb')
```

This does two things for you:

- Auto-detects that you have a File value sends it as multipart
- Auto-detects the mime of the file and sets it in the HEAD of the payload for each entry

If you are sending params that do not contain a File object but the payload needs to be multipart then:

```ruby
RestClient.post '/data', {:foo => 'bar', :multipart => true}
```

## Usage: ActiveResource-Style

```ruby
resource = RestClient::Resource.new 'http://example.com/resource'
resource.get

private_resource = RestClient::Resource.new 'https://example.com/private/resource', 'user', 'pass'
private_resource.put File.read('pic.jpg'), :content_type => 'image/jpg'
```

See RestClient::Resource module docs for details.

## Usage: Resource Nesting

```ruby
site = RestClient::Resource.new('http://example.com')
site['posts/1/comments'].post 'Good article.', :content_type => 'text/plain'
```
See `RestClient::Resource` docs for details.

## Exceptions (see http://www.w3.org/Protocols/rfc2616/rfc2616-sec10.html)

- for result codes between `200` and `207`, a `RestClient::Response` will be returned
- for result codes `301`, `302` or `307`, the redirection will be followed if the request is a `GET` or a `HEAD`
- for result code `303`, the redirection will be followed and the request transformed into a `GET`
- for other cases, a `RestClient::Exception` holding the Response will be raised; a specific exception class will be thrown for known error codes
- call `.response` on the exception to get the server's response

```ruby
RestClient.get 'http://example.com/resource'
➔ RestClient::ResourceNotFound: RestClient::ResourceNotFound

begin
  RestClient.get 'http://example.com/resource'
rescue => e
  e.response
end
➔ 404 Resource Not Found | text/html 282 bytes
```

## Result handling

The result of a `RestClient::Request` is a `RestClient::Response` object.

__New in 2.0:__ `RestClient::Response` objects are now a subclass of `String`.
Previously, they were a real String object with response functionality mixed
in, which was very confusing to work with.

Response objects have several useful methods. (See the class rdoc for more details.)

- `Response#code`: The HTTP response code
- `Response#body`: The response body as a string. (AKA .to_s)
- `Response#headers`: A hash of HTTP response headers
- `Response#raw_headers`: A hash of HTTP response headers as unprocessed arrays
- `Response#cookies`: A hash of HTTP cookies set by the server
- `Response#cookie_jar`: <em>New in 1.8</em> An HTTP::CookieJar of cookies
- `Response#request`: The RestClient::Request object used to make the request
- `Response#history`: If redirection was followed, a list of prior Response objects

```ruby
RestClient.get('http://example.com')
➔ <RestClient::Response 200 "<!doctype h...">

begin
 RestClient.get('http://example.com/notfound')
rescue RestClient::ExceptionWithResponse => err
  err.response
end
➔ <RestClient::Response 404 "<!doctype h...">
```

### Response callbacks

A block can be passed to the RestClient method. This block will then be called with the Response.
Response.return! can be called to invoke the default response's behavior.

```ruby
# Don't raise exceptions but return the response
RestClient.get('http://example.com/resource'){|response, request, result| response }
➔ 404 Resource Not Found | text/html 282 bytes

# Manage a specific error code
RestClient.get('http://my-rest-service.com/resource'){ |response, request, result, &block|
  case response.code
  when 200
    p "It worked !"
    response
  when 423
    raise SomeCustomExceptionIfYouWant
  else
    response.return!(request, result, &block)
  end
}

# Follow redirections for all request types and not only for get and head
# RFC : "If the 301, 302 or 307 status code is received in response to a request other than GET or HEAD,
#        the user agent MUST NOT automatically redirect the request unless it can be confirmed by the user,
#        since this might change the conditions under which the request was issued."
RestClient.get('http://my-rest-service.com/resource'){ |response, request, result, &block|
  if [301, 302, 307].include? response.code
    response.follow_redirection(request, result, &block)
  else
    response.return!(request, result, &block)
  end
}
```
## Non-normalized URIs

If you need to normalize URIs, e.g. to work with International Resource Identifiers (IRIs),
use the addressable gem (http://addressable.rubyforge.org/api/) in your code:

```ruby
  require 'addressable/uri'
  RestClient.get(Addressable::URI.parse("http://www.詹姆斯.com/").normalize.to_str)
```

## Lower-level access

For cases not covered by the general API, you can use the `RestClient::Request` class, which provides a lower-level API.

You can:

- specify ssl parameters
- override cookies
- manually handle the response (e.g. to operate on it as a stream rather than reading it all into memory)

See `RestClient::Request`'s documentation for more information.

## Shell

The restclient shell command gives an IRB session with RestClient already loaded:

```ruby
$ restclient
>> RestClient.get 'http://example.com'
```

Specify a URL argument for get/post/put/delete on that resource:

```ruby
$ restclient http://example.com
>> put '/resource', 'data'
```

Add a user and password for authenticated resources:

```ruby
$ restclient https://example.com user pass
>> delete '/private/resource'
```

Create ~/.restclient for named sessions:

```ruby
  sinatra:
    url: http://localhost:4567
  rack:
    url: http://localhost:9292
  private_site:
    url: http://example.com
    username: user
    password: pass
```

Then invoke:

```ruby
$ restclient private_site
```

Use as a one-off, curl-style:

```ruby
$ restclient get http://example.com/resource > output_body

$ restclient put http://example.com/resource < input_body
```

## Logging

To enable logging you can:

- set RestClient.log with a Ruby Logger, or
- set an environment variable to avoid modifying the code (in this case you can use a file name, "stdout" or "stderr"):

```ruby
$ RESTCLIENT_LOG=stdout path/to/my/program
```
Either produces logs like this:

```ruby
RestClient.get "http://some/resource"
# => 200 OK | text/html 250 bytes
RestClient.put "http://some/resource", "payload"
# => 401 Unauthorized | application/xml 340 bytes
```

Note that these logs are valid Ruby, so you can paste them into the `restclient`
shell or a script to replay your sequence of rest calls.

## Proxy

All calls to RestClient, including Resources, will use the proxy specified by
`RestClient.proxy`:

```ruby
RestClient.proxy = "http://proxy.example.com/"
RestClient.get "http://some/resource"
# => response from some/resource as proxied through proxy.example.com
```

Often the proxy URL is set in an environment variable, so you can do this to
use whatever proxy the system is configured to use:

```ruby
  RestClient.proxy = ENV['http_proxy']
```

__New in 2.0:__ Specify a per-request proxy by passing the :proxy option to
RestClient::Request. This will override any proxies set by environment variable
or by the global `RestClient.proxy` value.

```ruby
RestClient::Request.execute(method: :get, url: 'http://example.com',
                            proxy: 'http://proxy.example.com')
# => single request proxied through the proxy
```

This can be used to disable the use of a proxy for a particular request.

```ruby
RestClient.proxy = "http://proxy.example.com/"
RestClient::Request.execute(method: :get, url: 'http://example.com', proxy: nil)
# => single request sent without a proxy
```

## Query parameters

Request objects know about query parameters and will automatically add them to
the URL for GET, HEAD and DELETE requests, escaping the keys and values as needed:

```ruby
RestClient.get 'http://example.com/resource', :params => {:foo => 'bar', :baz => 'qux'}
# will GET http://example.com/resource?foo=bar&baz=qux
```

## Headers

Request headers can be set by passing a ruby hash containing keys and values
representing header names and values:

```ruby
# GET request with modified headers
RestClient.get 'http://example.com/resource', {:Authorization => 'Bearer cT0febFoD5lxAlNAXHo6g'}

# POST request with modified headers
RestClient.post 'http://example.com/resource', {:foo => 'bar', :baz => 'qux'}, {:Authorization => 'Bearer cT0febFoD5lxAlNAXHo6g'}

# DELETE request with modified headers
RestClient.delete 'http://example.com/resource', {:Authorization => 'Bearer cT0febFoD5lxAlNAXHo6g'}
```

## Cookies

Request and Response objects know about HTTP cookies, and will automatically
extract and set headers for them as needed:

```ruby
response = RestClient.get 'http://example.com/action_which_sets_session_id'
response.cookies
# => {"_applicatioN_session_id" => "1234"}

response2 = RestClient.post(
  'http://localhost:3000/',
  {:param1 => "foo"},
  {:cookies => {:session_id => "1234"}}
)
# ...response body
```
### Full cookie jar support (new in 1.8)

The original cookie implementation was very naive and ignored most of the
cookie RFC standards.
__New in 1.8__:  An HTTP::CookieJar of cookies

Response objects now carry a cookie_jar method that exposes an HTTP::CookieJar
of cookies, which supports full standards compliant behavior.

## SSL/TLS support

Various options are supported for configuring rest-client's TLS settings. By
default, rest-client will verify certificates using the system's CA store on
all platforms. (This is intended to be similar to how browsers behave.) You can
specify an :ssl_ca_file, :ssl_ca_path, or :ssl_cert_store to customize the
certificate authorities accepted.

### SSL Client Certificates

```ruby
RestClient::Resource.new(
  'https://example.com',
  :ssl_client_cert  =>  OpenSSL::X509::Certificate.new(File.read("cert.pem")),
  :ssl_client_key   =>  OpenSSL::PKey::RSA.new(File.read("key.pem"), "passphrase, if any"),
  :ssl_ca_file      =>  "ca_certificate.pem",
  :verify_ssl       =>  OpenSSL::SSL::VERIFY_PEER
).get
```
Self-signed certificates can be generated with the openssl command-line tool.

## Hook

RestClient.add_before_execution_proc add a Proc to be called before each execution.
It's handy if you need direct access to the HTTP request.

Example:

```ruby
# Add oauth support using the oauth gem
require 'oauth'
access_token = ...

RestClient.add_before_execution_proc do |req, params|
  access_token.sign! req
end

RestClient.get 'http://example.com'
```

## More

Need caching, more advanced logging or any ability provided by Rack middleware?

Have a look at rest-client-components: http://github.com/crohr/rest-client-components

## Credits

|||
|---------------------|---------------------------------------------------------|
| REST Client Team    | Andy Brody                                              |
| Creator             | Adam Wiggins                                            |
| Maintainers Emeriti | Lawrence Leonard Gilbert, Matthew Manning, Julien Kirch |
| Major contributions | Blake Mizerany, Julien Kirch                            |

A great many generous folks have contributed features and patches.
See AUTHORS for the full list.

## Legal

Released under the MIT License: http://www.opensource.org/licenses/mit-license.php

"Master Shake" photo (http://www.flickr.com/photos/solgrundy/924205581/) by
"SolGrundy"; used under terms of the Creative Commons Attribution-ShareAlike 2.0
Generic license (http://creativecommons.org/licenses/by-sa/2.0/)

Code for reading Windows root certificate store derived from work by Puppet;
used under terms of the Apache License, Version 2.0.
