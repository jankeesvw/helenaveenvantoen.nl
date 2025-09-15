#!/usr/bin/env ruby

require 'net/http'
require 'uri'
require 'fileutils'
require 'digest'

class MediaDownloader
  MARKDOWN_DIR = "export"
  IMAGES_DIR = "export/images"

  def initialize
    @downloaded = 0
    @failed = 0
    @updated_files = 0
    @media_map = {}
  end

  def run
    puts "==========================================="
    puts "Download Images and Audio from Markdown"
    puts "==========================================="

    check_prerequisites
    prepare_directories
    process_markdown_files
    download_audio_files
    show_statistics

    puts "\n==========================================="
    puts "✅ Media download completed!"
    puts "==========================================="
  end

  private

  def check_prerequisites
    unless Dir.exist?(MARKDOWN_DIR)
      puts "❌ Error: #{MARKDOWN_DIR} directory niet gevonden!"
      puts "Run eerst ./download-and-convert.rb om markdown files te maken."
      exit 1
    end

    markdown_files = Dir.glob(File.join(MARKDOWN_DIR, "*.md"))
    if markdown_files.empty?
      puts "❌ Error: Geen markdown files gevonden in #{MARKDOWN_DIR}/"
      exit 1
    end
  end

  def prepare_directories
    puts "📁 Creating images directory..."
    FileUtils.mkdir_p(IMAGES_DIR)
  end

  def process_markdown_files
    puts "\n🔍 Scanning markdown files for images..."

    markdown_files = Dir.glob(File.join(MARKDOWN_DIR, "*.md"))
    total_files = markdown_files.size

    markdown_files.each_with_index do |md_file, index|
      filename = File.basename(md_file)
      puts "\n[#{index + 1}/#{total_files}] Processing: #{filename}"

      process_single_file(md_file)
    end
  end

  def download_audio_files
    puts "\n🎵 Downloading audio files from geluid page..."

    audio_urls = [
      "https://static1.squarespace.com/static/5d43f94f93ac690001e770a7/t/6094cdc9fd2d517916d4a9e9/1620364870074/Jules_de_Corte.mp3/original/Jules_de_Corte.mp3",
      "https://static1.squarespace.com/static/5d43f94f93ac690001e770a7/t/6094cf44291fb36baa8ec2e0/1620365168754/lied_Helenaveen.mp3/original/lied_Helenaveen.mp3"
    ]

    audio_urls.each do |url|
      download_audio(url, "geluid")
    end
  end

  def process_single_file(md_file)
    content = File.read(md_file)
    modified = false

    # Get the base filename without extension for creating subdirectory
    base_filename = File.basename(md_file, '.md')

    # Find all media references in markdown
    # Matches: ![alt text](url), <img src="url">, and <audio src="url">
    media_patterns = [
      /!\[([^\]]*)\]\(([^)]+)\)/,  # Markdown image syntax
      /<img[^>]*src=["']([^"']+)["'][^>]*>/i,  # HTML img tags
      /<audio[^>]*src=["']([^"']+)["'][^>]*>/i,  # HTML audio tags
      /<source[^>]*src=["']([^"']+)["'][^>]*>/i  # HTML source tags within audio
    ]

    new_content = content.dup

    media_patterns.each_with_index do |pattern, pattern_index|
      new_content.gsub!(pattern) do |match|
        case pattern_index
        when 0
          # Markdown image syntax
          alt_text = $1
          media_url = $2
          media_type = 'image'
        when 1
          # HTML img tag
          media_url = $1
          media_type = 'image'
        when 2, 3
          # HTML audio tag or source tag
          media_url = $1
          media_type = 'audio'
        end

        if media_url.start_with?('http://', 'https://', '//')
          local_path = download_media(media_url, base_filename, media_type)
          if local_path
            modified = true
            if pattern_index == 0
              # Markdown syntax
              "![#{alt_text}](#{local_path})"
            else
              # HTML tags - replace the URL in the original match
              match.gsub(media_url, local_path)
            end
          else
            match  # Keep original if download failed
          end
        else
          match  # Already local or relative path
        end
      end
    end

    # Save modified content if changes were made
    if modified
      File.write(md_file, new_content)
      puts "  ✅ Updated markdown with local image paths"
      @updated_files += 1
    else
      puts "  ℹ️  No remote images found or all downloads failed"
    end
  end

  def download_media(url, page_name, media_type = 'image')
    # Check if we already downloaded this media
    return @media_map[url] if @media_map.key?(url)

    # Normalize URL
    url = "https:#{url}" if url.start_with?('//')

    begin
      uri = URI.parse(url)

      # Create subdirectory for this page's images
      page_images_dir = File.join(IMAGES_DIR, page_name)
      FileUtils.mkdir_p(page_images_dir)

      # Generate filename
      original_filename = File.basename(uri.path)
      if original_filename.empty? || !original_filename.include?('.')
        # Generate filename from URL hash if no proper filename
        ext = guess_extension(url)
        original_filename = "image_#{Digest::MD5.hexdigest(url)[0..7]}#{ext}"
      end

      # Clean up filename (remove special characters that might cause issues)
      clean_filename = original_filename.gsub(/[+%]/, '_')

      # Ensure unique filename within page subdirectory
      local_filename = clean_filename
      counter = 1
      while File.exist?(File.join(page_images_dir, local_filename))
        name, ext = clean_filename.split('.', 2)
        local_filename = "#{name}_#{counter}.#{ext}"
        counter += 1
      end

      local_path = File.join(page_images_dir, local_filename)

      # Download the media file
      emoji = media_type == 'audio' ? '🎵' : '📥'
      print "  #{emoji} Downloading: #{local_filename}..."

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = 10
      http.read_timeout = 30

      request = Net::HTTP::Get.new(uri.path.empty? ? '/' : uri.path)
      request['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'

      response = http.request(request)

      if response.code == '200'
        File.open(local_path, 'wb') do |file|
          file.write(response.body)
        end

        # Store relative path from markdown directory
        relative_path = "images/#{page_name}/#{local_filename}"
        @media_map[url] = relative_path
        @downloaded += 1

        puts " ✅"
        return relative_path
      else
        puts " ❌ (HTTP #{response.code})"
        @failed += 1
        return nil
      end

    rescue => e
      puts " ❌ (#{e.message})"
      @failed += 1
      return nil
    end
  end

  def download_audio(url, page_name)
    # Check if we already downloaded this audio
    return @media_map[url] if @media_map.key?(url)

    begin
      uri = URI.parse(url)

      # Create subdirectory for this page's audio
      page_images_dir = File.join(IMAGES_DIR, page_name)
      FileUtils.mkdir_p(page_images_dir)

      # Generate filename from URL
      original_filename = File.basename(uri.path)
      if original_filename.empty? || !original_filename.include?('.')
        # Generate filename from URL hash if no proper filename
        original_filename = "audio_#{Digest::MD5.hexdigest(url)[0..7]}.mp3"
      end

      # Clean up filename (remove special characters that might cause issues)
      clean_filename = original_filename.gsub(/[+%]/, '_')

      # Ensure unique filename within page subdirectory
      local_filename = clean_filename
      counter = 1
      while File.exist?(File.join(page_images_dir, local_filename))
        name, ext = clean_filename.split('.', 2)
        local_filename = "#{name}_#{counter}.#{ext}"
        counter += 1
      end

      local_path = File.join(page_images_dir, local_filename)

      # Download the audio
      print "  🎵 Downloading: #{local_filename}..."

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = 10
      http.read_timeout = 60  # Longer timeout for audio files

      request = Net::HTTP::Get.new(uri.path.empty? ? '/' : uri.path)
      request['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'

      response = http.request(request)

      if response.code == '200'
        File.open(local_path, 'wb') do |file|
          file.write(response.body)
        end

        # Store relative path from markdown directory
        relative_path = "images/#{page_name}/#{local_filename}"
        @media_map[url] = relative_path
        @downloaded += 1

        puts " ✅"
        return relative_path
      else
        puts " ❌ (HTTP #{response.code})"
        @failed += 1
        return nil
      end

    rescue => e
      puts " ❌ (#{e.message})"
      @failed += 1
      return nil
    end
  end

  def guess_extension(url)
    # Try to guess extension from URL
    return '.jpg' if url.include?('.jpg') || url.include?('.jpeg')
    return '.png' if url.include?('.png')
    return '.gif' if url.include?('.gif')
    return '.svg' if url.include?('.svg')
    return '.webp' if url.include?('.webp')
    return '.mp3' if url.include?('.mp3')
    return '.mp4' if url.include?('.mp4')
    return '.wav' if url.include?('.wav')
    '.jpg'  # Default to jpg
  end

  def show_statistics
    total_files = Dir.glob(File.join(IMAGES_DIR, "*")).size
    total_size = `du -sh "#{IMAGES_DIR}" 2>/dev/null | cut -f1`.strip

    puts "\n📊 Download Statistics:"
    puts "---------------------"
    puts "Media files downloaded: #{@downloaded}"
    puts "Downloads failed: #{@failed}"
    puts "Markdown files updated: #{@updated_files}"
    puts ""
    puts "📁 Media directory: #{IMAGES_DIR}/"
    puts "📄 Total files: #{total_files}"
    puts "💾 Total size: #{total_size}"
  end
end

# Run the downloader
if __FILE__ == $0
  downloader = MediaDownloader.new
  downloader.run
end