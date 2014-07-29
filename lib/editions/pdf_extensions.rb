module Asciidoctor
class PdfRenderer
  def start_new_chapter section
    if section.index == 3
      import_page 'images/inserts/contegix-ad.pdf'
    end
    start_new_page
  end

  def chapter_title section, title_string
    primary_title, subtitle = title_string.split(': ')
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
        move_down @theme.vertical_rhythm / 2
        indent 0, @theme.horizontal_rhythm do
          headshot_size = 25
          author_name = section.document.attr 'author'
          if box_height && (username = section.document.attr 'username')
            float do
              name_width = width_of author_name
              left = bounds.width - name_width - headshot_size - 5
              # QUESTION look for avatar.jpg inside article directory?
              image %(images/avatars/#{username}.jpg), at: [left, cursor + headshot_size], width: headshot_size
            end
          end
          prose author_name, align: :right, line_height: 1, margin_top: -(headshot_size - 4)
        end
      end
      #move_down @theme.vertical_rhythm
      indent @theme.horizontal_rhythm, @theme.horizontal_rhythm do
        if subtitle
          theme_font :chapter_title do
            heading primary_title.upcase, margin_bottom: 0
          end
        else
          move_down @theme.vertical_rhythm * 2
        end
        indent @theme.horizontal_rhythm do
          move_up @theme.vertical_rhythm / 3
          theme_font :chapter_subtitle do
            subtitle_upper = (subtitle || primary_title).upcase
                .gsub(/(<\/?[A-Z]+?>|&[A-Z]+;)/) { $1.downcase }
                .sub(/<em>(.*)<\/em>/, '<color rgb="ffc14f">\1</color>')
            heading subtitle_upper, margin_top: 3, line_height: 1.3
          end
        end
        move_down @theme.vertical_rhythm / 2
        stroke_horizontal_rule 'ffffff'
      end
      move_down @theme.vertical_rhythm / 2
    end
    move_down @theme.chapter_title_margin_bottom
  end

  def add_toc doc, num_levels = 2, toc_page_num = 2
    go_to_page toc_page_num - 1
    start_new_page
    theme_font :heading, level: 2 do
      prose doc.attr('toc-title').upcase, margin_bottom: -8
    end
    theme_font :chapter_title do
      # FIXME align me correctly (align to right of the toc title)
      indent @theme.horizontal_rhythm * 2.6 do
        revdate = ::DateTime.parse(doc.attr 'revdate')
        prose %(#{(revdate.strftime '%B').upcase} #{revdate.strftime '%Y'})
      end
    end
    
    # FIXME force font color to base_font_color for links
    prose 'NFJS 2014 Tour Series Schedule', margin: 0, size: @theme.base_font_size_large, anchor: 'tour-schedule', link_color: @font_color
    prose 'From the Publisher', margin: 0, size: @theme.base_font_size_large, anchor: doc.sections[0].id, link_color: @font_color
    move_down @theme.vertical_rhythm * 2

    theme_font :heading, level: 2 do
      label_text = 'FEATURES'
      label_height = height_of_typeset_text label_text
      label_width = width_of label_text
      bounding_box [-left_margin, cursor], width: label_width + left_margin + @theme.horizontal_rhythm, height: label_height do
        fill_bounds 'ffc14f'
        indent left_margin do
          heading 'FEATURES', margin: 0
        end
      end
    end
    move_down @theme.vertical_rhythm
    authors = (doc.attr 'authors').split ', '
    doc.sections[1..-1].each_with_index do |section, i|
      primary_title, subtitle = section.title.split(': ')
      theme_font :chapter_title do
        prose primary_title.upcase, margin_top: 0, margin_bottom: -5, line_height: 1.4, anchor: section.id, link_color: @font_color
      end
      prose sanitize(subtitle).upcase.gsub('&', '&amp;'), margin: 0, line_height: 1.4, size: @theme.base_font_size_large, anchor: section.id, link_color: @font_color if subtitle
      indent @theme.horizontal_rhythm / 2 do
        if (description = ((section.attributes[:attribute_entries] || []) + (section.blocks[0].attributes[:attribute_entries] || [])).find {|entry| entry.name == 'description' })
          desc_fmt = ::Asciidoctor.convert description.value, doctype: :inline
          prose desc_fmt, line_height: 1.6, margin: 0, align: :left, size: @theme.base_font_size_small
        end
        prose %(By #{authors[i]}), color: '666665', line_height: 1.5, margin_top: 2, margin_bottom: 0, style: :italic
        indent 0, 3 do
          prose %(Page #{(section.attr 'page_start') - 1}), line_height: 1.5, margin: 0, style: :bold, align: :right, anchor: section.id, link_color: @font_color
        end
      end
      move_down @theme.vertical_rhythm / 2
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
      svg IO.read('images/jacket/nfjs-magazine.svg'), at: [((bounds.width / 2) - (logo_width / 2)).floor, cursor], width: logo_width
    end

    grid([4,0],[4,0]).bounding_box do
      prose 'Publisher and Editor in Chief', align: :right, margin: 0, style: :bold, size: @theme.base_font_size_large
    end

    grid([4,1],[4,1]).bounding_box do
      prose 'Jay Zimmerman - NFJS One', margin_bottom: -4, size: @theme.base_font_size_large
      prose 'jzimmerman@nofluffjuststuff.com', color: '4F4F4E', margin: 0
    end

    grid([5,0],[5,0]).bounding_box do
      prose 'Technical Editor', align: :right, margin: 0, style: :bold, size: @theme.base_font_size_large
    end

    grid([5,1],[5,1]).bounding_box do
      prose 'Matt Stine', margin_bottom: -4, size: @theme.base_font_size_large
      prose 'matt@nofluffjuststuff.com', color: '4F4F4E', margin: 0
    end

    grid([6,0],[6,0]).bounding_box do
      prose 'Production and UX', align: :right, margin: 0, size: @theme.base_font_size_large
    end

    grid([6,1],[7,1]).bounding_box do
      prose 'Dan Allen - OpenDevise Inc.', margin_bottom: -4, size: @theme.base_font_size_large
      prose '@mojavelinux', color: '4F4F4E', margin: 0
      prose 'Sarah White - OpenDevise Inc.', margin_bottom: -4, size: @theme.base_font_size_large
      prose '@carbonfray', color: '4F4F4E', margin: 0
    end

    grid([8,0],[8,0]).bounding_box do
      prose 'Cover Artwork', align: :right, margin: 0, size: @theme.base_font_size_large
    end

    grid([8,1],[8,1]).bounding_box do
      prose 'Alicia Weller', margin: 0, size: @theme.base_font_size_large
    end

    grid([9,0],[9,0]).bounding_box do
      prose %(Issue #{doc.attr 'edition'} Contributors), align: :right, margin: 0, size: @theme.base_font_size_large
    end

    grid([9,1],[11,1]).bounding_box do
      prose doc.attr('authors').gsub(', ', "\n"), normalize: false, size: @theme.base_font_size_large, line_height: 1.2, margin_top: 2
    end

    grid([11.75,0],[11.75,1]).bounding_box do
      fill_bounds '666665'
      prose 'HOW TO REACH US', align: :center, color: 'FFFFFF', size: 16, margin: 0, valign: :center, line_height: 1
    end

    grid([13,0],[14,0]).bounding_box do
      prose 'Advertising', style: :bold, align: :right, margin: 0
      prose 'For information about advertising in NFJS, the Magazine, email Jay Zimmerman at jzimmerman@nofluffjuststuff.com', margin: 0, align: :right, line_height: 1.2, size: @theme.base_font_size_small
    end

    grid([13,1],[14,1]).bounding_box do
      prose 'Events', style: :bold, align: :left, margin: 0
      prose 'For the latest news about NFJS events, visit <link anchor="http://nofluffjuststuff.com">nofluffjuststuff.com</link>', margin: 0, align: :left, line_height: 1.2, size: @theme.base_font_size_small
    end

    grid([14.5,0],[15.5,0]).bounding_box do
      prose 'Office of the Publisher', style: :bold, align: :right, margin: 0
      prose '5023 W. 120th Avenue, Suite #289
Broomfield, CO 80020
(303) 469-0486', margin: 0, align: :right, line_height: 1.2, size: @theme.base_font_size_small, normalize: false
    end

    grid([14.5,1],[15.5,1]).bounding_box do
      prose 'Social', style: :bold, align: :left, margin: 0
      prose 'Follow <link anchor="https://twitter.com/nofluff">@nofluff</link> on Twitter
Join <link anchor="http://www.linkedin.com/groups/No-Fluff-Just-Stuff-1653697/about">NFJS</link> on LinkedIn
Watch <link anchor="http://www.nofluffjuststuff.com/m/network/index">NFJS videos</link>', margin: 0, align: :left, line_height: 1.2, size: @theme.base_font_size_small, normalize: false
    end

    grid([16.5,0],[16.5,1]).bounding_box do
      prose %(NFJS, the Magazine Issue #{doc.attr 'edition'} Copyright &#169; 2014 by No Fluff, Just Stuff (TM).
All Rights Reserved. Redistribution Is Strictly Prohibited.), align: :center, color: '666665', size: @theme.base_font_size_small, margin: 0, normalize: false, line_height: 1.3
    end
  end

  def page_number_pattern
    { left: '%s | NoFluffJustStuff.com', right: 'No Fluff Just Stuff, the Magazine | %s' }
  end
end
end
