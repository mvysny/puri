# frozen_string_literal: true

require 'zlib'

module Puri
  module Desktop
    # A {Protocol::Map} under an answer: its tiles, a numbered pin per place, a dot where a search
    # started, a route's line, the view fitted to all of them, and the map's note under it.
    #
    #   PlaceMap.new(block)                              # a pin click opens the place in GNOME Maps
    #   PlaceMap.new(block) { |url| opened << url }      # a spec's
    #
    # The wheel over the map zooms it and a drag pans it; neither scrolls the answer nor moves the
    # window.
    class PlaceMap < Gtk::Box
      # @return [Integer] pixels
      HEIGHT = 280
      # @return [Integer] what the view is fitted to until the map has a width of its own
      ASSUMED_WIDTH = 600
      # @return [String] OSM's attribution page, which the license line links to
      COPYRIGHT = 'https://www.openstreetmap.org/copyright'
      # @return [Gdk::RGBA] a route's line: Adwaita's blue
      ROUTE = Gdk::RGBA.new(0.21, 0.52, 0.89, 0.9)

      # @return [Shumate::SimpleMap]
      attr_reader :map

      # @return [Gtk::Label] the block's note
      attr_reader :note

      # @param block [Puri::Protocol::Map]
      # @yieldparam url [String] a clicked pin's place; without a block, {MapsLauncher.open} opens it
      # @yieldreturn [void]
      def initialize(block, &on_open)
        super(:vertical, 6)
        @on_open = on_open || ->(url) { MapsLauncher.open(url) }
        @map = Shumate::SimpleMap.new
        @map.set_size_request(-1, HEIGHT)
        @map.overflow = :hidden
        @map.add_css_class('puri-map')
        keep_the_drag
        @note = Gtk::Label.new
        @note.wrap = true
        @note.xalign = 0
        @note.add_css_class('puri-map-note')
        append(@map)
        append(@note)
        @layers = []
        self.block = block
      end

      # @param block [Puri::Protocol::Map]
      # @return [void]
      def block=(block)
        return if block == @block

        @block = block
        @map.map_source = source(block)
        @layers.each { @map.remove_overlay_layer(_1) }
        @layers = [line_layer(block.line), pin_layer(block.pins)]
        @layers.each { @map.add_overlay_layer(_1) }
        @note.markup = block.note.to_s
        @note.visible = !block.note.nil?
        look(ASSUMED_WIDTH)
        refit_once_sized
      end

      # @return [Array<Gtk::Button>] one per pin, in the block's order
      def pins = @pin_buttons.dup

      # The center and zoom that show every point with a margin around them, on a Web Mercator
      # map of `tile_size` tiles. The zoom is fractional, as libshumate takes it, so the points
      # fill the view.
      #
      #   PlaceMap.fit([[60.2916, 24.9657], [60.2931, 25.0307]], width: 600, height: 280)
      #   # => [60.29236…, 24.99821…, 12.98…]
      #
      # @param points [Array<Array<Float>>] `[lat, lon]`, at least one
      # @param width [Integer] pixels
      # @param height [Integer] pixels
      # @param tile_size [Integer] pixels
      # @param margin [Integer] pixels kept free on each side, for the pins and the zoom buttons
      # @param max_zoom [Float] for a single place, or places metres apart
      # @return [Array(Float, Float, Float)] latitude, longitude, zoom level
      def self.fit(points, width:, height:, tile_size: 256, margin: 48, max_zoom: 16.0)
        xs = points.map { |_, lon| (lon + 180) / 360.0 }
        ys = points.map { |lat, _| mercator_y(lat) }
        # A world's width in pixels at zoom z is tile_size * 2**z; each span must fit its side.
        fits = [[xs.max - xs.min, width], [ys.max - ys.min, height]].filter_map do |span, side|
          Math.log2((side - (2 * margin)) / (span * tile_size)) if span.positive?
        end
        zoom = (fits + [max_zoom]).min.clamp(1.0, max_zoom)
        y = (ys.min + ys.max) / 2
        lat = Math.atan(Math.sinh(Math::PI * (1 - (2 * y)))) * 180 / Math::PI
        lon = (((xs.min + xs.max) / 2) * 360) - 180
        [lat, lon, zoom]
      end

      # @param lat [Float]
      # @return [Float] 0 at the top of the world map, 1 at the bottom
      def self.mercator_y(lat)
        rad = lat.clamp(-85.05, 85.05) * Math::PI / 180
        (1 - (Math.log(Math.tan(rad) + (1 / Math.cos(rad))) / Math::PI)) / 2
      end

      private

      # @param block [Puri::Protocol::Map]
      # @return [Shumate::RasterRenderer]
      def source(block)
        renderer = Shumate::RasterRenderer.new(block.tiles)
        # Stable across runs: libshumate's tile cache on disk is per source id.
        renderer.id = "puri-#{Zlib.crc32(block.tiles).to_s(36)}"
        renderer.name = 'Puri'
        renderer.license = block.license
        renderer.license_uri = COPYRIGHT
        renderer.max_zoom_level = 19
        renderer
      end

      # libshumate's pan never claims its drag, so past the drag threshold the popup's WindowHandle
      # would take it and move the window. Claimed there and not on press, a click still reaches a pin.
      #
      # @return [void]
      def keep_the_drag
        controllers = @map.map.observe_controllers
        pan = Array.new(controllers.n_items) { controllers.get_item(_1) }.grep(Gtk::GestureDrag).first
        pan.signal_connect('drag-update') do |gesture, x, y|
          gesture.set_state(:claimed) if @map.drag_check_threshold(0, 0, x.to_i, y.to_i)
        end
      end

      # @param points [Array<Array<Float>>]
      # @return [Shumate::PathLayer]
      def line_layer(points)
        layer = Shumate::PathLayer.new(@map.viewport)
        layer.stroke_width = 5
        layer.stroke_color = ROUTE
        points.each { |lat, lon| layer.add_node(Shumate::Coordinate.new(lat, lon)) }
        layer
      end

      # @param pins [Array<Puri::Protocol::Pin>]
      # @return [Shumate::MarkerLayer]
      def pin_layer(pins)
        layer = Shumate::MarkerLayer.new(@map.viewport)
        @pin_buttons = pins.map do |pin|
          # A dot has no label at all: an empty one still takes a line's height.
          button = pin.label ? Gtk::Button.new(label: pin.label) : Gtk::Button.new
          button.add_css_class(pin.label ? 'puri-pin' : 'puri-pin-dot')
          button.tooltip_text = pin.name
          button.signal_connect('clicked') { @on_open.call(pin.url) }
          marker = Shumate::Marker.new
          marker.child = button
          marker.set_location(pin.lat, pin.lon)
          layer.add_marker(marker)
          button
        end
        layer
      end

      # @param width [Integer]
      # @return [void]
      def look(width)
        points = @block.pins.map { [_1.lat, _1.lon] } + @block.line
        return if points.empty?

        lat, lon, zoom = PlaceMap.fit(points, width:, height: HEIGHT)
        @map.viewport.zoom_level = zoom
        @map.map.center_on(lat, lon)
      end

      # The real width is known only once laid out, at the first frame.
      #
      # @return [void]
      def refit_once_sized
        @map.add_tick_callback do
          next true unless @map.width.positive?

          look(@map.width) unless @map.width == ASSUMED_WIDTH
          false
        end
      end
    end
  end
end
