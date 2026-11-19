#!/usr/bin/env ruby
# frozen_string_literal: true

# Copies the documentation of BuzzUI and BuzzController into the site.
#
#   ruby scripts/sync-docs.rb [BUZZUI_DIR] [BUZZCONTROLLER_DIR]
#
# The directories default to $BUZZUI_DIR / $BUZZCONTROLLER_DIR, then to ../BuzzUI and ../BuzzController.
#
# For each source file it:
#   - takes the first "# Heading" as the page title (the layout renders it),
#   - rewrites relative links: to another synced page -> its site URL, to an image -> the copied image,
#     to anything else in the repo -> the file on GitHub,
#   - writes front matter (layout, title, section, source link) and turns Liquid off, since the docs
#     contain Angular templates with {{ }}.
# It also writes _data/docs_nav.yml, the sidebar of the docs, in the order of SECTIONS below.
#
# Everything it writes is generated: see .gitignore, and don't edit it here, edit it in the source repo.

require "fileutils"
require "pathname"
require "yaml"

SITE = File.expand_path("..", __dir__)

REPOS = {
  "BuzzUI" => {
    dir: ARGV[0] || ENV["BUZZUI_DIR"] || File.join(SITE, "..", "BuzzUI"),
    url: "https://github.com/BuzzerBox/BuzzUI"
  },
  "BuzzController" => {
    dir: ARGV[1] || ENV["BUZZCONTROLLER_DIR"] || File.join(SITE, "..", "BuzzController"),
    url: "https://github.com/BuzzerBox/BuzzController"
  }
}.freeze

# Section => [[repo, source path, site path, optional title], ...], in sidebar order.
# Without a title, the first "# Heading" of the file is used.
SECTIONS = {
  "user" => {
    title: "User guide",
    pages: [
      ["BuzzUI", "docs/user/README.md", "docs/user/index.md", "User guide"],
      ["BuzzUI", "docs/user/quick-start.md", "docs/user/quick-start.md"],
      ["BuzzUI", "docs/user/hosting-a-game.md", "docs/user/hosting-a-game.md"],
      ["BuzzUI", "docs/user/creating-games.md", "docs/user/creating-games.md"],
      ["BuzzUI", "docs/user/wireless-buzzers.md", "docs/user/wireless-buzzers.md"],
      ["BuzzUI", "docs/user/box-settings-and-updates.md", "docs/user/box-settings-and-updates.md"],
      ["BuzzUI", "docs/user/troubleshooting.md", "docs/user/troubleshooting.md"]
    ]
  },
  "developer" => {
    title: "Software (BuzzUI)",
    pages: [
      ["BuzzUI", "docs/development.md", "docs/developer/development.md"],
      ["BuzzUI", "docs/architecture.md", "docs/developer/architecture.md"],
      ["BuzzUI", "server/README.md", "docs/developer/server.md"],
      ["BuzzUI", "client/README.md", "docs/developer/client.md"],
      ["BuzzUI", "docs/configuration.md", "docs/developer/configuration.md"],
      ["BuzzUI", "docs/box-settings.md", "docs/developer/box-settings.md"],
      ["BuzzUI", "docs/game-file-format.md", "docs/developer/game-file-format.md"],
      ["BuzzUI", "docs/operations.md", "docs/developer/operations.md"],
      ["BuzzUI", "provisioning/README.md", "docs/developer/provisioning.md", "Provisioning"]
    ]
  },
  "hardware" => {
    title: "Hardware & firmware (BuzzController)",
    pages: [
      ["BuzzController", "README.md", "docs/hardware/controller.md", "Controller board"],
      ["BuzzController", "wireless/README.md", "docs/hardware/wireless-buzzer.md"]
    ]
  }
}.freeze

# Image folders that are copied as they are: [repo, source dir, site dir]
IMAGE_DIRS = [
  ["BuzzUI", "docs/user/images", "docs/user/images"],
  ["BuzzController", "docs/images", "docs/hardware/images"]
].freeze

# Sections (by "## Heading") that are left out of the site; delete an entry to show that section again.
SKIP_SECTIONS = ["License"].freeze

