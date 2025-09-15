# Helenaveen van Toen - Website Archief

Dit project archiveert de website https://www.helenaveenvantoen.nl voor offline gebruik en converteer naar Markdown.

## 🚀 Quick Start

```bash
# Installeer dependencies (eenmalig)
gem install nokogiri

# Voer de scripts uit
ruby crawl-website.rb         # Stap 1: Verzamel alle links
ruby download-and-convert.rb  # Stap 2: Download en converteer naar Markdown
ruby download-images.rb       # Stap 3: Download alle afbeeldingen

# Opnieuw beginnen
ruby clean.rb                 # Verwijder alle gegenereerde bestanden
```

## 📁 Project Structuur

### Ruby Scripts (Nieuw)
- `crawl-website.rb` - Crawlt de website en verzamelt alle interne links
- `download-and-convert.rb` - Download HTML en converteert direct naar Markdown
- `download-images.rb` - Download afbeeldingen uit Markdown en update de links
- `clean.rb` - Ruimt alle gegenereerde bestanden op voor een schone start

### Output Directories
- `docs/` - Markdown bestanden en afbeeldingen (GitHub Pages compatible)
  - `*.md` - Geconverteerde Markdown pagina's
  - `images/[pagina-naam]/` - Afbeeldingen per pagina
  - `INDEX.md` - Overzicht van alle pagina's
- `website_backup/` - Tijdelijke HTML bestanden (wordt verwijderd na conversie)

## 🔧 Installatie

### Ruby Dependencies

```bash
# macOS/Linux
gem install nokogiri

# Of met bundler
bundle install
```


## 📖 Gebruik

### Complete Workflow

1. **Crawl de website**
   ```bash
   ruby crawl-website.rb
   ```
   - Verzamelt alle interne links
   - Output: `links.txt`

2. **Download en converteer**
   ```bash
   ruby download-and-convert.rb
   ```
   - Download alle pagina's van `links.txt`
   - Converteert HTML naar Markdown met Nokogiri
   - Verwijdert navigatie elementen en buttons
   - Cleaned HTML entities (&nbsp; etc.)
   - Output: `docs/*.md`

3. **Download afbeeldingen**
   ```bash
   ruby download-images.rb
   ```
   - Scant Markdown bestanden voor externe afbeeldingen
   - Download afbeeldingen naar `docs/images/[pagina-naam]/`
   - Update Markdown met lokale paden

### Opnieuw beginnen

```bash
ruby clean.rb
```
Verwijdert alle gegenereerde bestanden en directories voor een schone start.

