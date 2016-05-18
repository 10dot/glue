require 'pipeline/tasks/base_task'
require 'pipeline/util'

class Pipeline::NodeSecurityProject < Pipeline::BaseTask

  Pipeline::Tasks.add self
  include Pipeline::Util

  def initialize(trigger, tracker)
    super(trigger, tracker)
    @name = "NodeSecurityProject"
    @description = "Node Security Project"
    @stage = :code
    @labels << "code"
    @results = []
  end

  def run
    exclude_dirs = ['node_modules','bower_components']
    exclude_dirs = exclude_dirs.concat(@tracker.options[:exclude_dirs]).uniq if @tracker.options[:exclude_dirs]
    directories_with?('package.json', exclude_dirs).each do |dir|
      Pipeline.notify "#{@name} scanning: #{dir}"
      Dir.chdir(dir) do
        res = runsystem(true, "nsp", "check", "--output", "json")
        @results << JSON.parse(res)
      end
    end
  end

  def analyze
    begin
      @results.each do |dir_result|
        # This block iterates through each package name found and selects the unique nsp advisories
        # regardless of version, and builds a pipeline finding hash for each unique package/advisory combo.
        dir_result.uniq {|finding| finding['module']}.each do |package|
          dir_result.select {|f| f['module'] == package['module']}.uniq {|m| m['advisory']}.each do |unique_finding|
            description = "#{unique_finding['module']} - #{unique_finding['title']}"
            detail = "Upgrade to versions: #{unique_finding['patched_versions']}\n#{unique_finding['advisory']}"
            source = {
              :scanner => 'NodeSecurityProject',
              :file => "#{unique_finding['module']} - #{unique_finding['vulnerable_versions']}",
              :line => nil,
              :code => nil
            }
            report description, detail, source, 'medium', fingerprint("#{description}#{detail}#{source}")
          end
        end
      end
    rescue Exception => e
      Pipeline.warn e.message
      Pipeline.warn e.backtrace
    end
  end

  def supported?
    supported=runsystem(true, "nsp", "--version")
    if supported =~ /command not found/
      Pipeline.notify "Install nodesecurity: 'npm install -g nsp'"
      return false
    else
      return true
    end
  end

end
