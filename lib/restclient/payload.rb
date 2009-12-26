require "tempfile"
require "stringio"
require "mime/types"

module RestClient
	module Payload
		extend self

		def generate(params)
			if params.is_a?(String)
				Base.new(params)
			elsif params
				if params.delete(:multipart) == true || has_file?(params)
					Multipart.new(params)
				else
					UrlEncoded.new(params)
				end
			else
				nil
			end
		end

		def has_file?(params)
			params.any? do |_, v|
				case v
				when Hash
					has_file?(v)
				else
					v.respond_to?(:path) && v.respond_to?(:read)
				end
			end
		end

		class Base
			def initialize(params)
				build_stream(params)
			end

			def build_stream(params)
				@stream = StringIO.new(params)
				@stream.seek(0)
			end

			def read(bytes=nil)
				@stream.read(bytes)
			end
			alias :to_s :read

			def escape(v)
				URI.escape(v.to_s, Regexp.new("[^#{URI::PATTERN::UNRESERVED}]"))
			end

			def headers
				{ 'Content-Length' => size.to_s }
			end

			def size
				@stream.size
			end
			alias :length :size

			def close
				@stream.close
			end

			def inspect
				result = to_s.inspect
				@stream.seek(0)
				result
			end
		end

		class UrlEncoded < Base
			def build_stream(params = nil)
				@stream = StringIO.new process_params(params )
			end

			def process_params(params, parent_key = nil)
				params.keys.map do |key|
					calculated_key = parent_key ? "#{parent_key}[#{escape key}]" : escape(key)
					value = params[key]
					if value.is_a? Hash
						process_params(value, calculated_key)
					else
						"#{calculated_key}=#{escape value}"
					end
				end.join( "&" )
			end

			def headers
				super.merge({ 'Content-Type' => 'application/x-www-form-urlencoded' })
			end
		end

		class Multipart < Base
			EOL = "\r\n"

			def build_stream(params)
				b = "--#{boundary}"

				@stream = Tempfile.new("RESTClient.Stream.#{rand(1000)}")
				@stream.write(b + EOL)
				x = params.to_a
				last_index = x.length - 1
				x.each_with_index do |a, index|
					k, v = *a
					if v.respond_to?(:read) && v.respond_to?(:path)
						create_file_field(@stream, k,v)
					else
						create_regular_field(@stream, k,v)
					end
					@stream.write(EOL + b)
					@stream.write(EOL) unless last_index == index
				end
				@stream.write('--')
				@stream.write(EOL)
				@stream.seek(0)
			end

			def create_regular_field(s, k, v)
				s.write("Content-Disposition: multipart/form-data; name=\"#{k}\"")
				s.write(EOL)
				s.write(EOL)
				s.write(v)
			end

			def create_file_field(s, k, v)
				begin
					s.write("Content-Disposition: multipart/form-data; name=\"#{k}\"; filename=\"#{v.respond_to?(:original_filename) ? v.original_filename : File.basename(v.path)}\"#{EOL}")
					s.write("Content-Type: #{v.respond_to?(:content_type) ? v.content_type : mime_for(v.path)}#{EOL}")
					s.write(EOL)
					while data = v.read(8124)
						s.write(data)
					end
				ensure
					v.close
				end
			end

			def mime_for(path)
				mime = MIME::Types.type_for path
				mime.empty? ? 'text/plain' : mime[0].content_type
			end

			def boundary
				@boundary ||= rand(1_000_000).to_s
			end

			def headers
				super.merge({'Content-Type' => %Q{multipart/form-data; boundary="#{boundary}"}})
			end

			def close
				@stream.close
			end
		end
	end
end
