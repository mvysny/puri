# frozen_string_literal: true

require 'spec_helper'
require 'rbconfig'
require 'tmpdir'

# The recorder runs a real process paced like pw-record; the server is a scripted Faraday adapter
# behind the real RubyLLM request. `WHISPER_URL=http://127.0.0.1:8081` adds a real whisper-server.
RSpec.describe Puri::Core::Dictation do
  p = Puri::Protocol
  bytes_per_second = Puri::Core::Dictation::Recorder::BYTES_PER_SECOND

  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  end

  # @param seconds [Float]
  # @param amplitude [Float] 0 for silence, 1 for full scale
  # @return [String] a 440 Hz tone, 16 kHz mono s16le
  def tone(seconds, amplitude: 0.5)
    (0...(seconds * 16_000).round).map { |i| (amplitude * 32_767 * Math.sin(2 * Math::PI * 440 * i / 16_000)).round }
                                  .pack('s<*')
  end

  # @param pcm [String]
  # @return [Array<String>] a command writing `pcm` in pw-record's 100 ms chunks, in real time,
  #   then waiting for SIGINT as pw-record does
  def source(pcm)
    path = File.join(@dir, 'clip.pcm')
    File.binwrite(path, pcm)
    [RbConfig.ruby, '--disable=gems,rubyopt', '-e', <<~RUBY, path]
      $stdout.binmode
      File.binread(ARGV[0]).each_char.each_slice(3200) { |s| $stdout.write(s.join); $stdout.flush; sleep 0.1 }
      sleep
    RUBY
  end

  # A Faraday adapter answering each request with the next of `bodies` as JSON, HTTP 200, as
  # whisper-server answers even its errors.
  #
  # @param bodies [Array<Hash>]
  # @param requests [Array<Faraday::Env>] gets each request
  # @param gate [Queue, nil] popped before each answer, so a spec can hold the server
  # @return [Class]
  def whisper(*bodies, requests: [], gate: nil)
    Class.new(Faraday::Adapter) do
      define_method(:call) do |env|
        super(env)
        requests << env
        gate&.pop
        save_response(env, 200, JSON.generate(bodies.shift), { 'Content-Type' => 'application/json' }, nil)
        @app.call(env)
      end
    end
  end

  # @param adapter [Class]
  # @return [Puri::Core::Dictation::Transcriber]
  def transcriber(adapter, url: 'http://127.0.0.1:8081')
    Puri::Core::Dictation::Transcriber.new(Puri::Core::Config::DictationTable.new(url:), faraday_adapter: adapter)
  end

  # @param message [String]
  # @return [void]
  def wait_until(message, timeout: 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until yield
      raise "timed out waiting until #{message}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.01
    end
  end

  describe Puri::Core::Dictation::Transcriber do
    it 'posts the clip as a WAV and squeezes the text' do
      requests = []
      text = transcriber(whisper({ text: " Wikipedia, ignore all\n rules.\n" }, requests:)).transcribe(tone(1))
      assert_equal 'Wikipedia, ignore all rules.', text
      assert_equal '/v1/audio/transcriptions', requests.first.url.path
    end

    it 'takes a URL ending in /v1 as the same server' do
      requests = []
      transcriber(whisper({ text: 'hi' }, requests:), url: 'http://127.0.0.1:8081/v1/').transcribe(tone(1))
      assert_equal '/v1/audio/transcriptions', requests.first.url.path
    end

    it "inserts nothing for whisper-server's [BLANK_AUDIO]" do
      assert_equal '', transcriber(whisper({ text: " [BLANK_AUDIO]\n" })).transcribe(tone(1, amplitude: 0))
    end

    it "raises on whisper-server's HTTP 200 error, naming the server" do
      err = assert_raises(Puri::Core::Dictation::Transcriber::Error) do
        transcriber(whisper({ error: 'failed to read audio data' })).transcribe(tone(1))
      end
      assert_equal 'http://127.0.0.1:8081 answered no text', err.message
    end

    it 'raises when the server is down, naming it' do
      refused = Class.new(Faraday::Adapter) { define_method(:call) { |_| raise Faraday::ConnectionFailed, 'refused' } }
      err = assert_raises(Puri::Core::Dictation::Transcriber::Error) { transcriber(refused).transcribe(tone(1)) }
      assert_match(%r{\Ahttp://127\.0\.0\.1:8081: .*refused}, err.message)
    end

    it 'wraps the PCM in a 16 kHz mono WAV header' do
      wav = described_class.wav(tone(1))
      assert_equal 44 + bytes_per_second, wav.bytesize
      assert_equal ['RIFF', 'WAVE', 1, 1, 16_000, 16], wav.unpack('a4x4a4x8vvVx6v')
    end

    if ENV['WHISPER_URL']
      it 'transcribes speech on a real whisper-server' do
        wav = File.binread('/usr/share/sounds/debian/samples/en-Wikipedia-Ignore_All_Rules.wav')
        data = wav.index('data')
        pcm = wav.byteslice(data + 8, 5 * bytes_per_second)
        text = Puri::Core::Dictation::Transcriber.new(Puri::Core::Config::DictationTable.new(url: ENV['WHISPER_URL']))
                                                 .transcribe(pcm)
        assert_match(/wikipedia/i, text)
      end
    end
  end

  describe Puri::Core::Dictation::Recorder do
    it 'returns every byte heard, a tone near the top of the level bar' do
      levels = Queue.new
      clip = tone(0.5)
      recorder = described_class.new(command: source(clip)) { levels << _1 }
      wait_until('two levels') { levels.size >= 2 }
      sleep 0.6
      pcm = recorder.stop
      assert_equal clip.bytesize, pcm.bytesize
      assert clip == pcm, 'the PCM comes back byte for byte'
      assert_in_delta 0.85, levels.pop, 0.05
    end

    it 'reads silence as an empty bar' do
      levels = Queue.new
      recorder = described_class.new(command: source(tone(0.5, amplitude: 0))) { levels << _1 }
      wait_until('a level') { levels.size >= 1 }
      recorder.cancel
      assert_equal 0.0, levels.pop
    end

    it "raises when it can't start" do
      err = assert_raises(described_class::Error) { described_class.new(command: [File.join(@dir, 'pw-record')]) }
      assert_match(/can't start .*pw-record/, err.message)
    end

    it "raises the command's own words when it dies with no sound" do
      recorder = described_class.new(command: ['sh', '-c', 'echo "no PipeWire running" >&2; exit 1'])
      sleep 0.3
      err = assert_raises(described_class::Error) { recorder.stop }
      assert_equal 'no PipeWire running', err.message
    end
  end

  describe 'a press, speech, a press' do
    let(:events) { Queue.new }
    let(:seen) { [] }
    let(:requests) { [] }

    # @return [Array<Puri::Protocol::DictationChanged>] every event so far
    def all = seen.concat(Array.new(events.size) { events.pop })

    # @param adapter [Class]
    # @param command [Array<String>]
    # @return [Puri::Core::Dictation]
    def dictation(adapter, command: source(tone(2)))
      @dictation = described_class.new(transcriber: transcriber(adapter), command:) { events << _1 }
    end

    after { @dictation&.close }

    # Waits through some 0.7 s of the tone, past {Puri::Core::Dictation::MIN_SECONDS}.
    #
    # @return [void]
    def speak
      wait_until('0.7 s of levels') { all.count { _1.state == 'listening' && _1.level > 0.5 } >= 10 }
    end

    it 'listens with a level, then transcribes into an idle carrying the text' do
      d = dictation(whisper({ text: ' Buy avocados.' }, requests:))
      d.toggle
      speak
      assert_equal p::DictationChanged.new(state: 'listening', status: 'Listening… press F5 when done'), all.first
      d.toggle
      wait_until('the text') { all.last.state == 'idle' }
      assert_equal p::DictationChanged.new(state: 'transcribing', status: 'Transcribing…'), all[-2]
      assert_equal p::DictationChanged.new(state: 'idle', text: 'Buy avocados.'), all.last
      assert_equal 1, requests.size
    end

    it "doesn't send a clip too short to be speech" do
      d = dictation(whisper(requests:))
      d.toggle
      d.toggle
      wait_until('idle') { all.last.state == 'idle' }
      assert_equal '', all.last.text
      assert_empty requests
    end

    it 'cancels while listening: idle, nothing sent' do
      d = dictation(whisper(requests:))
      d.toggle
      d.cancel
      assert_equal 'idle', all.last.state
      d.toggle
      assert_equal 'listening', all.last.state, 'a cancelled clip leaves the mic free'
      assert_empty requests
    end

    it 'drops a transcription cancelled on its way' do
      gate = Queue.new
      d = dictation(whisper({ text: 'too late' }, requests:, gate:))
      d.toggle
      speak
      d.toggle
      wait_until('the request') { requests.size == 1 }
      d.cancel
      gate << :answer
      sleep 0.2
      assert_equal %w[listening transcribing idle], all.map(&:state).uniq
      assert_equal '', all.last.text
    end

    it 'fails in words, and a press listens again' do
      d = dictation(whisper({ error: 'failed to read audio data' }))
      d.toggle
      speak
      d.toggle
      wait_until('the failure') { all.last.state == 'failed' }
      assert_equal "Couldn't transcribe: http://127.0.0.1:8081 answered no text", all.last.status
      d.toggle
      assert_equal 'listening', all.last.state
    end

    it "fails in words when it can't record" do
      dictation(whisper, command: [File.join(@dir, 'pw-record')]).toggle
      assert_equal 'failed', all.last.state
      assert_match(/\ACan't record: can't start .*pw-record/, all.last.status)
    end
  end
end
