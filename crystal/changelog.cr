#!/usr/bin/env crystal
# A script to automate changelog generation from Git commit messages
#
# For use with a git-flow workflow, it will take changes from the last tagged
# release where commit messages contain NEW, FIXED, CHANGED, and IMPROVED
# keywords and sort and format them into a Markdown release note list.
#
# The script takes version information from version.rb files, the macOS
# command agvtool (bases the product name on the first matching Xcode Info.plist
# found) or from a plain text VERSION file.
#
# Format commit messages with markers:
#
# Commit message
# - NEW: New feature description
# - FIXED: Fix description
#
# OR with @format:
#
# Commit message
# @new New feature
# @changed application feature change
# @breaking breaking change

require "option_parser"
require "yaml"

VERSION = "1.0.8"

# Strings for section titles and keywords
CL_STRINGS = {
  :changed   => {"title" => "CHANGED", "rx" => "(CHANGED?|BREAK(ING)?)"},
  :new       => {"title" => "NEW", "rx" => "(NEW|ADD(ED)?)"},
  :improved  => {"title" => "IMPROVED", "rx" => "(IMP(ROV(MENT|ED)?)?|UPD(ATED?)?)"},
  :fixed     => {"title" => "FIXED", "rx" => "FIX(ED)?"},
  :deprecated => {"title" => "REMOVED", "rx" => "(DEP(RECATED)?|REM(OVED?)?)"},
}

