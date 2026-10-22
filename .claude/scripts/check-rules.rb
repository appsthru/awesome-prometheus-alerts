#!/usr/bin/env ruby
# Renders _data/rules.yml through dist/template.yml exactly like .github/workflows/test.yml
# (one file per exporter under test/rules/<service>/<slug>.yml), then runs `promtool check rules`.
# Usage: ruby .claude/scripts/check-rules.rb [slug ...]   (no argument = every exporter)
require "yaml"
require "json"
require "liquid"
require "fileutils"

root = File.expand_path("../..", __dir__)
only = ARGV
template = Liquid::Template.parse(File.read(File.join(root, "dist/template.yml")))
# Round-trip through JSON so Liquid sees the same plain hashes as the CI (yq -o json | liquid).
data = JSON.parse(JSON.generate(YAML.safe_load_file(File.join(root, "_data/rules.yml"))))

out_dir = File.join(root, "test/rules")
FileUtils.rm_rf(out_dir)
files = []
data["groups"].each do |group|
  group["services"].each do |service|
    subdir = File.join(out_dir, service["name"].downcase.split(" ").join("-"))
    service["exporters"].each do |exporter|
      next unless only.empty? || only.include?(exporter["slug"])
      FileUtils.mkdir_p(subdir)
      path = File.join(subdir, "#{exporter["slug"]}.yml")
      File.write(path, template.render(exporter))
      files << path
    end
  end
end
abort "No exporter matches: #{only.join(", ")}" if files.empty?

# Rendering alone already proves the YAML loads and the template applies; without promtool, stop there.
unless system("promtool", "--version", out: File::NULL, err: File::NULL)
  warn "WARNING: promtool not found, skipped `promtool check rules` (#{files.size} file(s) rendered in test/rules/)."
  exit 0
end

ok = system("promtool", "check", "rules", *files, out: File::NULL)
# Re-run verbosely only when something failed, so a green run stays short.
system("promtool", "check", "rules", *files) unless ok
puts "promtool: #{files.size} rule file(s) #{ok ? "OK" : "FAILED"}"
exit(ok ? 0 : 1)
