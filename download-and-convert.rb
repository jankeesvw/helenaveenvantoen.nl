#!/usr/bin/env ruby

require 'net/http'
require 'uri'
require 'fileutils'
require 'nokogiri'
require 'open3'
require 'cgi'

class DownloadAndConvert
  LINKS_FILE = "links.txt"
  BACKUP_DIR = "website_backup"
  MARKDOWN_DIR = "export"

  def initialize
    @converted = 0
    @failed = 0
  end

  def run
    puts "==========================================="
    puts "Download & Convert to Markdown"
    puts "==========================================="

    check_prerequisites
    prepare_directories
    process_all_links
    create_index_file
    cleanup_html_backup
    show_statistics

    puts "\n==========================================="
    puts "✅ Download and conversion completed!"
    puts "==========================================="
  end

  private

  def check_prerequisites
    unless File.exist?(LINKS_FILE)
      puts "❌ Error: #{LINKS_FILE} niet gevonden!"
      puts "Run eerst ./crawl-website.rb om links te verzamelen."
      exit 1
    end
  end

  def prepare_directories
    puts "📁 Creating directories..."
    FileUtils.rm_rf([BACKUP_DIR, MARKDOWN_DIR])
    FileUtils.mkdir_p([BACKUP_DIR, MARKDOWN_DIR])
  end

  def process_all_links
    puts "\n📥 Downloading and converting pages..."
    puts ""

    links = File.readlines(LINKS_FILE).map(&:strip).reject(&:empty?)
    total = links.size

    links.each_with_index do |url, index|
      filename = determine_filename(url)
      html_file = File.join(BACKUP_DIR, "#{filename}.html")
      markdown_file = File.join(MARKDOWN_DIR, "#{filename}.md")

      puts "[#{index + 1}/#{total}] #{filename}"

      if download_page(url, html_file)
        if convert_to_markdown(html_file, markdown_file, url)
          puts "  ✅ Converted to Markdown"
          @converted += 1
        else
          puts "  ⚠️  Conversion failed"
          @failed += 1
        end
      else
        puts "  ❌ Download failed"
        @failed += 1
      end

      # Add delay between ALL requests to avoid rate limiting
      if index < total - 1
        sleep(1.5 + rand * 0.5)  # Sleep 1.5-2 seconds between each request
      end
    end
  end

  def determine_filename(url)
    uri = URI.parse(url)

    if uri.path == '/' || uri.path.empty?
      'index'
    else
      # Extract filename from path
      filename = File.basename(uri.path, '.*')
      filename = "page_#{Digest::MD5.hexdigest(url)[0..7]}" if filename.empty?
      filename
    end
  end

  def download_page(url, output_file, retries = 3)
    attempt = 0

    while attempt < retries
      begin
        uri = URI.parse(url)

        # Add timeout and follow redirects
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')
        http.open_timeout = 10
        http.read_timeout = 30

        # Construct proper request path with query string if present
        request_path = uri.path.empty? ? '/' : uri.path
        request_path += "?#{uri.query}" if uri.query

        request = Net::HTTP::Get.new(request_path)
        request['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
        request['Accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
        request['Accept-Language'] = 'nl,en;q=0.9'
        request['Cache-Control'] = 'no-cache'
        response = http.request(request)

        case response
        when Net::HTTPSuccess
          File.write(output_file, response.body)
          return true
        when Net::HTTPRedirection
          # Follow redirect
          redirect_url = response['location']
          if redirect_url.start_with?('/')
            redirect_url = "#{uri.scheme}://#{uri.host}#{redirect_url}"
          end
          puts "  → Redirect to: #{redirect_url}"
          url = redirect_url
          uri = URI.parse(url)
          attempt += 1
        else
          puts "  HTTP #{response.code}: #{response.message}"
          attempt += 1
          # Longer sleep for rate limit errors
          if response.code == '429'
            sleep_time = 2 + attempt
            puts "  ⏳ Rate limited - waiting #{sleep_time}s before retry..."
            sleep(sleep_time)
          else
            sleep(1) if attempt < retries
          end
        end
      rescue => e
        attempt += 1
        puts "  Attempt #{attempt}/#{retries} failed: #{e.message}"
        sleep(2) if attempt < retries
      end
    end

    false
  end

  def convert_to_markdown(html_file, markdown_file, url)
    filename = File.basename(markdown_file, '.md')

    File.open(markdown_file, 'w') do |f|
      f.puts "# #{filename}"
      f.puts ""
      f.puts "> Bron: helenaveenvantoen.nl"
      f.puts ""

      # Convert HTML to markdown
      content = convert_with_nokogiri(html_file)

      f.puts content
    end
    true
  rescue => e
    puts "  Error converting: #{e.message}"
    false
  end


  def convert_with_nokogiri(html_file)
    html = File.read(html_file)
    doc = Nokogiri::HTML(html)

    # Remove unwanted elements
    doc.css('script, style, nav, header, footer, .nav, .navigation, button').remove

    # Extract text content
    content = []

    # Check for audio elements first (debugging)
    audio_elements = doc.css('audio')
    puts "  🔍 Found #{audio_elements.length} audio elements" if audio_elements.length > 0

    # Also check for Squarespace audio players (often in divs with data attributes)
    data_audio_elements = doc.css('[data-url*=".mp3"], [data-url*=".wav"], [data-url*=".m4a"]')
    puts "  🔍 Found #{data_audio_elements.length} data-url audio elements" if data_audio_elements.length > 0

    data_audio_elements.each do |element|
      audio_url = element['data-url']
      if audio_url && !audio_url.empty?
        puts "  🎵 Found audio URL: #{audio_url}"

        # Make absolute URL if needed
        if audio_url.start_with?('//')
          audio_url = "https:#{audio_url}"
        elsif audio_url.start_with?('/')
          audio_url = "https://www.helenaveenvantoen.nl#{audio_url}"
        end

        # Create HTML audio element
        audio_html = "<audio controls>\n  <source src=\"#{audio_url}\" type=\"audio/mpeg\">\n  Your browser does not support the audio element.\n</audio>"
        content << audio_html
      end
    end

    # Process all relevant elements including images and audio
    doc.css('h1, h2, h3, h4, h5, h6, p, img, audio').each do |element|
      case element.name
      when 'img'
        # Extract image source and alt text
        src = element['src'] || element['data-src']
        alt = element['alt'] || 'Afbeelding'

        if src && !src.empty?
          # Make absolute URL if needed
          if src.start_with?('//')
            src = "https:#{src}"
          elsif src.start_with?('/')
            src = "https://www.helenaveenvantoen.nl#{src}"
          end

          content << "![#{alt}](#{src})"
        end
      when 'audio'
        # Embed the full HTML audio element in markdown
        audio_html = element.to_html

        # Make any relative URLs absolute
        audio_html = audio_html.gsub(/src="\/\//, 'src="https://')
        audio_html = audio_html.gsub(/src="\/([^\/])/, 'src="https://www.helenaveenvantoen.nl/\1')

        content << audio_html
      when 'h1'
        text = clean_html_entities(element.text.strip)
        content << "# #{text}" unless text.empty?
      when 'h2'
        text = clean_html_entities(element.text.strip)
        content << "## #{text}" unless text.empty?
      when 'h3'
        text = clean_html_entities(element.text.strip)
        content << "### #{text}" unless text.empty?
      when 'h4'
        text = clean_html_entities(element.text.strip)
        content << "#### #{text}" unless text.empty?
      when 'h5'
        text = clean_html_entities(element.text.strip)
        content << "##### #{text}" unless text.empty?
      when 'h6'
        text = clean_html_entities(element.text.strip)
        content << "###### #{text}" unless text.empty?
      else
        text = clean_html_entities(element.text.strip)
        # Filter out navigation items like lynx did
        unless text.empty? || text.match?(/^(Home|Inhoudsopgave|Oorlog|Kerk en school|Bedrijven|Vervening|Verhalen|Multimedia|De Maatschappij|Het Helenaveen van toen|Zoeken|BUTTON)$/i)
          content << text
        end
      end
    end

    content.reject(&:empty?).join("\n\n")
  end

  def clean_html_entities(text)
    # First use CGI to unescape standard HTML entities
    text = CGI.unescapeHTML(text)

    # Then handle specific cases that might be missed
    text
      .gsub(/&nbsp;?/i, ' ')        # Non-breaking space (with or without semicolon)
      .gsub(/\u00A0/, ' ')           # Unicode non-breaking space
      .gsub(/&#160;?/, ' ')          # Numeric entity for nbsp
      .gsub(/&amp;?/i, '&')          # Ampersand
      .gsub(/&lt;?/i, '<')           # Less than
      .gsub(/&gt;?/i, '>')           # Greater than
      .gsub(/&quot;?/i, '"')         # Quote
      .gsub(/&#39;?/, "'")           # Apostrophe (numeric)
      .gsub(/&apos;?/i, "'")         # Apostrophe (named)
      .gsub(/\[\d+\]/, '')           # Remove link references [1], [2], etc.
      .gsub(/\s+/, ' ')              # Normalize whitespace
      .strip                         # Remove leading/trailing whitespace
  end


  def create_index_file
    puts "\n📝 Creating index file..."

    index_file = File.join(MARKDOWN_DIR, "INDEX.md")

    File.open(index_file, 'w') do |f|
      f.puts "# Helenaveen van Toen - Markdown Versie"
      f.puts ""
      f.puts "Geconverteerd op: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
      f.puts "Bron: https://www.helenaveenvantoen.nl"
      f.puts ""
      f.puts "## Statistieken"
      f.puts ""
      f.puts "- Totaal pagina's: #{@converted}"
      f.puts "- Conversie mislukt: #{@failed}"
      f.puts ""
      f.puts "## Beschikbare Pagina's"
      f.puts ""

      Dir.glob(File.join(MARKDOWN_DIR, "*.md"))
        .reject { |f| File.basename(f) == "INDEX.md" }
        .sort
        .each do |md_file|
          filename = File.basename(md_file, '.md')
          # Read first line for title
          title = File.readlines(md_file).first.to_s.gsub(/^# /, '').strip
          title = filename if title.empty?
          f.puts "- [#{title}](#{filename}.md)"
        end
    end

    puts "✅ Index created: #{index_file}"
  end

  def cleanup_html_backup
    puts "\n🧹 Cleaning up temporary HTML files..."

    if Dir.exist?(BACKUP_DIR)
      FileUtils.rm_rf(BACKUP_DIR)
      puts "  ✅ Removed #{BACKUP_DIR}/ directory"
    end
  end

  def show_statistics
    total_size = `du -sh "#{MARKDOWN_DIR}" 2>/dev/null | cut -f1`.strip

    puts "\n📊 Conversion Statistics:"
    puts "---------------------"
    puts "Pages converted: #{@converted}"
    puts "Pages failed: #{@failed}"
    puts ""
    puts "📁 Output directory: #{MARKDOWN_DIR}/"
    puts "📄 Total size: #{total_size}"
  end
end

# Check if required gems are installed
begin
  require 'nokogiri'
rescue LoadError
  puts "❌ Error: nokogiri gem is not installed"
  puts "Please run: gem install nokogiri"
  exit 1
end

# Run the converter
if __FILE__ == $0
  converter = DownloadAndConvert.new
  converter.run
end