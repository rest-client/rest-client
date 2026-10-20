# Raw HTTP deep dive

The flagship use of contractful is the [contract-first client layer]
(../README.md#contract-first-api-clients); the everyday raw-HTTP behavior is
documented directly in the [README](../README.md). This guide collects the
long-form, lower-frequency material from the historical documentation: the
ActiveResource-style facade, redirect-chain mechanics, block/exception result
handling, streaming, the shell and execution hooks. Everything here works the
same for `Contractful::Request.execute` one-liners and for generated contract
clients (the contract executor rides on the same request pipeline).

## Contents

1. [Usage: ActiveResource-Style](#usage-activeresource-style)
2. [Usage: Resource Nesting](#usage-resource-nesting)
3. [Redirection](#redirection)
4. [Result handling](#result-handling)
5. [Non-normalized URIs](#non-normalized-uris)
6. [Lower-level access: streaming](#streaming-request-payload)
7. [Shell](#shell)
8. [Hook](#hook)

---

## Usage: ActiveResource-Style

```ruby
resource = Contractful::Resource.new 'http://example.com/resource'
resource.get

private_resource = Contractful::Resource.new 'https://example.com/private/resource', 'user', 'pass'
private_resource.put File.read('pic.jpg'), :content_type => 'image/jpg'
```

See Contractful::Resource module docs for details.

## Usage: Resource Nesting

```ruby
site = Contractful::Resource.new('http://example.com')
site['posts/1/comments'].post 'Good article.', :content_type => 'text/plain'
```
See `Contractful::Resource` docs for details.


---

## Redirection

By default, contractful will follow HTTP 30x redirection requests.

`Contractful::Response` exposes a `#history` method that returns
a list of each response received in a redirection chain.

```ruby
>> r = Contractful.get('http://httpbin.org/redirect/2')
=> <Contractful::Response 200 "{\n  \"args\":...">

# see each response in the redirect chain
>> r.history
=> [<Contractful::Response 302 "<!DOCTYPE H...">, <Contractful::Response 302 "">]

# see each requested URL
>> r.request.url
=> "http://httpbin.org/get"
>> r.history.map {|x| x.request.url}
=> ["http://httpbin.org/redirect/2", "http://httpbin.org/relative-redirect/1"]
```

#### Manually following redirection

To disable automatic redirection, set `:max_redirects => 0`.

Prior rest-client versions would raise
`Contractful::MaxRedirectsReached`, with no easy way to access the server's
response. contractful raises the normal
`Contractful::ExceptionWithResponse` as it would with any other non-HTTP-20x
response.

```ruby
>> Contractful::Request.execute(method: :get, url: 'http://httpbin.org/redirect/1')
=> Contractful::Response 200 "{\n  "args":..."

>> Contractful::Request.execute(method: :get, url: 'http://httpbin.org/redirect/1', max_redirects: 0)
Contractful::Found: 302 Found
```

To manually follow redirection, you can call `Response#follow_redirection`. Or
you could of course inspect the result and choose custom behavior.

```ruby
>> Contractful::Request.execute(method: :get, url: 'http://httpbin.org/redirect/1', max_redirects: 0)
Contractful::Found: 302 Found
>> begin
       Contractful::Request.execute(method: :get, url: 'http://httpbin.org/redirect/1', max_redirects: 0)
   rescue Contractful::ExceptionWithResponse => err
   end
>> err
=> #<Contractful::Found: 302 Found>
>> err.response
=> Contractful::Response 302 "<!DOCTYPE H..."
>> err.response.headers[:location]
=> "/get"
>> err.response.follow_redirection
=> Contractful::Response 200 "{\n  "args":..."
```

## Result handling

The result of a `Contractful::Request` is a `Contractful::Response` object.

`Contractful::Response` objects are a subclass of `String`.
Previously, they were a real String object with response functionality mixed
in, which was very confusing to work with.

Response objects have several useful methods. (See the class rdoc for more details.)

- `Response#code`: The HTTP response code
- `Response#body`: The response body as a string. (AKA .to_s)
- `Response#headers`: A hash of HTTP response headers
- `Response#raw_headers`: A hash of HTTP response headers as unprocessed arrays
- `Response#cookies`: A hash of HTTP cookies set by the server
- `Response#cookie_jar`: An HTTP::CookieJar of cookies
- `Response#request`: The Contractful::Request object used to make the request
- `Response#history`: If redirection was followed, a list of prior Response objects
- `Response#json`: Parse the response body as JSON. Keyword
  arguments are forwarded to `JSON.parse`.

```ruby
>> r = Contractful.get('https://httpbin.org/get')
>> r.json['url']
=> "https://httpbin.org/get"

>> r.json(symbolize_names: true)[:url]
=> "https://httpbin.org/get"
```

```ruby
Contractful.get('http://example.com')
➔ <Contractful::Response 200 "<!doctype h...">

begin
 Contractful.get('http://example.com/notfound')
rescue Contractful::ExceptionWithResponse => err
  err.response
end
➔ <Contractful::Response 404 "<!doctype h...">
```

### Response callbacks, error handling

A block can be passed to the Contractful method. This block will then be called with the Response.
Response.return! can be called to invoke the default response's behavior.

```ruby
# Don't raise exceptions but return the response
>> Contractful.get('http://example.com/nonexistent') {|response, request, result| response }
=> <Contractful::Response 404 "<!doctype h...">
```

```ruby
# Manage a specific error code
Contractful.get('http://example.com/resource') { |response, request, result, &block|
  case response.code
  when 200
    p "It worked !"
    response
  when 423
    raise SomeCustomExceptionIfYouWant
  else
    response.return!(&block)
  end
}
```

But note that it may be more straightforward to use exceptions to handle
different HTTP error response cases:

```ruby
begin
  resp = Contractful.get('http://example.com/resource')
rescue Contractful::Unauthorized, Contractful::Forbidden => err
  puts 'Access denied'
  return err.response
rescue Contractful::ImATeapot => err
  puts 'The server is a teapot! # RFC 2324'
  return err.response
else
  puts 'It worked!'
  return resp
end
```

For GET and HEAD requests, contractful automatically follows redirection. For
other HTTP verbs, call `.follow_redirection` on the response object (works both
in block form and in exception form).

```ruby
# Follow redirections for all request types and not only for get and head
# RFC : "If the 301, 302 or 307 status code is received in response to a request other than GET or HEAD,
#        the user agent MUST NOT automatically redirect the request unless it can be confirmed by the user,
#        since this might change the conditions under which the request was issued."

# block style
Contractful.post('http://example.com/redirect', 'body') { |response, request, result|
  case response.code
  when 301, 302, 307
    response.follow_redirection
  else
    response.return!
  end
}

# exception style by explicit classes
begin
  Contractful.post('http://example.com/redirect', 'body')
rescue Contractful::MovedPermanently,
       Contractful::Found,
       Contractful::TemporaryRedirect => err
  err.response.follow_redirection
end

# exception style by response code
begin
  Contractful.post('http://example.com/redirect', 'body')
rescue Contractful::ExceptionWithResponse => err
  case err.http_code
  when 301, 302, 307
    err.response.follow_redirection
  else
    raise
  end
end
```

## Non-normalized URIs

If you need to normalize URIs, e.g. to work with International Resource Identifiers (IRIs),
use the Addressable gem (https://github.com/sporkmonger/addressable/) in your code:

```ruby
  require 'addressable/uri'
  Contractful.get(Addressable::URI.parse("http://www.詹姆斯.com/").normalize.to_str)
```


---

## Streaming request payload

Contractful will try to stream any file-like payload rather than reading it into
memory. This happens through `Contractful::Payload::Streamed`, which is
automatically called internally by `Contractful::Payload.generate` on anything
with a `read` method.

```ruby
>> r = Contractful.put('http://httpbin.org/put', File.open('/tmp/foo.txt', 'r'),
                      content_type: 'text/plain')
=> <Contractful::Response 200 "{\n  \"args\":...">
```

In Multipart requests, Contractful will also stream file handles passed as Hash
(or ParamsArray).

```ruby
>> r = Contractful.put('http://httpbin.org/put',
                      {file_a: File.open('a.txt', 'r'),
                       file_b: File.open('b.txt', 'r')})
=> <Contractful::Response 200 "{\n  \"args\":...">

# received by server as two file uploads with multipart/form-data
>> JSON.parse(r)['files'].keys
=> ['file_a', 'file_b']
```

## Streaming responses

Normally, when you use `Contractful.get` or the lower level
`Contractful::Request.execute method: :get` to retrieve data, the entire
response is buffered in memory and returned as the response to the call.

However, if you are retrieving a large amount of data, for example a Docker
image, an iso, or any other large file, you may want to stream the response
directly to disk rather than loading it in memory. If you have a very large
file, it may become *impossible* to load it into memory.

There are two main ways to do this:

### `raw_response`, saves into Tempfile

If you pass `raw_response: true` to `Contractful::Request.execute`, it will save
the response body to a temporary file (using `Tempfile`) and return a
`Contractful::RawResponse` object rather than a `Contractful::Response`.

Note that the tempfile created by `Tempfile.new` will be in `Dir.tmpdir`
(usually `/tmp/`), which you can override to store temporary files in a
different location. This file will be unlinked when it is dereferenced.

If logging is enabled, this will also print download progress.
Customize the interval with `:stream_log_percent` (defaults to
10 for printing a message every 10% complete).

For example:

```ruby
>> raw = Contractful::Request.execute(
           method: :get,
           url: 'http://releases.ubuntu.com/16.04.2/ubuntu-16.04.2-desktop-amd64.iso',
           raw_response: true)
=> <Contractful::RawResponse @code=200, @file=#<Tempfile:/tmp/contractful.20170522-5346-1pptjm1>, @request=<Contractful::Request @method="get", @url="http://releases.ubuntu.com/16.04.2/ubuntu-16.04.2-desktop-amd64.iso">>
>> raw.file.size
=> 1554186240
>> raw.file.path
=> "/tmp/contractful.20170522-5346-1pptjm1"
raw.file.path
=> "/tmp/contractful.20170522-5346-1pptjm1"

>> require 'digest/sha1'
>> Digest::SHA1.file(raw.file.path).hexdigest
=> "4375b73e3a1aa305a36320ffd7484682922262b3"
```

#### `block_response`, receives raw Net::HTTPResponse

If you want to stream the data from the response to a file as it comes, rather
than entirely in memory, you can also pass `Contractful::Request.execute` a
parameter `:block_response` to which you pass a block/proc. This block receives
the raw unmodified Net::HTTPResponse object from Net::HTTP, which you can use
to stream directly to a file as each chunk is received.

Note that this bypasses all the usual HTTP status code handling, so you will
want to do you own checking for HTTP 20x response codes, redirects, etc.

The following is an example:

````ruby
File.open('/some/output/file', 'w') {|f|
  block = proc { |response|
    response.read_body do |chunk|
      f.write chunk
    end
  }
  Contractful::Request.execute(method: :get,
                              url: 'http://example.com/some/really/big/file.img',
                              block_response: block)
}
````

## Shell

The contractful shell command gives an IRB session with Contractful already loaded:

```ruby
$ contractful
>> Contractful.get 'http://example.com'
```

Specify a URL argument for get/post/put/delete on that resource:

```ruby
$ contractful http://example.com
>> put '/resource', 'data'
```

Add a user and password for authenticated resources:

```ruby
$ contractful https://example.com user pass
>> delete '/private/resource'
```

Create ~/.contractful for named sessions:

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
$ contractful private_site
```

Use as a one-off, curl-style:

```ruby
$ contractful get http://example.com/resource > output_body

$ contractful put http://example.com/resource < input_body
```


---

## Hook

Contractful.add_before_execution_proc add a Proc to be called before each execution.
It's handy if you need direct access to the HTTP request.

Example:

```ruby
# Add oauth support using the oauth gem
require 'oauth'
access_token = ...

Contractful.add_before_execution_proc do |req, params|
  access_token.sign! req
end

Contractful.get 'http://example.com'
```
