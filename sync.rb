#!/usr/bin/env ruby

require 'optparse'
require 'pathname'
require 'digest'

FINGERPRINTS_FILENAME = '.syncrb.fingerprints'
FINGERPRINTS_BACKUP_FILENAME = '.syncrb.fingerprints.bak'

def main
  options = {}
  OptionParser.new do |parser|
    parser.banner = 'Usage: sync.rb [command] [options]'

    parser.on('-v', '--verbose')
    parser.on('-n', '--dry-run')
    parser.on('-s', '--source-dir SOURCE_DIR')
    parser.on('-d', '--dest-dir DESTINATION_DIR')
  end.parse!(into: options)

  command = ARGV.first

  case command
  when 'fingerprint'
    abort 'Error: Specify dir to fingerprint with `--source-dir`' unless options[:'source-dir']
    warn 'Warning: `--dest-dir` is ignored when fingerprinting' if options[:'dest-dir']

    reindex options[:'source-dir']
  when 'verify'
    abort 'Error: Specify dir to verify integrity of with `--source-dir`' unless options[:'source-dir']
    warn 'Warning: `--dest-dir` is ignored when verifying' if options[:'dest-dir']

    verify options[:'source-dir']
  else
    abort "Invalid command: `#{command}`"
  end
end

def reindex(dir_path)
  dir_path = Pathname.new dir_path
  reindex_recursive dir_path, dir_path, fingerprints_file_in(dir_path, create: true)
  puts
end

def reindex_recursive(root_path, current_path, fingerprints_file)
  children = current_path.children
  sorted_children = children.sort.partition(&:directory?).flatten

  sorted_children.each do |child_path|
    next if [FINGERPRINTS_FILENAME, FINGERPRINTS_BACKUP_FILENAME].include?(child_path.basename.to_s)

    if child_path.directory?
      reindex_recursive root_path, child_path, fingerprints_file
    else
      print '.'
      fingerprints_file.puts "#{file_sha1 child_path} #{child_path.relative_path_from root_path}"
    end
  end
end

def verify(dir_path)
  dir_path = Pathname.new dir_path
  fingerprints_file = fingerprints_file_in dir_path
  abort "Error: Cannot verify files in `#{dir_path}`, no fingerprints file found" unless fingerprints_file

  sha1_len = 40
  fingerprints = {}
  fingerprints_file.each_line do |line|
    line.strip!
    hash = line[0..(sha1_len - 1)]
    relative_path = line[(sha1_len + 1)..]
    fingerprints[relative_path] = hash
  end

  changed_hashes = {}
  fingerprints.each do |relative_path, recorded_hash|
    current_hash = file_sha1(dir_path + relative_path)
    changed_hashes[relative_path] = current_hash if current_hash != recorded_hash
    print(current_hash == recorded_hash ? '.' : 'F')
  end
  puts "\n\n"

  if changed_hashes.empty?
    puts 'All files are OK'
  else
    puts 'CORRUPTED FILES FOUND:'
    changed_hashes.each do |corrupted_file, new_hash|
      puts "#{corrupted_file}  (New hash: #{new_hash})"
    end
  end
end

def file_sha1(file_path)
  @sha1_digestor ||= Digest::SHA1.new
  file = File.open file_path, 'rb'

  @sha1_digestor.reset
  while (file_chunk = file.read(4 * 1024 * 1024))
    @sha1_digestor << file_chunk
  end
  @sha1_digestor.hexdigest
end

def fingerprints_file_in(dir_path, create: false)
  file_path = dir_path + FINGERPRINTS_FILENAME

  if create
    if file_path.exist? && file_path.directory?
      abort "Error: Cannot create fingerprints file `#{file_path}`, a directory with the same path exists"
    end
    if file_path.exist?
      warn "Warning: Fingerprints file `#{file_path}` exists, creating backup"
      File.rename file_path, dir_path + FINGERPRINTS_BACKUP_FILENAME
    end

    File.new file_path, 'w'
  else
    return nil unless file_path.exist?

    File.open file_path, 'r'
  end
end

main
