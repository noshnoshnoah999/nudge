#!/usr/bin/env ruby
# Adds the NudgeWidgets app-extension target (Control Center control) to the
# Nudge Xcode project, wires shared sources into both targets, and embeds the
# extension into the app. Idempotent-ish: bails if the target already exists.

require 'xcodeproj'

PROJ = File.join(__dir__, 'Nudge.xcodeproj')
TEAM = 'FMF6YAVA23'
EXT_NAME = 'NudgeWidgets'
EXT_BUNDLE = 'uk.flouty.Nudge.NudgeWidgets'
DEPLOY = '26.5'

project = Xcodeproj::Project.open(PROJ)
app = project.targets.find { |t| t.name == 'Nudge' } or abort 'app target not found'
abort "#{EXT_NAME} already exists" if project.targets.any? { |t| t.name == EXT_NAME }

ext = project.new_target(:app_extension, EXT_NAME, :ios, DEPLOY, nil, :swift)

ext.build_configurations.each do |c|
  bs = c.build_settings
  bs['PRODUCT_BUNDLE_IDENTIFIER'] = EXT_BUNDLE
  bs['PRODUCT_NAME'] = '$(TARGET_NAME)'
  bs['GENERATE_INFOPLIST_FILE'] = 'NO'
  bs['INFOPLIST_FILE'] = "#{EXT_NAME}/Info.plist"
  bs['DEVELOPMENT_TEAM'] = TEAM
  bs['CODE_SIGN_STYLE'] = 'Automatic'
  bs['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOY
  bs['SWIFT_VERSION'] = '5.0'
  bs['SWIFT_DEFAULT_ACTOR_ISOLATION'] = 'MainActor'
  bs['TARGETED_DEVICE_FAMILY'] = '1,2'
  bs['SKIP_INSTALL'] = 'YES'
  bs['CLANG_ENABLE_MODULES'] = 'YES'
  bs['ENABLE_PREVIEWS'] = 'YES'
  bs['MARKETING_VERSION'] = '1.0'
  bs['CURRENT_PROJECT_VERSION'] = '1'
  bs['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
  bs['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks',
                                   '@executable_path/../../Frameworks']
  bs['SWIFT_OPTIMIZATION_LEVEL'] = '-Onone' if c.name == 'Debug'
end

# Groups + file references
ext_group = project.main_group.new_group(EXT_NAME, EXT_NAME)
shared_group = project.main_group.new_group('Shared', 'Shared')

control_ref = ext_group.new_reference('NudgeControl.swift')
ext_group.new_reference('Info.plist')
shared_router = shared_group.new_reference('AppRouter.swift')
shared_intent = shared_group.new_reference('QuickAddIntent.swift')

# Sources: extension gets control + both shared files; app gets both shared files.
ext.source_build_phase.add_file_reference(control_ref)
[shared_router, shared_intent].each do |r|
  ext.source_build_phase.add_file_reference(r)
  app.source_build_phase.add_file_reference(r)
end

# Embed the extension into the app + depend on it.
app.add_dependency(ext)
embed = app.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
embed.dst_path = ''
bf = embed.add_file_reference(ext.product_reference, true)
bf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

project.save
puts "Added target #{EXT_NAME} (#{EXT_BUNDLE}); targets now: #{project.targets.map(&:name).join(', ')}"
