# frozen_string_literal: true

require_relative '_lib'

describe Contractful::Payload, :include_helpers do
  context 'Base Payload' do
    it 'resets stream after to_s' do
      payload = Contractful::Payload::Base.new('foobar')
      expect(payload.to_s).to eq 'foobar'
      expect(payload.to_s).to eq 'foobar'
    end
  end

  context 'A regular Payload' do
    it 'uses standard enctype as default content-type' do
      expect(Contractful::Payload::UrlEncoded.new({}).headers['Content-Type'])
        .to eq 'application/x-www-form-urlencoded'
    end

    it 'forms properly encoded params' do
      expect(Contractful::Payload::UrlEncoded.new({ foo: 'bar' }).to_s)
        .to eq 'foo=bar'
      expect(['foo=bar&baz=qux', 'baz=qux&foo=bar']).to include(
        Contractful::Payload::UrlEncoded.new({ foo: 'bar', baz: 'qux' }).to_s
      )
    end

    it 'escapes parameters' do
      expect(Contractful::Payload::UrlEncoded.new({ 'foo + bar' => 'baz' }).to_s)
        .to eq 'foo+%2B+bar=baz'
    end

    it 'properlies handle hashes as parameter' do
      expect(Contractful::Payload::UrlEncoded.new({ foo: { bar: 'baz' } }).to_s)
        .to eq 'foo[bar]=baz'
      expect(Contractful::Payload::UrlEncoded.new({ foo: { bar: { baz: 'qux' } } }).to_s)
        .to eq 'foo[bar][baz]=qux'
    end

    it 'handles many attributes inside a hash' do
      parameters = Contractful::Payload::UrlEncoded.new({ foo: { bar: 'baz', baz: 'qux' } }).to_s
      expect(parameters).to eq 'foo[bar]=baz&foo[baz]=qux'
    end

    it 'handles attributes inside an array inside an hash' do
      parameters = Contractful::Payload::UrlEncoded.new({ 'foo' => [{ 'bar' => 'baz' }, { 'bar' => 'qux' }] }).to_s
      expect(parameters).to eq 'foo[][bar]=baz&foo[][bar]=qux'
    end

    it 'handles arrays inside a hash inside a hash' do
      parameters = Contractful::Payload::UrlEncoded.new({ 'foo' => { 'even' => [0, 2], 'odd' => [1, 3] } }).to_s
      expect(parameters).to eq 'foo[even][]=0&foo[even][]=2&foo[odd][]=1&foo[odd][]=3'
    end

    it 'forms properly use symbols as parameters' do
      expect(Contractful::Payload::UrlEncoded.new({ foo: :bar }).to_s)
        .to eq 'foo=bar'
      expect(Contractful::Payload::UrlEncoded.new({ foo: { bar: :baz } }).to_s)
        .to eq 'foo[bar]=baz'
    end

    it 'properlies handle arrays as repeated parameters' do
      expect(Contractful::Payload::UrlEncoded.new({ foo: ['bar'] }).to_s)
        .to eq 'foo[]=bar'
      expect(Contractful::Payload::UrlEncoded.new({ foo: %w[bar baz] }).to_s)
        .to eq 'foo[]=bar&foo[]=baz'
    end

    it 'does not close if stream already closed' do
      p = Contractful::Payload::UrlEncoded.new({ 'foo ' => 'bar' })
      expect { 3.times { p.close } }.not_to raise_error
    end
  end

  context 'A multipart Payload' do
    it 'uses standard enctype as default content-type' do
      m = Contractful::Payload::Multipart.new({})
      allow(m).to receive(:boundary).and_return(123)
      expect(m.headers['Content-Type']).to eq 'multipart/form-data; boundary=123'
    end

    it 'does not error on close if stream already closed' do
      m = Contractful::Payload::Multipart.new(file: File.new(test_image_path))
      expect { 3.times { m.close } }.not_to raise_error
    end

    it 'forms properly separated multipart data' do
      m = Contractful::Payload::Multipart.new([[:bar, 'baz'], [:foo, 'bar']])
      expect(m.to_s).to eq <<~EOS
        --#{m.boundary}\r
        Content-Disposition: form-data; name="bar"\r
        \r
        baz\r
        --#{m.boundary}\r
        Content-Disposition: form-data; name="foo"\r
        \r
        bar\r
        --#{m.boundary}--\r
      EOS
    end

    it 'does not escape parameters names' do
      m = Contractful::Payload::Multipart.new([['bar ', 'baz']])
      expect(m.to_s).to eq <<~EOS
        --#{m.boundary}\r
        Content-Disposition: form-data; name="bar "\r
        \r
        baz\r
        --#{m.boundary}--\r
      EOS
    end

    it 'forms properly separated multipart data' do
      f = File.new(test_image_path)
      m = Contractful::Payload::Multipart.new({ foo: f })
      expect(m.to_s).to eq <<~EOS
        --#{m.boundary}\r
        Content-Disposition: form-data; name="foo"; filename="ISS.jpg"\r
        Content-Type: image/jpeg\r
        \r
        #{File.binread(f.path)}\r
        --#{m.boundary}--\r
      EOS
    end

    it "ignores the name attribute when it's not set" do
      f = File.new(test_image_path)
      m = Contractful::Payload::Multipart.new({ nil => f })
      expect(m.to_s).to eq <<~EOS
        --#{m.boundary}\r
        Content-Disposition: form-data; filename="ISS.jpg"\r
        Content-Type: image/jpeg\r
        \r
        #{File.binread(f.path)}\r
        --#{m.boundary}--\r
      EOS
    end

    it 'detects optional (original) content type and filename' do
      f = File.new(test_image_path)
      expect(f).to receive(:content_type).and_return('text/plain')
      expect(f).to receive(:original_filename).and_return('foo.txt')
      m = Contractful::Payload::Multipart.new({ foo: f })
      expect(m.to_s).to eq <<~EOS
        --#{m.boundary}\r
        Content-Disposition: form-data; name="foo"; filename="foo.txt"\r
        Content-Type: text/plain\r
        \r
        #{File.binread(f.path)}\r
        --#{m.boundary}--\r
      EOS
    end

    it 'handles hash in hash parameters' do
      m = Contractful::Payload::Multipart.new({ bar: { baz: 'foo' } })
      expect(m.to_s).to eq <<~EOS
        --#{m.boundary}\r
        Content-Disposition: form-data; name="bar[baz]"\r
        \r
        foo\r
        --#{m.boundary}--\r
      EOS

      f = File.new(test_image_path)
      f.instance_eval "def content_type; 'text/plain'; end", __FILE__, __LINE__
      f.instance_eval "def original_filename; 'foo.txt'; end", __FILE__, __LINE__
      m = Contractful::Payload::Multipart.new({ foo: { bar: f } })
      expect(m.to_s).to eq <<~EOS
        --#{m.boundary}\r
        Content-Disposition: form-data; name="foo[bar]"; filename="foo.txt"\r
        Content-Type: text/plain\r
        \r
        #{File.binread(f.path)}\r
        --#{m.boundary}--\r
      EOS
    end

    it 'correctlies format hex boundary' do
      allow(SecureRandom).to receive(:base64).with(12).and_return('TGs89+ttw/xna6TV')
      f = File.new(test_image_path)
      m = Contractful::Payload::Multipart.new({ foo: f })
      expect(m.boundary).to eq(('-' * 4) + 'RubyFormBoundary' + 'TGs89AttwBxna6TV')
    end
  end

  context 'streamed payloads' do
    it 'properlies determine the size of file payloads' do
      f = File.new(test_image_path)
      payload = Contractful::Payload.generate(f)
      expect(payload.size).to eq 72_463
      expect(payload.length).to eq 72_463
    end

    it 'properlies determine the size of other kinds of streaming payloads' do
      s = StringIO.new 'foo'
      payload = Contractful::Payload.generate(s)
      expect(payload.size).to eq 3
      expect(payload.length).to eq 3

      begin
        f = Tempfile.new 'contractful'
        f.write 'foo bar'

        payload = Contractful::Payload.generate(f)
        expect(payload.size).to eq 7
        expect(payload.length).to eq 7
      ensure
        f.close
      end
    end

    it 'has a closed? method' do
      f = File.new(test_image_path)
      payload = Contractful::Payload.generate(f)
      expect(payload.closed?).to be_falsey
      payload.close
      expect(payload.closed?).to be_truthy
    end

    context 'with non-seekable streams' do
      # A plain reader object: responds to #read but has no #seek at all.
      let(:plain_reader) do
        Class.new do
          def initialize(data)
            @io = StringIO.new(data)
          end

          def read(*args)
            @io.read(*args)
          end
        end.new('chunk-1chunk-2')
      end

      it 'does not raise when reading to_s from a reader without #seek' do
        payload = Contractful::Payload.generate(plain_reader)
        expect(payload).to be_a(Contractful::Payload::Streamed)

        expect(payload.to_s).to eq 'chunk-1chunk-2'
        expect { payload.to_s }.not_to raise_error
      end

      it 'does not raise when rewinding a reader without #rewind' do
        payload = Contractful::Payload.generate(plain_reader)
        expect(payload.rewind).to be_falsey
      end

      it 'does not raise when the stream is a non-seekable IO such as a pipe' do
        rd, wr = IO.pipe
        begin
          wr.write('pipe-data')
          wr.close
          payload = Contractful::Payload.generate(rd)
          # IO responds to #seek, but seeking a pipe raises Errno::ESPIPE.
          expect(rd.respond_to?(:seek)).to be_truthy
          expect(payload.to_s).to eq 'pipe-data'
          expect { payload.to_s }.not_to raise_error
        ensure
          rd.close unless rd.closed?
          wr.close unless wr.closed?
        end
      end

      it 'reports a pipe as non-rewindable instead of raising Errno::ESPIPE' do
        rd, wr = IO.pipe
        begin
          wr.write('pipe-data')
          wr.close
          payload = Contractful::Payload.generate(rd)

          expect { payload.rewind }.not_to raise_error
          expect(payload.rewind).to be false
        ensure
          rd.close unless rd.closed?
          wr.close unless wr.closed?
        end
      end

      it 'logs small non-seekable payloads without crashing (short_inspect path)' do
        payload = Contractful::Payload.generate(plain_reader)
        expect { payload.short_inspect }.not_to raise_error
      end
    end
  end

  context 'Payload generation' do
    it 'recognizes standard urlencoded params' do
      expect(Contractful::Payload.generate({ 'foo' => 'bar' })).to be_kind_of(Contractful::Payload::UrlEncoded)
    end

    it 'recognizes multipart params' do
      f = File.new(test_image_path)
      expect(Contractful::Payload.generate({ 'foo' => f })).to be_kind_of(Contractful::Payload::Multipart)
    end

    it 'is multipart if forced' do
      expect(Contractful::Payload.generate({ 'foo' => 'bar', :multipart => true })).to be_kind_of(Contractful::Payload::Multipart)
    end

    it 'does not mutate the caller hash when multipart is forced' do
      params = { 'foo' => 'bar', :multipart => true }

      expect(Contractful::Payload.generate(params)).to be_kind_of(Contractful::Payload::Multipart)
      expect(params).to eq('foo' => 'bar', :multipart => true)
      expect(Contractful::Payload.generate(params)).to be_kind_of(Contractful::Payload::Multipart)
    end

    it 'handles deeply nested multipart' do
      f = File.new(test_image_path)
      params = { foo: Contractful::ParamsArray.new({ nested: f }) }
      expect(Contractful::Payload.generate(params)).to be_kind_of(Contractful::Payload::Multipart)
    end

    it 'returns data if no of the above' do
      expect(Contractful::Payload.generate('data')).to be_kind_of(Contractful::Payload::Base)
    end

    it 'recognizes nested multipart payloads in hashes' do
      f = File.new(test_image_path)
      expect(Contractful::Payload.generate({ 'foo' => { 'file' => f } })).to be_kind_of(Contractful::Payload::Multipart)
    end

    it 'recognizes nested multipart payloads in arrays' do
      f = File.new(test_image_path)
      expect(Contractful::Payload.generate({ 'foo' => [f] })).to be_kind_of(Contractful::Payload::Multipart)
    end

    it 'recognizes file payloads that can be streamed' do
      f = File.new(test_image_path)
      expect(Contractful::Payload.generate(f)).to be_kind_of(Contractful::Payload::Streamed)
    end

    it 'recognizes other payloads that can be streamed' do
      expect(Contractful::Payload.generate(StringIO.new('foo'))).to be_kind_of(Contractful::Payload::Streamed)
    end

    # hashery gem introduces Hash#read convenience method. Existence of #read method used to determine of content is streameable :/
    it 'does not treat hashes as streameable' do
      # Pin the branch order in Payload.generate: a Hash that responds to
      # #read must still take the Hash branch, not the Streamed one.
      hash_that_reads = { 'foo' => 'bar' }
      def hash_that_reads.read(*)
        'looks like a stream'
      end
      expect(Contractful::Payload.generate(hash_that_reads)).to be_kind_of(Contractful::Payload::UrlEncoded)
    end

    it 'recognizes multipart payload wrapped in ParamsArray' do
      f = File.new(test_image_path)
      params = Contractful::ParamsArray.new([[:image, f]])
      expect(Contractful::Payload.generate(params)).to be_kind_of(Contractful::Payload::Multipart)
    end

    it 'handles non-multipart payload wrapped in ParamsArray' do
      params = Contractful::ParamsArray.new([[:arg, 'value1'], [:arg, 'value2']])
      expect(Contractful::Payload.generate(params)).to be_kind_of(Contractful::Payload::UrlEncoded)
    end

    it 'passes through Payload::Base and subclasses unchanged' do
      payloads = [
        Contractful::Payload::Base.new('foobar'),
        Contractful::Payload::UrlEncoded.new({ foo: 'bar' }),
        Contractful::Payload::Streamed.new(File.new(test_image_path)),
        Contractful::Payload::Multipart.new({ myfile: File.new(test_image_path) })
      ]

      payloads.each do |payload|
        expect(Contractful::Payload.generate(payload)).to equal(payload)
      end
    end
  end
end
