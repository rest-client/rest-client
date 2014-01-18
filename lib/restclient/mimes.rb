module RestClient

  module Mimes

    def self.mime_for(path)
      ret = Mimes.mime_for_ext(path)
      if ret
        return ret
      end
      return 'text/plain'
    end

    # takes something like json and returns application/json.
    # If no conversion, returns ext passed in
    def self.mime_for_ext(path)
      ret = nil
      dot = path.rindex('.')
      if dot
        ext = path[dot+1..path.length]
      else
        ext = path
      end
      # feel free to add more mime-types anyone.
      case ext
        when 'xml'
          ret = 'application/xml'
        when 'gif'
          ret = 'image/gif'
        when 'jpg', 'jpeg'
          ret = 'image/jpeg'
        when 'json'
          ret = 'application/json'
        when 'html'
          ret = 'text/html'
        when 'mp3'
          ret = 'audio/mpeg'
      end
      return ret
    end

    def self.mime_for_or_not(ext)
      ret = Mimes.mime_for_ext(ext)
      if ret
        return ret
      end
      return ext
    end
  end

end