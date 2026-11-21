# frozen_string_literal: true

require 'monitor'

module Puri
  module Core
    # The mic in the prompt (`D_dictation`): one clip per press, recorded by {Recorder},
    # transcribed by {Transcriber} on the user's own server, every step a
    # {Protocol::DictationChanged}.
    #
    #   dictation = Dictation.new(transcriber: Dictation::Transcriber.new(config.dictation)) { |event| … }
    #   dictation.toggle   # listening, its level ~15 times a second
    #   dictation.toggle   # transcribing, then idle with text: "Buy avocados."
    #   dictation.cancel   # Escape: idle, nothing inserted; a late transcription is dropped
    #
    # A clip under {MIN_SECONDS} isn't sent: a stray press would cost the server's 7 s floor.
    #
    # Thread-safe; {#toggle} and {#cancel} return at once, the recorder stopping and the server
    # answering on a thread of their own.
    class Dictation
      # @return [String]
      LISTENING = 'Listening… press F5 when done'

      # @return [String]
      TRANSCRIBING = 'Transcribing…'

      # @return [Float] seconds
      MIN_SECONDS = 0.5

      # @return [Logger]
      LOGGER = Pikuri.logger_for('Dictation')

      # @param transcriber [Puri::Core::Dictation::Transcriber, #transcribe]
      # @param command [Array<String>] the {Recorder}'s
      # @yieldparam event [Puri::Protocol::DictationChanged] on whichever thread caused it
      # @yieldreturn [void]
      def initialize(transcriber:, command: Recorder::COMMAND, &emit)
        @transcriber = transcriber
        @command = command
        @emit = emit
        @lock = Monitor.new
        @state = 'idle'
        @clip = 0
        @recorder = nil
      end

      # (see Puri::Protocol::Backend#toggle_dictation)
      def toggle
        @lock.synchronize do
          case @state
          when 'idle', 'failed' then listen
          when 'listening' then stop
          end
        end
      end

      # (see Puri::Protocol::Backend#cancel_dictation)
      def cancel
        recorder = drop
        Thread.new { recorder.cancel } if recorder
      end

      # Stops the mic, waiting for the recorder to exit.
      #
      # @return [void]
      def close = drop&.cancel

      private

      # @return [Puri::Core::Dictation::Recorder, nil] the one recording, now forgotten
      def drop
        @lock.synchronize do
          next if @state == 'idle'

          @clip += 1
          change('idle')
          @recorder.tap { @recorder = nil }
        end
      end

      # @return [void]
      def listen
        clip = @clip += 1
        @recorder = Recorder.new(command: @command) { |level| heard(clip, level) }
        change('listening', status: LISTENING)
      rescue Recorder::Error => e
        failed("Can't record: #{e.message}")
      end

      # @param clip [Integer]
      # @param level [Float]
      # @return [void]
      def heard(clip, level)
        @lock.synchronize { change('listening', status: LISTENING, level:) if current?(clip, 'listening') }
      end

      # @return [void]
      def stop
        recorder = @recorder
        @recorder = nil
        clip = @clip
        change('transcribing', status: TRANSCRIBING)
        Thread.new { transcribe(recorder, clip) }
      end

      # @param recorder [Puri::Core::Dictation::Recorder]
      # @param clip [Integer]
      # @return [void]
      def transcribe(recorder, clip)
        pcm = recorder.stop
        text = pcm.bytesize < MIN_SECONDS * Recorder::BYTES_PER_SECOND ? '' : @transcriber.transcribe(pcm)
        @lock.synchronize { change('idle', text:) if current?(clip, 'transcribing') }
      rescue Recorder::Error => e
        @lock.synchronize { failed("Can't record: #{e.message}") if current?(clip, 'transcribing') }
      rescue StandardError => e
        @lock.synchronize { failed("Couldn't transcribe: #{e.message}") if current?(clip, 'transcribing') }
      end

      # @param clip [Integer]
      # @param state [String]
      # @return [Boolean] whether `clip` is still the one in `state`, not cancelled or replaced
      def current?(clip, state) = @clip == clip && @state == state

      # @param status [String]
      # @return [void]
      def failed(status)
        LOGGER.warn(status)
        change('failed', status:)
      end

      # @param state [String]
      # @param fields [Hash{Symbol => Object}] the rest of the {Protocol::DictationChanged}
      # @return [void]
      def change(state, **fields)
        @state = state
        @emit.call(Protocol::DictationChanged.new(state:, **fields))
      end
    end
  end
end
