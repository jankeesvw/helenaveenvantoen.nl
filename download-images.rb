#!/usr/bin/env ruby

require 'net/http'
require 'uri'
require 'fileutils'
require 'digest'

class ImageDownloader
  MARKDOWN_DIR = "export"
  IMAGES_DIR = "export/images"

  def initialize
    @downloaded = 0
    @failed = 0
    @updated_files = 0
    @image_map = {}
  end

  def run
    puts "==========================================="
    puts "Download Images from Markdown"
    puts "==========================================="

    check_prerequisites
    prepare_directories
    process_markdown_files
    show_statistics

    puts "\n==========================================="
    puts "✅ Image download completed!"
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

  def process_single_file(md_file)
    content = File.read(md_file)
    modified = false

    # Get the base filename without extension for creating subdirectory
    base_filename = File.basename(md_file, '.md')

    # Find all image references in markdown
    # Matches: ![alt text](url) and <img src="url">
    image_patterns = [
      /!\[([^\]]*)\]\(([^)]+)\)/,  # Markdown image syntax
      /<img[^>]*src=["']([^"']+)["'][^>]*>/i  # HTML img tags
    ]

    new_content = content.dup

    image_patterns.each do |pattern|
      new_content.gsub!(pattern) do |match|
        if pattern == image_patterns[0]
          # Markdown syntax
          alt_text = $1
          image_url = $2

          if image_url.start_with?('http://', 'https://', '//')
            local_path = download_image(image_url, base_filename)
            if local_path
              modified = true
              "![#{alt_text}](#{local_path})"
            else
              match  # Keep original if download failed
            end
          else
            match  # Already local or relative path
          end
        else
          # HTML img tag
          image_url = $1

          if image_url.start_with?('http://', 'https://', '//')
            local_path = download_image(image_url, base_filename)
            if local_path
              modified = true
              match.gsub(image_url, local_path)
            else
              match  # Keep original if download failed
            end
          else
            match  # Already local or relative path
          end
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

  def download_image(url, page_name)
    # Check if we already downloaded this image
    return @image_map[url] if @image_map.key?(url)

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

      # Download the image
      print "  📥 Downloading: #{local_filename}..."

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
        @image_map[url] = relative_path
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
    '.jpg'  # Default to jpg
  end

  def show_statistics
    total_images = Dir.glob(File.join(IMAGES_DIR, "*")).size
    total_size = `du -sh "#{IMAGES_DIR}" 2>/dev/null | cut -f1`.strip

    puts "\n📊 Download Statistics:"
    puts "---------------------"
    puts "Images downloaded: #{@downloaded}"
    puts "Images failed: #{@failed}"
    puts "Markdown files updated: #{@updated_files}"
    puts ""
    puts "📁 Images directory: #{IMAGES_DIR}/"
    puts "📄 Total images: #{total_images}"
    puts "💾 Total size: #{total_size}"
  end
end

# Run the downloader
if __FILE__ == $0
  downloader = ImageDownloader.new
  downloader.run
end