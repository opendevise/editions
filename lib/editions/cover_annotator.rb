require 'RMagick'
require 'safe_yaml'
require 'asciidoctor'

module Editions
# Loads the image file front-cover-no-titles.jpg (1600x2056), annotates the
# image with the article titles and writes the image files front-cover.jpg
# (1600x2056), front-cover-small-thumb.jpg (125x141) and
# front-cover-large-thumb.jpg (400x514). The font settings for the article
# titles are read from the config file front-cover.yml in the same folder as
# the front-cover-no-titles.jpg image.
class CoverAnnotator

  include Magick
  
  DEFAULT_CONFIG = {
    'alignment'        => 'southwest',
    'font-size'        => 48,
    'font-color'       => 'FFFFFF',
    'shadow-color'     => '000000',
    'shadow-thickness' => 5,
    'shadow-blur'      => 5,
    'side-margin'      => 100,
    'bottom-margin'    => 50,
    'title-spacing'    => 100
  }

  PATH_TO_ROOT = '.'
  PATH_TO_JACKET = File.join 'images', 'jacket'
  EDITION_CONFIG_FILE = File.join PATH_TO_ROOT, 'config.yml'
  COVER_CONFIG_FILE = File.join PATH_TO_JACKET, 'front-cover.yml'
  COVER_NO_TITLES_FILE = File.join PATH_TO_JACKET, 'front-cover-no-titles.jpg'
  COVER_FILE = File.join PATH_TO_JACKET, 'front-cover.jpg'
  COVER_SMALL_THUMB_FILE = File.join PATH_TO_JACKET, 'front-cover-small-thumb.jpg'
  COVER_LARGE_THUMB_FILE = File.join PATH_TO_JACKET, 'front-cover-large-thumb.jpg'

  def initialize
    load_config
    load_titles
  end

  def load_config
    config = DEFAULT_CONFIG.merge((File.exist? COVER_CONFIG_FILE) ? (YAML.load_file COVER_CONFIG_FILE, safe: :safe) : {})
  
    @img_width = 1600
    @img_height = 2056
    @font_size = config['font-size']
    #@font_family = 'M+-1p-medium'
    asciidoctor_epub3_datadir = ::Gem.datadir 'asciidoctor-epub3'
    unless (::File.basename asciidoctor_epub3_datadir) == 'data'
      asciidoctor_epub3_datadir = ::File.dirname asciidoctor_epub3_datadir
    end
    @font_family = ::File.join asciidoctor_epub3_datadir, 'fonts', 'mplus1p-regular-latin-ext.ttf'
    unless ::File.exist? @font_family
      warn %(Could not find font file for adding article titles to the cover image: #{@font_family})
      @font_family = 'Helvetica'
    end
    @font_color = %(##{config['font-color'].upcase})
    @shadow_color = (config['shadow-color'] == 'transparent' ? 'transparent' : %(##{config['shadow-color'].upcase}))
    @shadow_thickness = config['shadow-thickness']
    @shadow_blur = config['shadow-blur']
    @side_padding = config['side-margin']
    @bottom_padding = config['bottom-margin']
    @title_spacing = config['title-spacing']
  end
  
  def load_titles
    @titles = (YAML.load_file EDITION_CONFIG_FILE, safe: :safe)['articles']
      .map {|a|
        File.join PATH_TO_ROOT, a['local_dir'], 'article.adoc'
      }
      .map {|f|
        title = (Asciidoctor.load_file f).doctitle sanitize: true
        if title.size > 40 && (title.include? ': ')
          title = title.sub ': ', %(:\n)
        end
        title
      }
      .reverse
  end

  def self.annotated?
    File.exist? COVER_FILE
  end

  def self.needs_annotating?
    !(File.exist? COVER_FILE) && (File.exist? COVER_NO_TITLES_FILE)
  end
  
  # Writes the titles in a shadow layer, then overlays the titles in the font
  # color, then overlays the text on the artwork with no titles, then flattens
  # and saves the image.
  def annotate
    canvas = Magick::ImageList.new

    text = Magick::Draw.new
    text.font = @font_family
    text.pointsize = @font_size
    text.gravity = Magick::SouthWestGravity
    text.kerning = -1.5
    text.interline_spacing = -(@font_size / 3).floor

    unless @shadow_color == 'transparent'
      active_layer = create_layer
      y_offset = @bottom_padding
      @titles.each do |txt|
        shadow_color = @shadow_color
        shadow_thickness = @shadow_thickness
        text.annotate active_layer, 0, 0, @side_padding, y_offset, txt do |t|
          t.fill = t.stroke = shadow_color
          t.stroke_width = shadow_thickness
        end
        if txt.include? "\n"
          y_offset += @font_size
        end
        y_offset += @title_spacing
      end
      
      canvas << (active_layer.blur_channel 0, @shadow_blur, AllChannels)
    end

    active_layer = create_layer
    
    y_offset = @bottom_padding
    @titles.each do |txt|
      font_color = @font_color
      text.annotate active_layer, 0, 0, @side_padding, y_offset, txt do |t|
        t.fill = font_color
        t.stroke = 'none'
      end
      if txt.include? "\n"
        y_offset += @font_size
      end
      y_offset += @title_spacing
    end

    canvas << active_layer

    canvas.unshift (Image.read COVER_NO_TITLES_FILE)[0]

    canvas = canvas.flatten_images

    canvas.write COVER_FILE
    
    canvas_thumb = canvas.scale 125, 161
    canvas_thumb.write COVER_SMALL_THUMB_FILE
    
    canvas_thumb = canvas.scale 400, 514
    canvas_thumb.write COVER_LARGE_THUMB_FILE
  end

  def create_layer
    Magick::Image.new @img_width, @img_height do |i|
      i.background_color = 'transparent'
    end
  end
end
end
