# frozen_string_literal: true

require 'ruby_llm'
require 'stringio'

module Puri
  module Core
    class Dictation
      # Turns a clip into text on the `[dictation]` server, OpenAI's `/v1/audio/transcriptions`,
      # through a RubyLLM context of its own rather than pikuri (`D_dictation`).
      #
      #   transcriber = Transcriber.new(config.dictation)
      #   transcriber.transcribe(pcm)   # => "Buy avocados and limes."
      #   transcriber.transcribe(hush)  # => "" for whisper-server's " [BLANK_AUDIO]\n"
      #
      # == Implementation details
      #
      # whisper-server reports a failure as HTTP 200 with `{"error": …}`, which RubyLLM reads as
      # `text: nil`, its message lost; that raises here. No retries: a dead server should say so
      # at once, and a retry would cost the encoder's 7 s floor again.
      #
      # Thread-safe.
      class Transcriber
        # Raised when the server can't be reached or transcribes nothing.
        class Error < StandardError; end

        # @return [Integer] seconds a clip may take; whisper.cpp's `small.en` on 4 CPU threads
        #   takes ~20 for a minute's speech
        TIMEOUT = 120

        # @param table [Puri::Core::Config::DictationTable]
        # @param faraday_adapter [Class, Symbol, nil] what specs script the server with; nil for
        #   RubyLLM's own
        def initialize(table, faraday_adapter: nil)
          @url = table.url
          @model = table.model
          # Auto sends none, so a server's own `-l` decides; OpenAI's would refuse "auto".
          @language = table.language == Config::DictationTable::AUTO ? {} : { language: table.language }
          @context = RubyLLM.context do |config|
            config.openai_api_base = "#{table.url.chomp('/').delete_suffix('/v1')}/v1"
            config.openai_api_key = table.api_key || 'not-needed'
            config.max_retries = 0
            config.request_timeout = TIMEOUT
            config.faraday_adapter = faraday_adapter if faraday_adapter
          end
        end

        # @param pcm [String] 16 kHz mono s16le, as {Recorder#stop} returns it
        # @return [String] the text squeezed to single spaces; empty when Whisper heard only its
        #   bracketed tags, `[BLANK_AUDIO]` and the like
        # @raise [Error] naming the server
        def transcribe(pcm)
          clip = RubyLLM::Attachment.new(StringIO.new(Transcriber.wav(pcm)), filename: 'clip.wav',
                                                                             mime_type: 'audio/wav')
          text = @context.transcribe(clip, model: @model, provider: :openai, assume_model_exists: true,
                                           **@language).text
          raise Error, "#{@url} answered no text" unless text

          Dictation.squeeze(text)
        rescue RubyLLM::Error, Faraday::Error => e
          raise Error, "#{@url}: #{e.message}"
        end

        # @param pcm [String] 16 kHz mono s16le
        # @return [String] `pcm` behind a 44-byte WAV header, binary
        def self.wav(pcm)
          rate = Recorder::BYTES_PER_SECOND / 2
          header = ['RIFF', 36 + pcm.bytesize, 'WAVE', 'fmt ', 16, 1, 1, rate, Recorder::BYTES_PER_SECOND, 2, 16,
                    'data', pcm.bytesize].pack('a4Va4a4VvvVVvva4V')
          header + pcm.b
        end
      end
    end
  end
end
