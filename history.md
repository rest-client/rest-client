# 1.3.0

- a block can be used to process a request's result, this enable to handle custom error codes or paththrought (design by Cyril Rohr)
- cleaner log API, add a warning for some cases but should be compatible
- accept multiple "Set-Cookie" headers, see http://www.ietf.org/rfc/rfc2109.txt (patch provided by Cyril Rohr)
- remove "Content-Length" and "Content-Type" headers when following a redirection (patch provided by haarts)
- all http error codes have now a corresponding exception class and all of them contain the Reponse -> this means that the raised exception can be different
- changed "Content-Disposition: multipart/form-data" to "Content-Disposition: form-data" per RFC 2388 (patch provided by Kyle Crawford)

# 1.2.0

- formatting changed from tabs to spaces
- logged requests now include generated headers
- accept and content-type headers can now be specified using extentions: RestClient.post "http://example.com/resource", { 'x' => 1 }.to_json, :content_type => :json, :accept => :json
- should be 1.1.1 but renamed to 1.2.0 because 1.1.X versions has already been packaged on Debian

# 1.1.0

- new maintainer: Archiloque, the working repo is now at http://github.com/archiloque/rest-client
- a mailing list has been created at rest.client@librelist.com and an freenode irc channel #rest-client
- François Beausoleil' multipart code from http://github.com/francois/rest-client has been merged
- ability to use hash in hash as payload
- the mime-type code now rely on the mime-types gem http://mime-types.rubyforge.org/ instead of an internal partial list
- 204 response returns a Response instead of nil (patch provided by Elliott Draper)

All changes exept the last one should be fully compatible with the previous version.

NOTE: due to a dependency problem and to the last change, heroku users should update their heroku gem to >= 1.5.3 to be able to use this version.