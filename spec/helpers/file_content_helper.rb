def file_content_helper(path)
  IO.respond_to?(:binread) ? IO.binread(path) : IO.read(path)
end