module StringHelpers
  def cap_first
    if match = self.match(/^([a-z])(.*)$/)
      match[1].upcase + match[2]
    else
      self
    end
  end

  def clean_entry
    rx_parts = CL_STRINGS.map do |_, v|
      "(?:@#{v["rx"].downcase}|#{v["rx"]}:)"
    end
    rx = "(?:#{rx_parts.join("|")})"
    pattern = /^(?:[-*+] )*#{rx} *(: )?/
    self.sub(pattern, "").strip.cap_first
  end

  def link_github_issues(base_url : String?)
    return self if base_url.nil? || base_url.empty?

    # (?!\]) avoids matching #N inside existing [...](#N) links
    self.gsub(/#(\d+)(?!\])/) { "[##{$1}](#{base_url}/#{$1})" }
  end

  def strip_non_ascii
    # Simplify: remove non-ASCII characters
    self.each_char.select(&.ascii?).join
  end
end

class String
  include StringHelpers
end

class Change
  property githash : String
  property date : String
  property changes : String

  def initialize(@githash : String, @date : String, @changes : String)
  end
end

class ChangeSet
  property changed : Array(String)
  property new : Array(String)
  property improved : Array(String)
  property fixed : Array(String)
  property deprecated : Array(String)

  def initialize
    @changed = [] of String
    @new = [] of String
    @improved = [] of String
    @fixed = [] of String
    @deprecated = [] of String
  end

  def add(type : Symbol, change : String)
    case type
    when :changed   then @changed << change
    when :new       then @new << change
    when :improved  then @improved << change
    when :fixed     then @fixed << change
    when :deprecated then @deprecated << change
    end
  end

  def get(type : Symbol) : Array(String)
    case type
    when :changed   then @changed
    when :new       then @new
    when :improved  then @improved
    when :fixed     then @fixed
    when :deprecated then @deprecated
    else
      [] of String
    end
  end
end

class ChangeLog
  include Enumerable(Change)
  property entries : Array(Change)

  def initialize(@entries : Array(Change) = [] of Change)
  end

  def <<(change : Change)
    @entries << change
  end

  def each(&block : Change ->)
    @entries.each(&block)
  end

  def changes : Array(String)
    res = [] of String
    each do |v|
      chgs = v.changes.strip.split("\n").reject(&.strip.empty?)
      res.concat(chgs)
    end
    res.uniq
  end
end

def compare_versions(a : String, b : String) : Int32
  a_parts = a.gsub(/[^0-9.]/, "").split(".").map { |s| s.to_i? || 0 }
  b_parts = b.gsub(/[^0-9.]/, "").split(".").map { |s| s.to_i? || 0 }

  max_len = {a_parts.size, b_parts.size}.max
  max_len.times do |i|
    a_val = a_parts[i]? || 0
    b_val = b_parts[i]? || 0
    return -1 if a_val < b_val
    return 1 if a_val > b_val
  end
  0
end

def run_cmd(command : String) : String
  stdout = IO::Memory.new
  Process.run("/bin/sh", ["-c", command], output: stdout)
  stdout.to_s.strip
end

def run_cmd_with_input(program : String, args : Array(String), input_data : String) : String
  stdout = IO::Memory.new
  Process.run(program, args, input: IO::Memory.new(input_data), output: stdout)
  stdout.to_s.strip
end

def shell_escape(str : String) : String
  "'" + str.gsub("'", "'\"'\"'") + "'"
end

module GitLogParser
  extend self

  def gen_rx : String
    parts = CL_STRINGS.map { |_, v| "(?:@#{v["rx"].downcase}:?|- #{v["rx"]}:)" }
    "(#{parts.join("|")})"
  end

  def revision(options : Hash) : String
    if (since_val = options[:since_version]?) && (since = since_val.to_s).size > 0
      tags = run_cmd("git tag -l").split("\n")
      matches = tags.select { |tag| tag.includes?(since) }
      if matches.empty?
        STDERR.puts "No matching tag found for '#{since}'"
        exit 1
      end
      selected_tag = if matches.size == 1 || !STDIN.tty?
        matches.first
      else
        result = run_cmd_with_input("fzf", ["--tac"], matches.join("\n"))
        if result.empty?
          STDERR.puts "No selection made"
          exit 1
        end
        result
      end
      run_cmd("git log -1 --format=format:\"%H\" #{selected_tag}")
    elsif options[:select]?
      tags = run_cmd("git tag -n0 -l")
      selection = run_cmd_with_input("fzf", ["--tac"], tags)
      raise "No selection" if selection.empty?
      tag_name = selection.split("\t").first?.try(&.strip) || selection
      run_cmd("git log -1 --format=format:\"%H\" #{tag_name}")
    else
      run_cmd("git rev-list --tags --max-count=1")
    end
  end

  def tags_in_range(options : Hash) : Array(NamedTuple(tag: String, hash: String))
    since_hash = options[:_cached_revision]? || GitLogParser.revision(options)
    tag_info = run_cmd("git tag --sort=-creatordate --format='%(refname:short) %(objectname:short)'")
    return [] of NamedTuple(tag: String, hash: String) if tag_info.empty?

    result = [] of NamedTuple(tag: String, hash: String)
    tag_info.split("\n").each do |line|
      parts = line.split(" ")
      next if parts.size < 2
      tag, hash = parts[0], parts[1]
      if system("git merge-base --is-ancestor #{since_hash} #{hash} 2>/dev/null")
        result << {tag: tag, hash: hash}
      end
    end
    result
  end

  def commits_between(from_ref : String, to_ref : String) : Array(Change)
    log = run_cmd("git log --pretty=format:'===%h%n%ci%n%s%n%b' --reverse #{from_ref}..#{to_ref}")
    return [] of Change if log.empty?

    entries = [] of Change
    gen = gen_rx
    log.split(/^===/).each do |entry|
      e = split_gitlog(entry.strip, gen)
      entries << e if e && !e.githash.empty?
    end
    entries
  end

  def split_gitlog(entry : String, gen_rx : String) : Change?
    lines = entry.strip_non_ascii
    lines_arr = lines.split("\n")
    return nil if lines_arr.size < 3

    loghash = lines_arr.shift || ""
    date = lines_arr.shift || ""
    return nil if lines_arr[0]? =~ /^Merge (branch|tag)/

    changes = lines_arr.reject(&.strip.empty?).join("\n")
    Change.new(loghash, date, changes)
  end

  def version_set_empty?(changeset : ChangeSet) : Bool
    CL_STRINGS.keys.all? { |k| changeset.get(k).empty? }
  end

  def parse(options : Hash, revision_method : -> String, gen_rx_method : -> String) : ChangeLog
    since = run_cmd("git show -s --format=%ad #{revision_method.call}")
    log = run_cmd("git log --pretty=format:'===%h%n%ci%n%s%n%b' --reverse --since=\"#{since}\"")

    if file = options[:file]?
      content = File.read(File.expand_path(file.to_s)).strip
      log = "===XXXXXXX\n#{Time.utc.to_s("%+%F %T %z")}\n#{content}\n\n#{log}"
    end

    if !log.empty?
      cl = ChangeLog.new
      log.split(/^===/).each do |ent|
        e = split_gitlog(ent.strip, gen_rx_method.call)
        cl << e if e && !e.githash.empty?
      end
      return cl
    else
      STDERR.puts "No new entries"
      exit 1
    end
  end

  def sort_changes(logger : ChangeLogger)
    log = logger.log
    gen = gen_rx
    chgs = [] of String
    gen_re = Regex.new(gen)
    log.each do |l|
      chgs.concat(l.changes.split("\n").select { |ch| ch =~ gen_re })
    end
    chgs.each do |change|
      CL_STRINGS.each do |k, v|
        if change =~ Regex.new("(?:@#{v["rx"].downcase}:?|- #{v["rx"]}:)")
          logger.changes.add(k, change.clean_entry)
        end
      end
    end
  end

  def sort_changes_by_version(logger : ChangeLogger)
    options = logger.@options
    tags = tags_in_range(options)

    if tags.empty?
      sort_changes(logger)
      return
    end

    current_version = logger.version || "Unreleased"
    previous_ref = (options[:_cached_revision]? || revision(options)).to_s
    gen = gen_rx
    gen_re = Regex.new(gen)

    tags.reverse.each do |tag_info|
      tag = tag_info[:tag]
      tag_hash = tag_info[:hash]

      entries = commits_between(previous_ref, tag_hash)
      unless entries.empty?
        version_set = ChangeSet.new
        entries.each do |entry|
          next unless entry.changes
          entry.changes.split("\n").each do |line|
            next unless line =~ gen_re
            CL_STRINGS.each do |k, v|
              if line =~ Regex.new("(?:@#{v["rx"].downcase}:?|- #{v["rx"]}:)")
                version_set.add(k, line.clean_entry)
              end
            end
          end
        end
        logger.version_changes[tag] = version_set unless version_set_empty?(version_set)
      end
      previous_ref = tag_hash
    end

    entries = commits_between(previous_ref, "HEAD")
    return if entries.empty?

    version_set = ChangeSet.new
    entries.each do |entry|
      next unless entry.changes
      entry.changes.split("\n").each do |line|
        next unless line =~ gen_re
        CL_STRINGS.each do |k, v|
          if line =~ Regex.new("(?:@#{v["rx"].downcase}:?|- #{v["rx"]}:)")
            version_set.add(k, line.clean_entry)
          end
        end
      end
    end
    logger.version_changes[current_version] = version_set unless version_set_empty?(version_set)
  end
end

class ChangeLogger
  property changes : ChangeSet
  property version : String?
  property version_changes : Hash(String, ChangeSet)
  getter options : Hash(Symbol, String | Bool | Symbol | Array(Symbol) | Nil)
  getter log : ChangeLog

  def initialize(app_title : String? = nil, options : Hash = {} of Symbol => String | Bool | Symbol | Array(Symbol) | Nil)
    @options = options
    @options[:order] ||= :desc
    @changes = ChangeSet.new
    @version_changes = {} of String => ChangeSet
    @app_title = app_title
    @version = nil
    @options[:_cached_revision] = GitLogParser.revision(@options) unless @options[:_cached_revision]?
    revision_lambda = -> { @options[:_cached_revision].to_s }
    gen_rx_lambda = -> { GitLogParser.gen_rx }
    @log = GitLogParser.parse(@options, revision_lambda, gen_rx_lambda)

    if @options[:split]?
      GitLogParser.sort_changes_by_version(self)
    else
      GitLogParser.sort_changes(self)
    end
  end

  def to_s : String
    return split_output if @options[:split]? && !@version_changes.empty?

    fmt = @options[:format].as(Symbol?)
    version_info = VersionDetector.detect(@options, @version, @app_title, fmt || :markdown)
    @version = version_info[:version]
    @app_title = version_info[:app_name]

    header_lambda = ->(fmt : Symbol) {
      if fmt == (fmt_for_detection = @options[:format].as(Symbol?) || :markdown)
        version_info[:header_out]
      else
        ChangelogFormatter.header(fmt, @options, @version, @app_title)
      end
    }

    ChangelogFormatter.format(@changes, @options, header_lambda, @version)
  end

  def split_output : String
    types = CL_STRINGS.select { |k, _| (@options[:types].as(Array(Symbol))).includes?(k) }
    gh_base = ChangelogFormatter.github_issues_base_url
    linkify = ->(item : String) { item.link_github_issues(gh_base) }
    output = ""
    versions = @version_changes.keys.to_a
    versions = versions.reverse if @options[:order] == :desc
    versions.each do |version|
      changeset = @version_changes[version]
      case @options[:format]
      when :keepachangelog
        output += "## [#{version}] - #{Time.utc.to_s("%F")}\n\n"
        types.each_key do |k|
          chs = changeset.get(k)
          next if chs.empty?
          output += "### #{CL_STRINGS[k]["title"].capitalize}\n\n"
          output += "- #{chs.map { |item| linkify.call(item) }.join("\n- ")}\n\n"
        end
      when :def_list
        output += "#{version}\n"
        types.each_key do |k|
          changeset.get(k).each { |item| output += ": #{linkify.call(item)}\n" }
        end
        output += "\n"
      else
        output += "### #{version}\n\n"
        types.each_key do |k|
          chs = changeset.get(k)
          next if chs.empty?
          output += "#### #{CL_STRINGS[k]["title"]}\n\n"
          output += "- #{chs.map { |item| linkify.call(item) }.join("\n- ")}\n\n"
        end
      end
    end
    output
  end

  def self.add_keepachangelog_link_static(content : String, version : String?) : String
    return content unless version && content =~ /## \[#{Regex.escape(version)}\]/
    version_rx = version.gsub(".", "\\.")
    return content if content =~ /^\[#{version_rx}\]:/m

    base_url = nil
    if content =~ /^\[\d+\.\d+\.\d+\]: *(https:\/\/github\.com\/[^\/]+\/[^\/]+\/releases\/tag\/v?)[\d.]+ *$/m
      base_url = $1
    else
      repo_url = run_cmd("git config --get remote.origin.url")
      if repo_url =~ /github\.com[:\/](.+)\/(.+?)(\.git)?$/
        base_url = "https://github.com/#{$1}/#{$2}/releases/tag/v"
      end
    end

    return content unless base_url
    new_link = "[#{version}]: #{base_url}#{version}"
    "#{content.rstrip}\n\n#{new_link}\n"
  end

  def self.cleanup_keepachangelog_links(content : String, order : Symbol = :desc) : String
    links = [] of NamedTuple(version: String, url: String, full: String)
    content.scan(/^\[(\d+\.\d+\.\d+.*?)\]: *(https:\/\/github\.com\/[^\s]+) *$/m) do
      links << {version: $1, url: $2, full: "[#{$1}]: #{$2}"}
    end

    return content if links.empty?

    content = content.gsub(/^\[\d+\.\d+\.\d+.*?\]: *https:\/\/github\.com\/[^\s]+ *\n?/m, "")
    content = content.gsub(/\n{3,}/, "\n\n")

    seen = Set(String).new
    unique_links = links.select do |link|
      next false if seen.includes?(link[:version])
      seen.add(link[:version])
      true
    end

    sorted = unique_links.sort do |a, b|
      cmp = compare_versions(a[:version].gsub(/[^0-9.]/, ""), b[:version].gsub(/[^0-9.]/, ""))
      order == :desc ? -cmp : cmp
    end

    content = content.rstrip
    content += "\n\n" + sorted.map(&.[:full]).join("\n") + "\n" if sorted.any?
    content
  end
end

module ChangelogFormatter
  extend self

  def github_issues_base_url : String?
    url = run_cmd("git config --get remote.origin.url 2>/dev/null")
    return nil if url.empty?
    if url =~ /github\.com[:\/]([^\/]+)\/([^\/]+?)(?:\.git)?$/
      "https://github.com/#{$1}/#{$2}/issues"
    end
  end

  def format_header(build : String, fmt : Symbol) : String
    case fmt
    when :marked
      "Marked #{build}\n-------------------------\n\n"
    when :def_list
      "#{build}\n"
    when :git
      "#{build}\n\n"
    when :bunch
      "{% available #{build} %}\n\n---\n\n#{build}"
    when :keepachangelog
      "## [#{build}] - #{Time.utc.to_s("%F")}\n\n"
    else
      "### #{build}\n\n#{Time.utc.to_s("%F %R")}\n\n"
    end
  end

  def header(fmt : Symbol = :markdown, options : Hash = {} of Symbol => String, version : String? = nil, app_title : String? = nil) : String
    return "" if options[:no_version]?
    version_info = VersionDetector.detect(options, version, app_title, fmt)
    version_info[:header_out]
  end

  def format(changes : ChangeSet, options : Hash, header_method : Symbol -> String, version : String?) : String
    types = CL_STRINGS.select { |k, _| (options[:types].as(Array(Symbol))).includes?(k) }
    gh_base = github_issues_base_url
    linkify = ->(item : String) { item.link_github_issues(gh_base) }

    case options[:format]
    when :def_list
      output = [] of String
      types.each_key do |k|
        changes.get(k).each { |item| output << ": #{linkify.call(item)}" }
      end
      "#{header_method.call(:def_list)}#{output.join("\n")}"
    when :bunch
      output = [] of String
      types.each_key do |k|
        icon = case k.to_s.downcase
               when .starts_with?("fix") then "fix"
               when .starts_with?("cha"), .starts_with?("imp") then "imp"
               when .starts_with?("new") then "new"
               else "new"
               end
        changes.get(k).each do |item|
          txt = item.gsub(/https:\/\/bunchapp\.co/, "{{ site.baseurl }}")
          ico = "{% icon #{icon} %}"
          ico += "{% icon breaking %}" if txt =~ /BREAKING/
          output << ": #{ico} #{linkify.call(txt)}"
        end
      end
      "#{header_method.call(:bunch)}\n#{output.join("\n")}\n\n{% endavailable %}"
    when :keepachangelog
      output = ""
      types.each_key do |k|
        v = changes.get(k)
        next if v.empty?
        output += "### #{CL_STRINGS[k]["title"].capitalize}\n\n"
        output += "- #{v.map { |item| linkify.call(item) }.join("\n- ")}\n\n"
      end
      result = header_method.call(:keepachangelog) + output
      ChangeLogger.add_keepachangelog_link_static(result, version)
    else
      output = ""
      types.each_key do |k|
        v = changes.get(k)
        next if v.empty?
        output += "#### #{CL_STRINGS[k]["title"]}\n\n"
        output += "- #{v.map { |item| linkify.call(item) }.join("\n- ")}\n\n"
      end
      header_method.call(options[:format].as(Symbol)) + output
    end
  end
end

module VersionDetector
  extend self

  def detect(options : Hash, current_version : String?, current_app_name : String?, fmt : Symbol) : NamedTuple(version: String?, app_name: String?, header_out: String)
    version = options[:version]?.try(&.to_s) || current_version
    app_name = current_app_name
    header_out = ""

    if File.exists?("Cargo.toml")
      cargo = File.read("Cargo.toml")
      app_name = $1 if cargo =~ /^name\s*=\s*"([^"]+)"/m
      version = $1 if cargo =~ /^version\s*=\s*"([^"]+)"/m
    elsif Dir.glob("**/*.rs").any?
      Dir.glob("**/*.rs").each do |f|
        content = File.read(f)
        version = $1 if !version && content =~ /const VERSION: *&str *= *"([^"]+)"/
        app_name = $1 if !app_name && content =~ /Command::new\("([^"]+)"\)/
      end
    end

    version ||= begin
      files = Dir.glob("lib/**/version.rb")
      if files.any?
        content = File.read(files[0]) rescue ""
        content =~ /VERSION *= *(['"])(.*?)\1/ ? $2 : nil
      elsif {"VERSION", "VERSION.txt", "VERSION.md"}.any? { |f| File.exists?(f) }
        vf = {"VERSION", "VERSION.txt", "VERSION.md"}.find { |f| File.exists?(f) }
        vf ? File.read(vf).strip : nil
      elsif (gv = run_cmd("git ver")).strip.size > 0
        gv.strip
      end
    end

    if fmt == :keepachangelog
      header_out = ChangelogFormatter.format_header(version.to_s, :keepachangelog)
    elsif options[:version]?
      header_out = ChangelogFormatter.format_header(options[:version].to_s, fmt)
    elsif Dir.glob("lib/**/version.rb").any?
      specs = Dir.glob("*.gemspec")
      if specs.any?
        app_name = File.basename(specs[0], ".gemspec")
        vfiles = Dir.glob("lib/*/version.rb")
        if vfiles.any?
          build = (File.read(vfiles[0]) =~ /VERSION *= *(['"])(.*?)\1/) ? $2 : nil
          version = build
          header_out = ChangelogFormatter.format_header(build.to_s, fmt)
        end
      end
    elsif File.exists?("Package.swift")
      content = File.read("Package.swift")
      if content =~ /Package\(.*?name: *"(.*?)"/m
        app_name = $1
      end
      version = run_cmd("git semnext")
      header_out = "## #{version}\n\n"
    elsif {"VERSION", "VERSION.txt", "VERSION.md"}.any? { |f| File.exists?(f) }
      vf = {"VERSION", "VERSION.txt", "VERSION.md"}.find { |f| File.exists?(f) }
      app_name = File.basename(File.expand_path("."))
      version = File.read(vf.not_nil!).strip
      header_out = ChangelogFormatter.format_header(version, fmt)
    elsif (gv = run_cmd("git ver")).strip.size > 0
      version = gv
    else
      ["config.yml", "config.yaml"].each do |filename|
        next unless File.exists?(filename)
        begin
          config = YAML.parse(File.read(filename))
          if config
            app_name = config["title"]?.try(&.to_s) || File.basename(File.dirname(File.expand_path(filename)))
            version = config["version"]?.try(&.to_s)
            header_out = "### #{app_name} #{version}\n\n"
          end
        rescue
        end
      end
    end

    {version: version, app_name: app_name, header_out: header_out}
  end
end

LOG_FORMATS = [:def_list, :bunch, :markdown, :keepachangelog]

class App
  property options : Hash(Symbol, String | Bool | Symbol | Array(Symbol) | Nil)
  property app_title : String?

  def initialize(args : Array(String))
    top = run_cmd("git rev-parse --show-toplevel")
    Dir.cd(top)

    @options = {} of Symbol => String | Bool | Symbol | Array(Symbol) | Nil
    @options[:select] = false
    @options[:split] = false
    @options[:file] = nil
    @options[:format] = nil
    @options[:copy] = false
    @options[:update] = nil
    @options[:version] = nil
    @options[:no_version] = false
    @options[:types] = [:changed, :new, :improved, :fixed] of Symbol
    @options[:order] = :desc

    OptionParser.parse(args) do |parser|
      parser.banner = "Usage: changelog [options] [CHANGELOG_FILE] [APP_NAME]\n  Gets git log entries since last tag containing #{CL_STRINGS.map { |_, v| v["title"] }.join(", ")}"
      parser.on("--since-version [VER]", "Show changelog since tag matching VER") { |v| @options[:since_version] = v }
      parser.on("--sv [VER]", "Alias for --since-version") { |v| @options[:since_version] = v }
      parser.on("-c", "--copy", "Copy results to clipboard") { @options[:copy] = true }
      parser.on("-f FORMAT", "--format FORMAT", "Output format (#{LOG_FORMATS.join("|")})") do |fmt|
        unless fmt =~ /^[dbmk]/
          puts "Invalid format: #{fmt}. Available: #{LOG_FORMATS.join(", ")}"
          exit 1
        end
        @options[:format] = case fmt
                           when /^d/ then :def_list
                           when /^b/ then :bunch
                           when /^k/ then :keepachangelog
                           when /^m/ then :markdown
                           else :markdown
                           end
      end
      parser.on("-o TYPES", "--only TYPES", "Only output changes of type (#{CL_STRINGS.keys.join(", ")})") do |arg|
        types = arg.split(/, */).map(&.downcase)
        @options[:types] = [] of Symbol
        types.each do |t|
          next unless t =~ /^[cnfi]/
          @options[:types].as(Array(Symbol)) << case t[0]
                                               when 'c' then :changed
                                               when 'n' then :new
                                               when 'i' then :improved
                                               when 'f' then :fixed
                                               else :new
                                               end
        end
        @options[:types] = [:changed, :new, :improved, :fixed] if @options[:types].as(Array).empty?
      end
      parser.on("--file PATH", "File to read additional commit messages from") { |p| @options[:file] = p }
      parser.on("-s", "--select", "Choose 'since' tag") { @options[:select] = true }
      parser.on("--split", "Split output by version (use with --select)") { @options[:split] = true }
      parser.on("--order ORDER", "Order: asc or desc") do |o|
        @options[:order] = o.to_s.downcase[0]? == 'a' ? :asc : :desc
      end
      parser.on("-u FILE", "--update FILE", "Update changelog file") do |file|
        raise "Can't skip version check when updating" if @options[:no_version]?
        @options[:update] = file ? File.expand_path(file) : find_changelog
      end
      parser.on("-v VER", "--version=VER", "Force version") do |v|
        raise "Invalid version" unless v && v =~ /\d+\.\d+(\.\d+)?(\w+)?( *\([.\d]+\))?/
        @options[:version] = v
      end
      parser.on("-n", "--no_version", "Skip version check") do
        raise "Can't skip version when updating" if @options[:update]?
        @options[:no_version] = true
      end
      parser.on("-h", "--help", "Show help") { puts parser; exit }
    end

    if !@options[:format]?
      file = @options[:update]? || find_changelog
      if file
        fmt = detect_changelog_type(file.to_s)
        @options[:format] = fmt
        STDERR.puts "Parsed #{file}, detected format: #{fmt}"
      end
    end

    @app_title = args[0]? if args.size > 0

    if @options[:split]? && !@options[:select]? && !@options[:since_version]?
      STDERR.puts "--split requires --select or --since-version, ignoring"
      @options[:split] = false
    end

    cl = ChangeLogger.new(@app_title, @options)

    if @options[:copy]?
      Process.run("pbcopy", [] of String, input: IO::Memory.new(cl.to_s))
      STDERR.puts "Changelog in clipboard"
    elsif @options[:update]?
      update_changelog(@options[:update].to_s, cl.to_s, cl.version)
    else
      puts cl.to_s
    end
  end

  def find_changelog : String?
    # Prefer text changelog files, exclude executables and binary artifacts
    files = (Dir.glob("changelog*") + Dir.glob("CHANGELOG*")).uniq.reject do |f|
      File::Info.executable?(f) ||
        f.ends_with?(".dwarf") ||
        f.ends_with?(".o") ||
        f.ends_with?(".crystal")
    rescue
      false
    end
    # Prefer CHANGELOG.md, changelog.md, changelog, changelog.cr
    files.sort_by! do |f|
      case f.downcase
      when /changelog\.md$/ then 0
      when /changelog\.txt$/ then 1
      when /^changelog$/ then 2
      else 3
      end
    end
    files.any? ? files.first : nil
  end

  def detect_changelog_type(file : String) : Symbol
    content = File.read(File.expand_path(file)).strip
    return :keepachangelog if content.includes?("## [") && content.includes?("] - ")
    return :markdown if content =~ /^#+ \d+\.\d+/m
    return :bunch if content.includes?("{% icon ")
    return :def_list if content =~ /\d+\.\d+\.\d+.*\n:/m
    :markdown
  rescue
    :markdown
  end

  def update_changelog(file : String, changes : String, version : String?)
    return unless version
    fmt = detect_changelog_type(file)
    input = File.read(file)
    version_rx = version.gsub(".", "\\.")

    version_headers = [] of String
    case fmt
    when :keepachangelog then input.scan(/^## \[(\d+\.\d+\.\d+.*?)\]/) { |m| version_headers << m[0] }
    when :markdown      then input.scan(/^##+ +(\d+\.\d+\.\d+)/) { |m| version_headers << m[0] }
    when :def_list      then input.scan(/^(\d+\.\d+\.\d+)/) { |m| version_headers << m[0] }
    when :bunch         then input.scan(/^\{% available (\d+\.\d+\.\d+)/) { |m| version_headers << m[0] }
    end

    order = @options[:order]? || :desc
    if version_headers.size > 1
      cmp = compare_versions(version_headers[0], version_headers[1])
      order = cmp > 0 ? :desc : :asc
    end

    found_existing = case fmt
                     when :keepachangelog then input =~ /^## \[#{version_rx}\]( - .*?)? *$/m
                     when :markdown      then input =~ /^### #{version_rx}/
                     when :def_list      then input =~ /^#{version_rx}/
                     when :bunch         then input =~ /\{% available #{version_rx} %\}/
                     else false
                     end

    unless found_existing
      case fmt
      when :keepachangelog
        if order == :desc
          input = input.sub(/^(## \[\d+\.\d+)/m, "#{changes.strip}\n\n\\1")
        else
          input = input.sub(/^(\[\d+\.\d+.*?\]:)/m, "#{changes.strip}\n\n\\1")
        end
        input = ChangeLogger.add_keepachangelog_link_static(input, version)
      when :bunch
        input = input.sub(/\{% docdiff %\}/, "{% docdiff %}\n\n---\n\n#{changes.strip}\n")
      when :def_list
        input = input.sub(/^(\d+\.\d+\.\d+.*?\n+:)/, "#{changes.strip}\n\n\\1")
      else
        input = "#{changes.strip}\n\n#{input}"
      end
    end

    input = ChangeLogger.cleanup_keepachangelog_links(input, order.as(Symbol)) if fmt == :keepachangelog
    File.write(file, input)
  end
end

App.new(ARGV)
