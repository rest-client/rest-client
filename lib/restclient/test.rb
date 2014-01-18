
def m(path)
  ret = 'text/plain'
  dot = path.rindex('.')
  if dot
    ext = path[dot+1..path.length]
  else
    return ret
  end
  p ext
end

x = "abc.json"

p m x

x ="scooby"
p m x
