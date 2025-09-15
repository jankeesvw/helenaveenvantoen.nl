#!/usr/bin/env ruby

require 'fileutils'

class Cleaner
  FILES_TO_REMOVE = [
    "links.txt",
    "images.txt",
    "processed_urls.txt",
    "queue.txt"
  ]

  DIRECTORIES_TO_REMOVE = [
    "website_backup",
    "docs",
    "markdown",
    "temp_crawl"
  ]

  def run
    puts "==========================================="
    puts "🧹 Clean Script"
    puts "==========================================="
    puts ""

    show_current_state

    perform_cleanup

    puts ""
    puts "==========================================="
    puts "✅ Done!"
    puts "==========================================="
  end

  private

  def show_current_state
    puts "📊 Huidige status:"
    puts ""

    # Check files
    existing_files = FILES_TO_REMOVE.select { |f| File.exist?(f) }
    if existing_files.any?
      puts "📄 Bestanden gevonden:"
      existing_files.each do |file|
        size = File.size(file)
        size_str = format_size(size)
        puts "   - #{file} (#{size_str})"
      end
    else
      puts "📄 Geen tijdelijke bestanden gevonden"
    end

    puts ""

    # Check directories
    existing_dirs = DIRECTORIES_TO_REMOVE.select { |d| Dir.exist?(d) }
    if existing_dirs.any?
      puts "📁 Directories gevonden:"
      existing_dirs.each do |dir|
        size = `du -sh "#{dir}" 2>/dev/null | cut -f1`.strip
        file_count = Dir.glob(File.join(dir, "**", "*")).select { |f| File.file?(f) }.size
        puts "   - #{dir}/ (#{size}, #{file_count} bestanden)"
      end
    else
      puts "📁 Geen directories gevonden"
    end
  end

  def confirm_cleanup?
    puts ""
    puts "⚠️  Deze actie zal alle bovenstaande bestanden en directories verwijderen!"
    puts "    Dit kan niet ongedaan gemaakt worden."
    puts ""
    print "Weet je het zeker? (y/n): "

    response = gets.chomp.downcase
    response == 'y' || response == 'yes'
  end

  def perform_cleanup
    puts ""
    puts "🗑️  Bezig met opruimen..."
    puts ""

    # Remove files
    FILES_TO_REMOVE.each do |file|
      if File.exist?(file)
        File.delete(file)
        puts "   ✅ Verwijderd: #{file}"
      end
    end

    # Remove directories
    DIRECTORIES_TO_REMOVE.each do |dir|
      if Dir.exist?(dir)
        FileUtils.rm_rf(dir)
        puts "   ✅ Verwijderd: #{dir}/"
      end
    end

    puts ""
    puts "🎉 Alles is opgeruimd!"
    puts ""
    puts "Je kunt nu opnieuw beginnen met:"
    puts "   1. ruby crawl-website.rb       # Verzamel links"
    puts "   2. ruby download-and-convert.rb # Download en converteer"
    puts "   3. ruby download-images.rb      # Download images"
  end

  def format_size(size)
    case
    when size < 1024
      "#{size} B"
    when size < 1024 * 1024
      "#{(size / 1024.0).round(1)} KB"
    when size < 1024 * 1024 * 1024
      "#{(size / (1024.0 * 1024)).round(1)} MB"
    else
      "#{(size / (1024.0 * 1024 * 1024)).round(1)} GB"
    end
  end
end

# Run the cleaner
if __FILE__ == $0
  cleaner = Cleaner.new
  cleaner.run
end
