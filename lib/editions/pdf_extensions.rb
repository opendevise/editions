module Asciidoctor
module Pdf
class Converter
  alias :normal_convert_paragraph :convert_paragraph

  def start_new_chapter sect
    if sect.index == 3
      import_page 'images/inserts/contegix-ad.pdf'
      start_new_page
    else
      # IMPORTANT we can't delegate to super because we are monkeypatching, not extending
      start_new_page unless at_page_top?
    end
  end

  def layout_chapter_title node, title
    if title.include? ': '
      primary_title, _, subtitle = title.rpartition ': '
    else
      primary_title = title
      subtitle = nil
    end
    keep_together do |box_height = nil|
      if box_height
        extra_height = bounds.absolute_top - cursor
        float do
          # FIXME clean this up!
          bounding_box [-bounds.absolute_left, bounds.absolute_top], width: bounds.absolute_right + bounds.absolute_left, height: box_height + extra_height do
            theme_fill_and_stroke_bounds :chapter_title
          end
        end
      end
      theme_font :chapter_byline do
        move_down @theme.vertical_rhythm / 2.0
        indent 0, @theme.horizontal_rhythm do
          headshot_width = 25
          headshot_height = 25
          author_name = node.document.attr 'author'
          if box_height && (username = node.document.attr 'username')
            float do
              name_width = width_of author_name
              left = bounds.width - name_width - headshot_width - 5
              # QUESTION look for avatar.jpg inside article directory?
              image %(images/avatars/#{username}.jpg), at: [left, cursor + headshot_width], width: headshot_width, height: headshot_height
            end
          end
          # FIXME use valign: :center inside a bounding box
          layout_prose author_name, align: :right, line_height: 1, margin_top: -headshot_height + (headshot_height - font.height) * 0.5, margin_bottom: 0
        end
      end
      move_down @theme.vertical_rhythm * 2
      indent @theme.horizontal_rhythm, @theme.horizontal_rhythm do
        if subtitle
          theme_font :chapter_title do
            layout_heading primary_title.upcase, margin_bottom: 0
          end
        else
          move_down @theme.vertical_rhythm * 2
        end
        indent @theme.horizontal_rhythm do
          move_up @theme.vertical_rhythm / 3.0
          theme_font :chapter_subtitle do
            subtitle_upper = (subtitle || primary_title).upcase
                .gsub(/(<\/?[A-Z]+?>|&[A-Z]+;)/) { $1.downcase }
                .sub(/<em>(.*)<\/em>/, '<color rgb="ffc14f">\1</color>')
            layout_heading subtitle_upper, margin_top: 2, line_height: 1.2
          end
        end
        move_down @theme.vertical_rhythm / 2.0
        stroke_horizontal_rule 'ffffff'
      end
      move_down @theme.vertical_rhythm / 2.0
    end
    move_down @theme.chapter_title_margin_bottom
  end

  def convert_paragraph node
    if (parent = node.parent).context == :section && node == parent.blocks[0] && parent.title == 'About the Author'
      layout_prose_around_image %(images/headshots/#{node.document.attr 'username'}.jpg), node.content, image_width: 75
    else
      normal_convert_paragraph node
    end
  end

  # TODO still needs some work with line metrics integration
  # FIXME leaves large gap between paragraphs if text doesn't match or exceed image height
  # TODO review calculations for padding around image (and spacing in general)
  def layout_prose_around_image image_file, text_string, opts = {}
    margin_top = (margin = (opts.delete :margin)) || (opts.delete :margin_top) || 0
    margin_bottom = margin || (opts.delete :margin_bottom) || @theme.vertical_rhythm
    line_metrics = calc_line_metrics opts.delete(:line_height) || @theme.base_line_height
    spacing_to_text = opts[:spacing_to_text] || @theme.horizontal_rhythm
    self.margin_top margin_top
    text_options = opts.select {|k,v| k.to_s.start_with? 'text_' }.map {|(k,v)| [ k.to_s[5..-1].to_sym, v ] }.to_h
    image_options = opts.select {|k,v| k.to_s.start_with? 'image_' }.map {|(k,v)| [ k.to_s[6..-1].to_sym, v ] }.to_h
    move_down line_metrics.padding_top
    move_down line_metrics.leading
    image_info = image image_file, image_options
    move_up line_metrics.leading
    image_height = image_info.scaled_height
    image_width = image_info.scaled_width
    move_up image_height
    text_align = (text_options[:align] || @theme.base_align || :justify).to_sym
    coordinates = case (image_options[:position] || :left)
    when :left
      { image_left: 0, text_x: image_width + spacing_to_text, text_y: cursor, text_height: image_height + line_metrics.height }
    when :right
      { image_left: bounds.right - image_width, text_x: 0, text_y: cursor, text_width: bounds.right - image_width - spacing_to_text, text_height: image_height + line_metrics.height }
    else
      warn %(asciidoctor: WARNING: Image position #{image_options[:position]} not supported.)
      return
    end
    #if opts[:bordered]
    #  bounding_box [coordinates[:image_left], cursor], width: image_width, height: image_height do
    #    line_width 0.25
    #    stroke_color 'CCCCCC'
    #    stroke_bounds
    #  end
    #  move_up image_height
    #end
    text_fragments = text_formatter.format text_string, normalize: (normalize = (opts.delete :normalize)) != false 
    text_fragments = text_fragments.map {|fragment|
      fragment[:color] ||= @font_color
      fragment
    }
    tbox = ::Prawn::Text::Formatted::Box.new text_fragments, at: [coordinates[:text_x], coordinates[:text_y]], width: coordinates[:text_width], height: coordinates[:text_height], final_gap: line_metrics.final_gap, leading: line_metrics.leading, align: text_align, document: self
    if (rest = tbox.render).empty?
      if tbox.height > image_height
        move_down tbox.height + line_metrics.padding_bottom
      else
        move_down image_height
      end
    else
      move_down tbox.height + line_metrics.leading
      formatted_text rest, align: text_align, color: @font_color, final_gap: line_metrics.final_gap, leading: line_metrics.leading, inline_format: [normalize: normalize != false]
      move_down line_metrics.padding_bottom
    end
    self.margin_bottom margin_bottom
  end

  def layout_toc doc, num_levels = 2, toc_page_num = 2
    go_to_page toc_page_num - 1
    start_new_page
    theme_font :heading, level: 2 do
      layout_prose doc.attr('toc-title').upcase, margin: 0
    end
    theme_font :chapter_title do
      # FIXME align me correctly (align to right of the toc title)
      indent @theme.horizontal_rhythm * 2.6 do
        revdate = ::DateTime.parse(doc.attr 'revdate')
        layout_prose %(#{(revdate.strftime '%B').upcase} #{revdate.strftime '%Y'}), margin_top: -4
      end
    end
    
    # FIXME force font color to base_font_color for links
    move_down @theme.vertical_rhythm
    layout_prose 'NFJS 2014 Tour Series Schedule', margin: 0, size: @theme.base_font_size_large, anchor: 'tour-schedule', link_color: @font_color, line_height: 1
    layout_prose 'From the Publisher', margin: 0, size: @theme.base_font_size_large, anchor: doc.sections[0].id, link_color: @font_color, line_height: 1
    move_down @theme.vertical_rhythm * 2

    theme_font :heading, level: 2 do
      label_text = 'FEATURES'
      label_height = height_of_typeset_text label_text, line_height: @theme.heading_line_height
      label_width = width_of label_text
      bounding_box [-left_margin, cursor], width: label_width + left_margin + @theme.horizontal_rhythm, height: label_height do
        fill_bounds 'ffc14f'
        indent left_margin do
          layout_heading label_text, margin: 0
        end
      end
    end
    move_down @theme.vertical_rhythm
    authors = (doc.attr 'authors').split ', '
    doc.sections[1..-1].each_with_index do |section, i|
      primary_title, subtitle = section.title.split(': ')
      theme_font :chapter_title do
        layout_prose primary_title.upcase, margin: 0, line_height: @theme.heading_line_height, anchor: section.id, link_color: @font_color
      end
      if subtitle
        layout_prose sanitize(subtitle).upcase.gsub('&', '&amp;'), margin_top: -4, margin_bottom: 0, line_height: @theme.heading_line_height, size: @theme.base_font_size_large, anchor: section.id, link_color: @font_color
      end
      indent @theme.horizontal_rhythm / 2.0 do
        if (description = ((section.attributes[:attribute_entries] || []) + (section.blocks[0].attributes[:attribute_entries] || [])).find {|entry| entry.name == 'description' })
          desc_fmt = ::Asciidoctor.convert description.value, doctype: :inline
          layout_prose desc_fmt, line_height: @theme.base_line_height, margin: 0, align: :left, size: @theme.base_font_size_small
        end
        layout_prose %(By #{authors[i]}), color: '666665', line_height: @theme.base_line_height, margin: 0, style: :italic
        indent 0, 3 do
          layout_prose %(Page #{(section.attr 'page_start') - 1}), line_height: 1, margin: 0, style: :bold, align: :right, anchor: section.id, link_color: @font_color
        end
      end
      move_down @theme.vertical_rhythm / 2.0
      stroke_horizontal_rule 'DEDEDC'
      move_down @theme.vertical_rhythm
    end

    render_credits_page doc
    import_page 'images/inserts/nfjstour-ad.pdf'
    add_dest 'tour-schedule', (dest_top page_number)

    toc_page_nums = (toc_page_num..page_number)
    go_to_page page_count - 1
    toc_page_nums
  end

  def render_credits_page doc
    start_new_page

    define_grid columns: 2, rows: 16, row_gutter: 0, column_gutter: @theme.horizontal_rhythm
    grid([0,0], [4,1]).bounding_box do
      logo_width = 232
      svg IO.read('images/jacket/nfjs-magazine.svg'), at: [((bounds.width / 2.0) - (logo_width / 2.0)).floor, cursor], width: logo_width
    end

    grid([4,0],[4,0]).bounding_box do
      layout_prose 'Publisher and Editor in Chief', align: :right, margin: 0, style: :bold, size: @theme.base_font_size_large
    end

    grid([4,1],[4,1]).bounding_box do
      layout_prose 'Jay Zimmerman - NFJS One', margin_bottom: -4, size: @theme.base_font_size_large
      layout_prose 'jzimmerman@nofluffjuststuff.com', color: '4F4F4E', margin: 0
    end

    grid([5,0],[5,0]).bounding_box do
      layout_prose 'Technical Editor', align: :right, margin: 0, style: :bold, size: @theme.base_font_size_large
    end

    grid([5,1],[5,1]).bounding_box do
      layout_prose 'Matt Stine', margin_bottom: -4, size: @theme.base_font_size_large
      layout_prose 'matt@nofluffjuststuff.com', color: '4F4F4E', margin: 0
    end

    grid([6,0],[6,0]).bounding_box do
      layout_prose 'Production and UX', align: :right, margin: 0, size: @theme.base_font_size_large
    end

    grid([6,1],[7,1]).bounding_box do
      layout_prose 'Dan Allen - OpenDevise Inc.', margin_bottom: -4, size: @theme.base_font_size_large
      layout_prose '@mojavelinux', color: '4F4F4E', margin: 0
      layout_prose 'Sarah White - OpenDevise Inc.', margin_bottom: -4, size: @theme.base_font_size_large
      layout_prose '@carbonfray', color: '4F4F4E', margin: 0
    end

    grid([8,0],[8,0]).bounding_box do
      layout_prose 'Cover Artwork', align: :right, margin: 0, size: @theme.base_font_size_large
    end

    grid([8,1],[8,1]).bounding_box do
      layout_prose 'Alicia Weller', margin: 0, size: @theme.base_font_size_large
    end

    grid([9,0],[9,0]).bounding_box do
      layout_prose %(Issue #{doc.attr 'edition'} Contributors), align: :right, margin: 0, size: @theme.base_font_size_large
    end

    grid([9,1],[11,1]).bounding_box do
      layout_prose doc.attr('authors').gsub(', ', "\n"), normalize: false, size: @theme.base_font_size_large, line_height: 1.2, margin_top: 2
    end

    grid([11.75,0],[11.75,1]).bounding_box do
      fill_bounds '666665'
      layout_prose 'HOW TO REACH US', align: :center, color: 'FFFFFF', size: 16, margin: 0, valign: :center, line_height: 1
    end

    grid([13,0],[14,0]).bounding_box do
      layout_prose 'Advertising', style: :bold, align: :right, margin: 0
      layout_prose 'For information about advertising in NFJS, the Magazine, email Jay Zimmerman at jzimmerman@nofluffjuststuff.com', margin: 0, align: :right, line_height: 1.2, size: @theme.base_font_size_small
    end

    grid([13,1],[14,1]).bounding_box do
      layout_prose 'Events', style: :bold, align: :left, margin: 0
      layout_prose 'For the latest news about NFJS events, visit <link anchor="http://nofluffjuststuff.com">nofluffjuststuff.com</link>', margin: 0, align: :left, line_height: 1.2, size: @theme.base_font_size_small
    end

    grid([14.5,0],[15.5,0]).bounding_box do
      layout_prose 'Office of the Publisher', style: :bold, align: :right, margin: 0
      layout_prose '5023 W. 120th Avenue, Suite #289
Broomfield, CO 80020
(303) 469-0486', margin: 0, align: :right, line_height: 1.2, size: @theme.base_font_size_small, normalize: false
    end

    grid([14.5,1],[15.5,1]).bounding_box do
      layout_prose 'Social', style: :bold, align: :left, margin: 0
      layout_prose 'Follow <link anchor="https://twitter.com/nofluff">@nofluff</link> on Twitter
Join <link anchor="http://www.linkedin.com/groups/No-Fluff-Just-Stuff-1653697/about">NFJS</link> on LinkedIn
Watch <link anchor="http://www.nofluffjuststuff.com/m/network/index">NFJS videos</link>', margin: 0, align: :left, line_height: 1.2, size: @theme.base_font_size_small, normalize: false
    end

    grid([16.5,0],[16.5,1]).bounding_box do
      layout_prose %(NFJS, the Magazine Issue #{doc.attr 'edition'} Copyright &#169; 2014 by No Fluff, Just Stuff (TM).
All Rights Reserved. Redistribution Is Strictly Prohibited.), align: :center, color: '666665', size: @theme.base_font_size_small, margin: 0, normalize: false, line_height: 1.3
    end
  end

  def page_number_pattern
    { left: '%s | NoFluffJustStuff.com', right: 'No Fluff Just Stuff, the Magazine | %s' }
  end
end
end
end
