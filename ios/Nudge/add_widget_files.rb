#!/usr/bin/env ruby
# Adds the new widget source files to the NudgeWidgets target.
require 'xcodeproj'

PROJ = File.join(__dir__, 'Nudge.xcodeproj')
project = Xcodeproj::Project.open(PROJ)
ext = project.targets.find { |t| t.name == 'NudgeWidgets' } or abort 'NudgeWidgets target not found'
group = project.main_group['NudgeWidgets'] or abort 'NudgeWidgets group not found'

existing = ext.source_build_phase.files_references.map { |r| r.path }
%w[WidgetData.swift NudgeWidgets.swift].each do |f|
  next if existing.include?(f)
  ref = group.new_reference(f)
  ext.source_build_phase.add_file_reference(ref)
  puts "added #{f}"
end

project.save
puts "NudgeWidgets sources: " + ext.source_build_phase.files_references.map(&:path).join(', ')
