#
# Gemspec for Windows platforms. We can't put these in the main gemspec because
# it results in bundler platform hell when trying to build the gem.
#
# Set $BUILD_PLATFORM when calling gem build with this gemspec to build for
# Windows platforms like x86-mingw32.
#
# Bundler evaluates gemspec files with `eval`, which breaks `__FILE__`-based
# relative paths inside this file. Locate the main gemspec from the working
# directory instead; every supported workflow (bundler, gem build, rake) runs
# from the repository root.
main_gemspec = File.expand_path('contractful.gemspec', Dir.pwd)
s = eval(File.read(main_gemspec), nil, main_gemspec)

platform = ENV['BUILD_PLATFORM'] || RUBY_PLATFORM

case platform
when /(mingw|mswin)/
  # ffi is needed for Contractful::Windows::RootCerts
  s.add_dependency('ffi', '~> 1.16')
  s.platform = platform
end

s
