# frozen_string_literal: true

require 'json'

module Puri
  module Eval
    # Today's `report.md`, from its `results.jsonl` and `configurations.jsonl`: per configuration
    # and tier the pass rate, pass^3 (every run of a task passed), tool errors, median time to
    # the first streamed word and to the end, and the box's tokens a second; then each task's
    # passes per configuration, and the checks that failed most.
    #
    #   Report.new(day_dir).write   # => the report's path
    class Report
      # @param day_dir [String]
      def initialize(day_dir)
        @day_dir = day_dir
        @rows = jsonl('results.jsonl')
        @configs = jsonl('configurations.jsonl').to_h { [_1['configuration'], _1] }
      end

      # @return [String] the report's path
      def write
        path = File.join(@day_dir, 'report.md')
        File.write(path, markdown)
        path
      end

      # @return [String]
      def markdown
        names = @rows.map { _1['configuration'] }.uniq
        [
          "# Model eval, #{File.basename(@day_dir)}", '',
          summary(names), '',
          '## Per task: runs passed', '', per_task(names), '',
          '## The checks that failed', '', failures(names), ''
        ].join("\n")
      end

      private

      # @param names [Array<String>]
      # @return [String]
      def summary(names)
        lines = ['| Configuration | Tier | Runs | Pass | Pass^3 | Tool errors | First word, median | ' \
                 'Turn, median | Prompt tok/s | Gen tok/s | First prompt | Load | Cold start |',
                 '|---|---|---|---|---|---|---|---|---|---|---|---|---|']
        names.each do |name|
          config = @configs[name] || {}
          [*Task::TIERS, 'all'].each do |tier|
            rows = @rows.select { _1['configuration'] == name && (tier == 'all' || _1['tier'] == tier) }
            next if rows.empty?

            lines << row(name, tier, rows, config)
          end
        end
        lines.join("\n")
      end

      # @param name [String]
      # @param tier [String]
      # @param rows [Array<Hash{String => Object}>]
      # @param config [Hash{String => Object}]
      # @return [String]
      def row(name, tier, rows, config)
        turns = rows.flat_map { _1['turns'] }
        box = rows.map { _1['box'] }
        cells = [name, tier, rows.size, percent(rows.count { _1['pass'] }, rows.size), pass3(rows),
                 turns.sum { _1['errors'].to_i }, seconds(median(turns.filter_map { _1['first_stream'] })),
                 seconds(median(turns.map { _1['seconds'] })),
                 rate(box.sum { _1['prompt_tokens'] }, box.sum { _1['prompt_seconds'] }),
                 rate(box.sum { _1['tokens_predicted'] }, box.sum { _1['tokens_predicted_seconds'] }),
                 median(rows.filter_map { _1['first_prompt'] })&.round,
                 tier == 'all' ? seconds(config['load_seconds']) : '',
                 tier == 'all' ? seconds(config.dig('cold', 'first_stream')) : '']
        "| #{cells.join(' | ')} |"
      end

      # @param names [Array<String>]
      # @return [String]
      def per_task(names)
        tasks = @rows.map { [_1['task'], _1['tier']] }.uniq
        lines = ["| Task | Tier | #{names.join(' | ')} |", "|---|---|#{'---|' * names.size}"]
        tasks.each do |task, tier|
          cells = names.map do |name|
            rows = @rows.select { _1['configuration'] == name && _1['task'] == task }
            rows.empty? ? '' : "#{rows.count { _1['pass'] }}/#{rows.size}"
          end
          lines << "| #{task} | #{tier} | #{cells.join(' | ')} |"
        end
        lines.join("\n")
      end

      # @param names [Array<String>]
      # @return [String]
      def failures(names)
        names.map do |name|
          failed = @rows.select { _1['configuration'] == name }.flat_map do |r|
            r['checks'].reject { _1['pass'] }.map { "#{r['task']}: #{_1['check']}" }
          end
          tally = failed.tally.sort_by { -_2 }.first(12).map { |what, count| "#{what} ×#{count}" }
          "- **#{name}:** #{tally.empty? ? 'none' : tally.join(', ')}"
        end.join("\n")
      end

      # @param rows [Array<Hash{String => Object}>]
      # @return [String] tasks whose every run passed, of all tasks
      def pass3(rows)
        by_task = rows.group_by { _1['task'] }
        percent(by_task.count { |_, runs| runs.all? { _1['pass'] } }, by_task.size)
      end

      # @param part [Integer]
      # @param whole [Integer]
      # @return [String]
      def percent(part, whole) = whole.zero? ? '–' : "#{(100.0 * part / whole).round} %"

      # @param tokens [Float]
      # @param secs [Float]
      # @return [String]
      def rate(tokens, secs) = secs.to_f.positive? ? (tokens / secs).round(1).to_s : '–'

      # @param value [Float, nil]
      # @return [String]
      def seconds(value) = value ? format('%.1f s', value) : '–'

      # @param values [Array<Numeric>]
      # @return [Float, nil]
      def median(values)
        return nil if values.empty?

        sorted = values.sort
        mid = sorted.size / 2
        sorted.size.odd? ? sorted[mid].to_f : (sorted[mid - 1] + sorted[mid]) / 2.0
      end

      # @param file [String]
      # @return [Array<Hash{String => Object}>]
      def jsonl(file)
        path = File.join(@day_dir, file)
        File.exist?(path) ? File.readlines(path).map { JSON.parse(_1) } : []
      end
    end
  end
end
