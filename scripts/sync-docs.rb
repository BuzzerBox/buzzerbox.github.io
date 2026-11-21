#!/usr/bin/env ruby
# frozen_string_literal: true

# Copies the documentation of BuzzerBox (formerly BuzzUI) and BuzzController into the site.
#
#   ruby scripts/sync-docs.rb [BUZZERBOX_DIR] [BUZZCONTROLLER_DIR]
#
# The directories default to $BUZZERBOX_DIR / $BUZZCONTROLLER_DIR, then to ../BuzzerBox (or ../BuzzUI, a checkout
# from before the rename) and ../BuzzController.
# $BUZZERBOX_REF / $BUZZCONTROLLER_REF name the branch the checkouts are on (default main); links to GitHub use it.
#
# A page or image folder that is missing in a checkout is skipped with a warning, so a doc that isn't merged yet
# doesn't break the deploy; links to it then go to GitHub.
#
# For each source file it:
#   - takes the first "# Heading" as the page title (the layout renders it),
#   - rewrites relative links: to another synced page -> its site URL, to an image -> the copied image,
#     to anything else in the repo -> the file on GitHub,
#   - writes front matter (layout, title, section, source link) and turns Liquid off, since the docs
#     contain Angular templates with {{ }}.
# It also writes _data/docs_nav.yml, the sidebar of the docs, in the order of SECTIONS below.
#
# The user guide is also in German (docs/user/de/ in BuzzerBox, on the site under /de/docs/user/). A section with a
# `lang` is only shown in the sidebar of pages in that language; one without is shown in all. A page and its
# translation share a `ref` (its file name), so the header can link them.
#
# Everything it writes is generated: see .gitignore, and don't edit it here, edit it in the source repo.

require "fileutils"
require "pathname"
require "yaml"

SITE = File.expand_path("..", __dir__)

REPOS = {
  "BuzzerBox" => {
    dir: ARGV[0] || ENV["BUZZERBOX_DIR"] ||
      %w[BuzzerBox BuzzUI].map { |d| File.join(SITE, "..", d) }.find { |d| File.directory?(d) } ||
      File.join(SITE, "..", "BuzzerBox"),
    url: "https://github.com/BuzzerBox/BuzzerBox",
    ref: ENV.fetch("BUZZERBOX_REF", "").then { |r| r.empty? ? "main" : r }
  },
  "BuzzController" => {
    dir: ARGV[1] || ENV["BUZZCONTROLLER_DIR"] || File.join(SITE, "..", "BuzzController"),
    url: "https://github.com/BuzzerBox/BuzzController",
    ref: ENV.fetch("BUZZCONTROLLER_REF", "").then { |r| r.empty? ? "main" : r }
  }
}.freeze

# Section => [[repo, source path, site path, optional title], ...], in sidebar order.
# Without a title, the first "# Heading" of the file is used.
SECTIONS = {
  "user" => {
    title: "User guide",
    lang: "en",
    pages: [
      ["BuzzerBox", "docs/user/README.md", "docs/user/index.md", "User guide"],
      ["BuzzerBox", "docs/user/quick-start.md", "docs/user/quick-start.md"],
      ["BuzzerBox", "docs/user/hosting-a-game.md", "docs/user/hosting-a-game.md"],
      ["BuzzerBox", "docs/user/creating-games.md", "docs/user/creating-games.md"],
      ["BuzzerBox", "docs/user/wireless-buzzers.md", "docs/user/wireless-buzzers.md"],
      ["BuzzerBox", "docs/user/box-settings-and-updates.md", "docs/user/box-settings-and-updates.md"],
      ["BuzzerBox", "docs/user/troubleshooting.md", "docs/user/troubleshooting.md"]
    ]
  },
  "user-de" => {
    title: "Benutzerhandbuch",
    lang: "de",
    pages: [
      ["BuzzerBox", "docs/user/de/README.md", "de/docs/user/index.md", "Benutzerhandbuch"],
      ["BuzzerBox", "docs/user/de/quick-start.md", "de/docs/user/quick-start.md"],
      ["BuzzerBox", "docs/user/de/hosting-a-game.md", "de/docs/user/hosting-a-game.md"],
      ["BuzzerBox", "docs/user/de/creating-games.md", "de/docs/user/creating-games.md"],
      ["BuzzerBox", "docs/user/de/wireless-buzzers.md", "de/docs/user/wireless-buzzers.md"],
      ["BuzzerBox", "docs/user/de/box-settings-and-updates.md", "de/docs/user/box-settings-and-updates.md"],
      ["BuzzerBox", "docs/user/de/troubleshooting.md", "de/docs/user/troubleshooting.md"]
    ]
  },
  "developer" => {
    title: "Software (BuzzerBox)",
    pages: [
      ["BuzzerBox", "docs/development.md", "docs/developer/development.md"],
      ["BuzzerBox", "docs/architecture.md", "docs/developer/architecture.md"],
      ["BuzzerBox", "server/README.md", "docs/developer/server.md"],
      ["BuzzerBox", "client/README.md", "docs/developer/client.md"],
      ["BuzzerBox", "docs/configuration.md", "docs/developer/configuration.md"],
      ["BuzzerBox", "docs/box-settings.md", "docs/developer/box-settings.md"],
      ["BuzzerBox", "docs/game-file-format.md", "docs/developer/game-file-format.md"],
      ["BuzzerBox", "docs/operations.md", "docs/developer/operations.md"],
      ["BuzzerBox", "provisioning/README.md", "docs/developer/provisioning.md", "Provisioning"]
    ]
  },
  "hardware" => {
    title: "Hardware & firmware",
    pages: [
      ["BuzzController", "README.md", "docs/hardware/controller.md", "Controller board"],
      ["BuzzerBox", "firmware/wireless-buzzer/README.md", "docs/hardware/wireless-buzzer.md"]
    ]
  }
}.freeze

