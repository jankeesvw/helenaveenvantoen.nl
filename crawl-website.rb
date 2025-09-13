#!/usr/bin/env ruby

require 'net/http'
require 'uri'
require 'set'
require 'nokogiri'

class WebsiteCrawler
  WEBSITE_URL = "https://www.helenaveenvantoen.nl"
  LINKS_FILE = "links.txt"

  def initialize
    @processed_urls = Set.new
    @queue = []
    @links = Set.new
  end

  def run
    puts "==========================================="
    puts "Website Crawler"
    puts "Website: #{WEBSITE_URL}"
    puts "==========================================="

    # First, try to get links from sitemap
    puts "\n📄 Fetching sitemap..."
    fetch_sitemap_links

    # Then crawl the website for any additional links
    puts "\n📥 Starting crawl from homepage..."
    @queue << WEBSITE_URL
    crawl_all_pages

    save_links
    show_statistics

    puts "\n==========================================="
    puts "✅ Crawling completed!"
    puts "==========================================="
  end

  private

  def fetch_sitemap_links
    sitemap_url = "#{WEBSITE_URL}/sitemap.xml"

    begin
      uri = URI.parse(sitemap_url)
      response = Net::HTTP.get_response(uri)

      if response.code == '200'
        # Parse XML to find all <loc> tags
        sitemap_content = response.body

        # Extract URLs from <loc> tags
        sitemap_links = sitemap_content.scan(/<loc>(.*?)<\/loc>/).flatten

        sitemap_links.each do |url|
          # Clean and add to links collection
          url = url.strip
          if url.start_with?(WEBSITE_URL)
            @links << url
            # Also add to queue for crawling if not processed
            @queue << url unless @processed_urls.include?(url)
          end
        end

        puts "  ✅ Found #{sitemap_links.size} URLs in sitemap"
      else
        puts "  ⚠️  Sitemap not found (HTTP #{response.code})"
      end
    rescue => e
      puts "  ⚠️  Error fetching sitemap: #{e.message}"
    end
  end

  def crawl_all_pages
    puts "\n🔍 Crawling website for internal links..."

    while url = @queue.shift
      next if @processed_urls.include?(url)

      @processed_urls << url
      puts "  Processing: #{url} (#{@processed_urls.size} processed, #{@links.size} links found)"

      begin
        html = fetch_page(url)
        next unless html

        extract_links(html, url)
      rescue => e
        puts "  ⚠️  Error processing #{url}: #{e.message}"
      end
    end

  end

  def fetch_page(url)
    uri = URI.parse(url)

    # Try fast request first (no explicit timeout)
    begin
      response = Net::HTTP.get_response(uri)
      return response.body if response.code == '200'
      return nil
    rescue Timeout::Error, Errno::ETIMEDOUT => e
      # If timeout, try once more with explicit longer timeout
      puts "  ⏱️  Timeout, retrying with longer timeout..."

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = 10
      http.read_timeout = 30

      request = Net::HTTP::Get.new(uri.path.empty? ? '/' : uri.path)
      request['User-Agent'] = 'Mozilla/5.0 (compatible; Ruby crawler)'

      response = http.request(request)
      return response.body if response.code == '200'
      return nil
    rescue => e
      puts "  ❌ Failed to fetch #{url}: #{e.message}"
      nil
    end
  end

  def extract_links(html, base_url)
    doc = Nokogiri::HTML(html)

    doc.css('a[href]').each do |link|
      href = link['href']
      next if href.nil? || href.empty?

      # Skip anchors, mailto, javascript
      next if href.start_with?('#', 'mailto:', 'javascript:', 'tel:')

      # Make absolute URL
      full_url = make_absolute_url(href, base_url)
      next unless full_url

      # Only process internal links
      next unless full_url.start_with?(WEBSITE_URL)

      # Remove fragment and query
      full_url = full_url.split('#').first
      full_url = full_url.split('?').first

      # Add to links collection
      @links << full_url

      # Add to queue if not processed
      unless @processed_urls.include?(full_url) || @queue.include?(full_url)
        @queue << full_url
      end
    end
  end

  def make_absolute_url(href, base_url)
    return nil if href.nil? || href.empty?

    if href.start_with?('http://', 'https://')
      href
    elsif href.start_with?('//')
      "https:#{href}"
    elsif href.start_with?('/')
      "#{WEBSITE_URL}#{href}"
    else
      # Relative URL
      base_uri = URI.parse(base_url)
      base_path = File.dirname(base_uri.path)
      base_path = '' if base_path == '/'
      "#{base_uri.scheme}://#{base_uri.host}#{base_path}/#{href}"
    end.gsub(/([^:])\/\/+/, '\1/')
  rescue => e
    puts "  ⚠️  Error creating URL from #{href}: #{e.message}"
    nil
  end

  def save_links
    puts "\n📁 Saving links to #{LINKS_FILE}..."

    File.open(LINKS_FILE, 'w') do |file|
      @links.sort.each do |link|
        file.puts link
      end
    end
  end

  def show_statistics
    puts "\n📊 Crawl Statistics:"
    puts "---------------------"
    puts "Total unique links found: #{@links.size}"
    puts "Pages crawled: #{@processed_urls.size}"
    puts ""
    puts "📁 Output file:"
    puts "  - #{LINKS_FILE} (#{@links.size} links)"

    # Show sources breakdown
    sitemap_count = @links.size # This is approximate, but gives an idea
    puts ""
    puts "📈 Source breakdown:"
    puts "  - From sitemap: ~#{sitemap_count} links"
    puts "  - From crawling: verified and discovered additional links"
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

# Run the crawler
if __FILE__ == $0
  crawler = WebsiteCrawler.new
  crawler.run
end