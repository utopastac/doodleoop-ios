# frozen_string_literal: true

# Frameit patches:
# - `tracking` on keyword/title (ImageMagick kerning)
# - `title_stack_spacing` between stacked keyword and title (Frameit defaults
#   to keyword_font_size / 2, which reads too airy for SF Pro)

require "frameit/editor"

module Frameit
  class Editor
    def put_title_into_background_stacked(background, title, keyword)
      resize_text(title)
      resize_text(keyword)

      vertical_padding = vertical_frame_padding
      spacing_between_title_and_keyword = if @config.key?("title_stack_spacing")
        @config["title_stack_spacing"].to_f
      else
        (actual_font_size("keyword") / 2)
      end
      title_left_space = (background.width / 2.0 - title.width / 2.0).round
      keyword_left_space = (background.width / 2.0 - keyword.width / 2.0).round

      self.space_to_device += title.height + keyword.height + spacing_between_title_and_keyword + vertical_padding

      if title_below_image
        keyword_top = background.height - effective_text_height / 2 - (keyword.height + spacing_between_title_and_keyword + title.height) / 2
      else
        keyword_top = device_top(background) / 2 - spacing_between_title_and_keyword / 2 - keyword.height
      end
      title_top = keyword_top + keyword.height + spacing_between_title_and_keyword

      background = background.composite(keyword, "png") do |c|
        c.compose("Over")
        c.geometry("+#{keyword_left_space}+#{keyword_top}")
      end
      background = background.composite(title, "png") do |c|
        c.compose("Over")
        c.geometry("+#{title_left_space}+#{title_top}")
      end
      background
    end

    def build_text_images(max_width, max_height)
      words = [:keyword, :title].keep_if { |a| fetch_text(a) }
      results = {}
      trim_boxes = {}
      top_vertical_trim_offset = Float::INFINITY
      bottom_vertical_trim_offset = 0

      words.each do |key|
        empty_path = File.join(Frameit::ROOT, "lib/assets/empty.png")
        text_image = MiniMagick::Image.open(empty_path)
        image_height = max_height
        text_image.combine_options do |i|
          i.resize("#{max_width * 5.0}x#{image_height}!")
        end

        current_font = font(key)
        text = fetch_text(key)
        UI.verbose("Using #{current_font} as font the #{key} of #{screenshot.path}") if current_font
        UI.verbose("Adding text '#{text}'")

        text.gsub!('\n', "\n")
        text.gsub!(/(?<!\\)(')/) { |s| "\\#{s}" }

        interline_spacing = @config["interline_spacing"]
        tracking = @config[key.to_s]["tracking"]

        text_image.combine_options do |i|
          i.font(current_font) if current_font
          i.weight(@config[key.to_s]["font_weight"]) if @config[key.to_s]["font_weight"]
          i.gravity("Center")
          i.pointsize(actual_font_size(key))
          i.kerning(tracking) unless tracking.nil?
          i.draw("text 0,0 '#{text}'")
          i.interline_spacing(interline_spacing) if interline_spacing
          i.fill(@config[key.to_s]["color"])
        end

        results[key] = text_image

        calculated_trim_box = text_image.identify do |b|
          b.format("%@")
        end

        trim_box = Frameit::Trimbox.new(calculated_trim_box)

        if trim_box.offset_y < top_vertical_trim_offset
          top_vertical_trim_offset = trim_box.offset_y
        end

        if (trim_box.offset_y + trim_box.height) > bottom_vertical_trim_offset
          bottom_vertical_trim_offset = trim_box.offset_y + trim_box.height
        end

        trim_boxes[key] = trim_box
      end

      words.each do |key|
        trim_box = trim_boxes[key]

        if trim_box.offset_y > top_vertical_trim_offset
          trim_box.height += trim_box.offset_y - top_vertical_trim_offset
          trim_box.offset_y = top_vertical_trim_offset
          UI.verbose("Trim box for key \"#{key}\" is adjusted to align top: #{trim_box.json_string_format}")
        end

        if (trim_box.offset_y + trim_box.height) < bottom_vertical_trim_offset
          trim_box.height = bottom_vertical_trim_offset - trim_box.offset_y
          UI.verbose("Trim box for key \"#{key}\" is adjusted to align bottom: #{trim_box.json_string_format}")
        end

        results[key].crop(trim_box.string_format)
      end

      results
    end
  end
end