# Image folders that are copied as they are: [repo, source dir, site dir]
IMAGE_DIRS = [
  ["BuzzerBox", "docs/user/images", "docs/user/images"],
  ["BuzzController", "docs/images", "docs/hardware/images"]
].freeze

# Sections (by "## Heading") that are left out of the site; delete an entry to show that section again.
SKIP_SECTIONS = ["License"].freeze

GENERATED = %w[docs/user docs/developer docs/hardware de/docs/user].freeze # includes the copied image folders
IMAGE_EXT = /\.(png|jpe?g|gif|svg|webp)\z/i

def site_url(site_path)
  "/" + site_path.sub(/index\.md\z/, "").sub(/\.md\z/, ".html")
end

REPOS.each do |name, repo|
  abort "#{name} not found at #{repo[:dir]} (pass its directory as an argument)" unless File.directory?(repo[:dir])
end

skipped = []

# [repo, normalized source path] => site URL, for the pages that exist in the checkouts
page_map = {}
SECTIONS.each_value do |s|
  s[:pages].each do |repo, src, dst, _|
    if File.file?(File.join(REPOS[repo][:dir], src))
      page_map[[repo, src]] = site_url(dst)
    else
      skipped << "#{repo}:#{src}"
    end
  end
end
image_dirs = IMAGE_DIRS.select do |repo, src, _|
  next true if File.directory?(File.join(REPOS[repo][:dir], src))

  skipped << "#{repo}:#{src}/"
  false
end
image_map = image_dirs.to_h { |repo, src, dst| [[repo, src], "/#{dst}"] }

GENERATED.each { |d| FileUtils.rm_rf(File.join(SITE, d)) }

image_dirs.each do |repo, src, dst|
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
  "#{REPOS[repo][:url]}/#{kind}/#{REPOS[repo][:ref]}/#{resolved}#{suffix}"
end

nav = []
SECTIONS.each do |section, s|
  items = []
  s[:pages].each do |repo, src, dst, title_override|
    next unless page_map.key?([repo, src])

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
      "source_url" => "#{REPOS[repo][:url]}/blob/#{REPOS[repo][:ref]}/#{src}",
      "render_with_liquid" => false
    }
    if s[:lang]
      front["lang"] = s[:lang]
      front["ref"] = "docs-user-#{File.basename(dst, ".md")}"
    end
    out = File.join(SITE, dst)
    FileUtils.mkdir_p(File.dirname(out))
    File.write(out, "#{front.to_yaml}---\n\n#{text}")
    items << { "title" => title, "url" => site_url(dst) }
  end
  entry = { "section" => section, "title" => s[:title] }
  entry["lang"] = s[:lang] if s[:lang]
  nav << entry.merge("pages" => items) unless items.empty?
end

FileUtils.mkdir_p(File.join(SITE, "_data"))
File.write(File.join(SITE, "_data", "docs_nav.yml"),
           "# Generated by scripts/sync-docs.rb, don't edit.\n#{nav.to_yaml}")

skipped.each { |path| warn "warning: #{path} not found, skipped" }
puts "Synced #{page_map.size} pages and #{image_dirs.size} image folder(s)" \
     "#{", skipped #{skipped.size}" unless skipped.empty?}."