GENERATED = %w[docs/user docs/developer docs/hardware].freeze # includes the copied image folders
IMAGE_EXT = /\.(png|jpe?g|gif|svg|webp)\z/i

def site_url(site_path)
  "/" + site_path.sub(/index\.md\z/, "").sub(/\.md\z/, ".html")
end

REPOS.each do |name, repo|
  abort "#{name} not found at #{repo[:dir]} (pass its directory as an argument)" unless File.directory?(repo[:dir])
end

# [repo, normalized source path] => site URL
page_map = {}
SECTIONS.each_value do |s|
  s[:pages].each { |repo, src, dst, _| page_map[[repo, src]] = site_url(dst) }
end
image_map = IMAGE_DIRS.to_h { |repo, src, dst| [[repo, src], "/#{dst}"] }

GENERATED.each { |d| FileUtils.rm_rf(File.join(SITE, d)) }

IMAGE_DIRS.each do |repo, src, dst|
  FileUtils.mkdir_p(File.join(SITE, dst))
  FileUtils.cp_r(Dir[File.join(REPOS[repo][:dir], src, "*")], File.join(SITE, dst))
end

def rewrite_link(target, repo, src, page_map, image_map)
  return target if target.match?(%r{\A([a-z]+:|#|/)}i) # absolute URL, anchor or site-absolute

  path, anchor = target.split("#", 2)
  resolved = Pathname.new(File.dirname(src)).join(path).cleanpath.to_s
  suffix = anchor ? "##{anchor}" : ""

  if (url = page_map[[repo, resolved]])
    return url + suffix
  end

  image_map.each do |(img_repo, img_dir), url|
    next unless img_repo == repo && resolved.start_with?("#{img_dir}/")

    return url + resolved.delete_prefix(img_dir) + suffix
  end

  kind = path.match?(IMAGE_EXT) ? "raw" : (path.end_with?("/") || File.extname(path).empty? ? "tree" : "blob")
  "#{REPOS[repo][:url]}/#{kind}/main/#{resolved}#{suffix}"
end

nav = []
SECTIONS.each do |section, s|
  items = []
  s[:pages].each do |repo, src, dst, title_override|
    text = File.read(File.join(REPOS[repo][:dir], src))
    title = title_override || text[/\A\s*#\s+(.+)$/, 1]&.strip || File.basename(dst, ".md")
    text = text.sub(/\A\s*#\s+.+\n/, "") # the layout renders the title
    SKIP_SECTIONS.each do |heading|
      # from "## Heading" up to the next heading of level 1 or 2, or the end; also a "---" rule just before it
      text = text.sub(/(?:^---\s*\n\s*)?^##\s+#{Regexp.escape(heading)}\s*\n.*?(?=^[#]{1,2}\s|\z)/m, "")
    end

    # [text](target) and [text](target "title"); keep fenced code untouched
    in_fence = false
    text = text.lines.map do |line|
      in_fence = !in_fence if line.match?(/\A\s*(```|~~~)/)
      next line if in_fence

      line.gsub(/(\]\()([^)\s]+)((?:\s+"[^"]*")?\))/) do
        "#{$1}#{rewrite_link($2, repo, src, page_map, image_map)}#{$3}"
      end
    end.join

    front = {
      "layout" => "doc",
      "title" => title,
      "section" => section,
      "source_url" => "#{REPOS[repo][:url]}/blob/main/#{src}",
      "render_with_liquid" => false
    }
    out = File.join(SITE, dst)
    FileUtils.mkdir_p(File.dirname(out))
    File.write(out, "#{front.to_yaml}---\n\n#{text}")
    items << { "title" => title, "url" => site_url(dst) }
  end
  nav << { "section" => section, "title" => s[:title], "pages" => items }
end

FileUtils.mkdir_p(File.join(SITE, "_data"))
File.write(File.join(SITE, "_data", "docs_nav.yml"),
           "# Generated by scripts/sync-docs.rb, don't edit.\n#{nav.to_yaml}")

puts "Synced #{page_map.size} pages and #{IMAGE_DIRS.size} image folder(s)."
