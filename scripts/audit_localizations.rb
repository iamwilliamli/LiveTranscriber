#!/usr/bin/env ruby

require "json"
require "open3"

ROOT = File.expand_path("..", __dir__)
LOCALES = %w[de en ja nl zh-Hans zh-Hant].freeze

errors = []

def placeholder_signature(value)
  value.to_s.scan(/%(?:\d+\$)?(?:\.\d+)?(?:ll)?[@a-zA-Z%]/).sort
end

def load_strings_file(path)
  stdout, status = Open3.capture2("plutil", "-convert", "json", "-o", "-", path)
  raise "Could not parse #{path}" unless status.success?
  JSON.parse(stdout)
end

catalog_paths = [
  "LiveTranscriber/ControlCenter.xcstrings",
  "SharedApp/AudioEvents.xcstrings",
  "SharedApp/Semantic.xcstrings"
]

catalog_paths.each do |relative_path|
  path = File.join(ROOT, relative_path)
  catalog = JSON.parse(File.read(path))
  catalog.fetch("strings").each do |key, entry|
    localizations = entry["localizations"] || {}
    missing = LOCALES - localizations.keys
    errors << "#{relative_path}: #{key} is missing #{missing.join(', ')}" unless missing.empty?

    reference_value = localizations.dig("en", "stringUnit", "value")
    reference_signature = placeholder_signature(reference_value)
    LOCALES.each do |locale|
      unit = localizations.dig(locale, "stringUnit")
      next unless unit
      errors << "#{relative_path}: #{key} [#{locale}] is #{unit['state'].inspect}" unless unit["state"] == "translated"
      errors << "#{relative_path}: #{key} [#{locale}] is empty" if unit["value"].to_s.empty?
      signature = placeholder_signature(unit["value"])
      if reference_value && signature != reference_signature
        errors << "#{relative_path}: #{key} [#{locale}] placeholders #{signature.inspect} do not match English #{reference_signature.inspect}"
      end
    end
  end
end

semantic_path = File.join(ROOT, "SharedApp/Semantic.xcstrings")
semantic_keys = JSON.parse(File.read(semantic_path)).fetch("strings").keys
l10n_source = File.read(File.join(ROOT, "SharedApp/L10n.swift"))
declared_semantic_keys = l10n_source.scan(/L10n\.resource\(\s*"([^"]+)"/m).flatten.uniq
(declared_semantic_keys - semantic_keys).sort.each do |key|
  errors << "SharedApp/L10n.swift: #{key} is missing from Semantic.xcstrings"
end

mac_l10n_source = File.read(File.join(ROOT, "LiveTranscriberMac/Sources/MacL10n.swift"))
declared_mac_keys = mac_l10n_source.scan(/resource\(\s*"([^"]+)"/m).flatten.uniq.sort
mac_tables = LOCALES.to_h do |locale|
  relative_path = "LiveTranscriberMac/Resources/#{locale}.lproj/MacSemantic.strings"
  [locale, load_strings_file(File.join(ROOT, relative_path))]
end
mac_tables.each do |locale, table|
  missing = declared_mac_keys - table.keys
  extra = table.keys - declared_mac_keys
  errors << "MacSemantic [#{locale}] missing: #{missing.sort.join(', ')}" unless missing.empty?
  errors << "MacSemantic [#{locale}] undeclared: #{extra.sort.join(', ')}" unless extra.empty?
  table.each do |key, value|
    errors << "MacSemantic [#{locale}] #{key} is empty" if value.to_s.empty?
    english_signature = placeholder_signature(mac_tables.fetch("en")[key])
    signature = placeholder_signature(value)
    if signature != english_signature
      errors << "MacSemantic [#{locale}] #{key} placeholders #{signature.inspect} do not match English #{english_signature.inspect}"
    end
  end
end

localized_file_groups = [
  ["LiveTranscriber", "InfoPlist.strings"],
  ["LiveTranscriber", "AppShortcuts.strings"],
  ["LiveTranscriberWidget", "InfoPlist.strings"],
  ["LiveTranscriberBroadcastExtension", "InfoPlist.strings"],
  ["LiveTranscriberMac/Resources", "InfoPlist.strings"]
]

localized_file_groups.each do |directory, filename|
  tables = {}
  LOCALES.each do |locale|
    relative_path = "#{directory}/#{locale}.lproj/#{filename}"
    path = File.join(ROOT, relative_path)
    if File.exist?(path)
      tables[locale] = load_strings_file(path)
    else
      errors << "Missing localized file #{relative_path}"
    end
  end
  next unless tables.key?("en")
  reference_keys = tables.fetch("en").keys.sort
  tables.each do |locale, table|
    missing = reference_keys - table.keys
    extra = table.keys - reference_keys
    errors << "#{directory}/#{filename} [#{locale}] missing: #{missing.join(', ')}" unless missing.empty?
    errors << "#{directory}/#{filename} [#{locale}] extra: #{extra.join(', ')}" unless extra.empty?
    table.each do |key, value|
      errors << "#{directory}/#{filename} [#{locale}] #{key} is empty" if value.to_s.empty?
    end
  end
end

if errors.empty?
  puts "Localization audit passed: all six locales are complete."
  exit 0
end

warn errors.join("\n")
exit 1
