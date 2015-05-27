require_relative 'testrail.rb'
require_relative 'properties.rb'
require 'json'
require 'logger'

module TestRailReporterWrapper

  class ReporterWrapper

    def initialize(test_plan_name, project_name = TR_PROJECT_NAME)
      @logger = Logger.new(STDOUT)
      @logger.level = Logger::INFO

      @client = TestRail::APIClient.new(TR_CLIENT)
      @client.user = TR_USER
      @client.password = TR_PASSWORD

      @runs = []
      @manual_runs = []
      @mem_runs_results = Hash.new
      @results = []

      @project_id = _get_project_id(project_name)
      @suite_id = _get_suite_id()

      @mem_sections = _load_sections()
      @mem_automated_cases = _load_cases(TR_CASE_TYPES[:AUTOMATED])
      @mem_manual_cases = _load_cases(TR_CASE_TYPES[:MANUAL], {:min_priority => 4})
      @mem_configs = _load_configurations()

      @milestone_id, milestone_name = _get_active_milestone

      #Create a test plan if he doesn't exist
      test_plan_name = test_plan_name + " - #{milestone_name}"
      @test_plan_id = _get_test_plan_id(test_plan_name, @milestone_id)
      if @test_plan_id.nil?
        @test_plan_id = _create_test_plan(test_plan_name, @milestone_id)
      end

      @mem_plan_info = _load_plan_info(@test_plan_id)
    end

    #
    # add_run
    #
    # This adds tests information of a certain run to mem
    #
    #
    #
    # parameters
    # Arguments:
    #
    # results               Test information
    #                       e.g.
    #                       {
    #                          {
    #                              :feature_name=>"<feature name A>",
    #                              :steps=>["<step A>", "<step B>", "<step C>"],
    #                              :status=>"<status>"
    #                          }
    #                          ...
    #                          {
    #                             :feature_name=>"<feature name B>",
    #                             :steps=>["<step A>", "<step B>", "<step C>"],
    #                             :status=>"<status>"
    #                          }
    #                       }
    #
    #
    # configuration         An array that indicates the current run configuration
    #                       e.g.
    #                       ["IOS 7", "iPas 2", "physical"]
    #
    #
    #
    def add_run(results, configuration)
      @logger.info("Adding run with configuration \"#{configuration.join(', ')}\"...")
      if configuration.nil? || configuration.count == 0
        raise SupportError.new('Invalid configuration parameter')
      end

      config_ids = get_config_ids(configuration)
      if config_ids.nil? || config_ids.count == 0
        raise SupportError.new('Any configuration matched')
      end

      test_ids = []
      test_results = Hash.new
      run = Hash.new

      if results.nil?
        @mem_manual_cases.each do |test_name, case_info|
          case_id = case_info['id']
          if !case_info.has_key?(TR_SYS_CONFIGS_TYPE) ||
              (case_info.has_key?(TR_SYS_CONFIGS_TYPE) && (config_ids == case_info[TR_SYS_CONFIGS_TYPE] || case_info[TR_SYS_CONFIGS_TYPE].count == 0))
            test_ids << case_id
            test_results[case_id] = TR_MEM_RESULT_STATUS[:UNTESTED]
          end
        end
        run['include_all'] = false
        run['config_ids'] = config_ids
        run['case_ids'] = test_ids
      else
        #add cases
        results.each do |test_name, test_info|
          case_info = _get_case_id(test_name)
          if case_info.nil?
            @logger.info("Adding case \"#{test_name}\"...")
            test_id = add_case(test_name, test_info[:feature_name], test_info[:steps])
          else
            test_id = case_info['id']
          end
          test_ids << test_id
          test_results[test_id] = test_info[:status]
        end
        run['include_all'] = false
        run['config_ids'] = config_ids
        run['case_ids'] = test_ids
      end

      run_info = Hash.new
      run_info[:case_results] = test_results
      run_info[:run_id] = nil
      @mem_runs_results[config_ids.join.to_s] = run_info

      @runs << run
    end

    def create_plan_entry(build_name)
      @logger.info("Creating plan entry  \"#{build_name}\"...")
      if build_name.nil? || build_name.size == 0
        raise SupportError.new('Invalid build name')
      end

      if @runs.count == 0
        raise SupportError.new('Any Run found!')
      end

      #Add a entry for the current Test Plan
      run_prop = Hash.new
      run_prop['name'] = build_name
      run_prop['suite_id'] = @suite_id
      run_prop['include_all'] = true
      run_prop['config_ids'] = _get_all_config_ids
      run_prop['runs'] = @runs

      entry_exists, entry_info = _check_if_entry_exists?(build_name)
      if !entry_exists
        begin
          entry_info = @client.send_post("add_plan_entry/#{@test_plan_id}", run_prop)
        rescue TestRail::APIError => e
          raise SupportError.new(e.to_s)
        end
      end
      _add_run_id_to_runs_results(entry_info)
    end

    def delete_plan_entry(build_name)
      @logger.info("Deleting plan entry  \"#{build_name}\"...")
      if build_name.nil? || build_name.size == 0
        raise SupportError.new('Invalid build name')
      end

      entry_exists, entry_info = _check_if_entry_exists?(build_name)
      if entry_exists
        entry_id = entry_info['id']
        begin
          @client.send_post("delete_plan_entry/#{@test_plan_id}/#{entry_id}", nil)
        rescue TestRail::APIError => e
          raise SupportError.new(e.to_s)
        end
      end

      _delete_entry_from_mem(build_name)
    end

    def set_results
      @mem_runs_results.each do |run_config_id, run_result|
        tests = _get_tests(run_result[:run_id])
        _clear_test_results
        tests.each do |test|
          #in some cases, like re-run, we only want to update some test cases
          if run_result[:case_results].has_key?(test['case_id'])
            _add_test_result(test['id'], run_result[:case_results][test['case_id']])
          end
        end
        _set_results(run_result[:run_id])
      end
    end

    def get_results(run_name)
      mem_loaded_runs_results = Hash.new
      plan_id = _get_test_plan_id(run_name, @milestone_id)
      plan_info = _load_plan_info(plan_id)
      runs = _get_runs_from_plan_info(plan_info)
      runs.each do |run|
        run_results = _get_results_from_run(run['id'])
        results = Hash.new
        run_results.each do |result|
          test_id, result = _get_test_result(result['test_id'])
          results[test_id] = result
        end
        mem_loaded_runs_results[run['config_ids'].sort.join(',')] = results
      end
      mem_loaded_runs_results
    end

    def add_case(title, section_name, case_steps)
      if !_section_exists?(section_name)
        _add_section(section_name)
        section_id = _get_section_id(section_name)
      else
        section_id =_get_section_id(section_name)
      end

      _add_case(title, section_id, case_steps)
    end

    def get_config_ids(configuration)
      #this transforms Configuration names in TestRail configuration ID's
      config_ids = []

      configuration.each do |cfg|
        if @mem_configs.has_key?(cfg)
          config_ids << @mem_configs[cfg]
        else
          Raise SupportError.new("Configuration \"#{cfg}\" not founs in testrail project configuration")
        end
      end
      config_ids.sort
    end

    private

    def _load_sections()
      mem_sections = Hash.new
      begin
        sections = @client.send_get("get_sections/#{@project_id}&suite_id=1")
      rescue TestRail::APIError => e
        raise SupportError.new(e.to_s)
      end
      sections.each do |section|
        mem_sections[section['name']] = section['id']
      end
      mem_sections
    end

    def _load_configurations()
      begin
        configurations_groups = @client.send_get("get_configs/#{@project_id}")
      rescue TestRail::APIError => e
        raise SupportError.new(e.to_s)
      end

      if configurations_groups.nil? || configurations_groups.count == 0
        raise SupportError.new('Any configuration found in Test Rail')
      end

      configurations = Hash.new

      configurations_groups.each do |group|
        configuration = group['configs']
        configuration.each do |prop|
          configurations[prop['name']] = prop['id']
        end
      end
      configurations
    end

    def _get_project_id(project_name)
      begin
        projects = @client.send_get('get_projects')
      rescue TestRail::APIError => e
        raise SupportError.new(e.to_s)
      end

      project_id = nil
      projects.each do |project|
        if project.key(project_name).eql? 'name'
          project_id = project['id']
          break
        end
      end

      if project_id.nil?
        raise SupportError.new('Project not found')
      end
      project_id
    end

    def _get_runs_from_plan_info(plan_info)
      runs = []
      plan_info['entries'].each do |entry|
        entry['runs'].each do |run|
          runs << {"id" => run['id'], "config_ids" => run['config_ids']}
        end
      end
      runs
    end

    def _get_results_from_run(run_id)
      @client.send_get("get_results_for_run/#{run_id}")
    end

    def _get_test_result(test_id)
      test = @client.send_get("get_test/#{test_id}")
      return test['test_id'], test['status']
    end

    def _get_suite_id()
      suites = @client.send_get("get_suites/#{@project_id}")
      suites[0]['id']
    end

    def _get_result_status(status)
      status.upcase!
      if TR_MEM_RESULT_STATUS.has_key?(status.to_sym)
        TR_MEM_RESULT_STATUS[status.to_sym]
      else
        #TODO - In Testrail, it must be created a unknown status
        -1
      end
    end

    def _load_plan_info(plan_id)
      begin
        @mem_plan_info = @client.send_get("get_plan/#{plan_id}")
      rescue TestRail::APIError => e
        raise SupportError.new(e.to_s)
      end
    end

    def _load_cases(type, options = {})
      min_priority = options[:min_priority].nil? ? 1 : options[:min_priority]
      mem_cases = Hash.new
      begin
        cases = @client.send_get("get_cases/#{@project_id}&type_id=#{type}")
      rescue TestRail::APIError => e
        raise SupportError.new(e.to_s)
      end
      cases.each do |tr_case|
        if tr_case['priority_id'] >= min_priority
          case_props = Hash.new
          case_props['id'] = tr_case['id']
          if tr_case.has_key? TR_SYS_CONFIGS_TYPE
            case_props[TR_SYS_CONFIGS_TYPE] = tr_case[TR_SYS_CONFIGS_TYPE].sort
          end
          mem_cases[tr_case['title']] = case_props
        end
      end
      mem_cases
    end

    def _get_all_config_ids
      configs = []
      @mem_configs.each do |config|
        configs << config[1]
      end
    end

    def _case_exists?(title)
      @mem_automated_cases.has_key?(title)
    end

    def _get_case_id(title)
      @mem_automated_cases[title]
    end

    def _section_exists?(section)
      @mem_sections.has_key?(section)
    end

    def _add_section(name)
      section_prop = Hash.new
      section_prop['name'] = name
      begin
        section = @client.send_post("add_section/#{@project_id}", section_prop)
      rescue TestRail::APIError => e
        raise SupportError.new(e.to_s)
      end
      @mem_sections[section['name']] = section['id']
    end

    def _get_test_plan_id(name, milestone_id)
      plan_id = nil

      begin
      plans = @client.send_get("get_plans/#{@project_id}&is_completed=0&milestone_id=#{milestone_id}")
      rescue TestRail::APIError => e
        raise SupportError.new(e.to_s)
      end

      plans.each do |plan|
        if plan.key(name).eql? 'name'
          plan_id = plan['id']
          break
        end
      end
      plan_id
    end

    def _check_if_entry_exists?(build_name)
      entry_found = false
      entry_info = Hash.new
      @mem_plan_info['entries'].each do |entry|
        if entry.key(build_name).eql?('name')
          entry_found = true
          entry_info = entry
          break
        end
      end
      return entry_found, entry_info
    end

    def _delete_entry_from_mem(build_name)
      #@mem_plan_info['entries'].each do |entry|
      #  entry.delete_if{|build| build.has_value?(build_name)}
      #end

      @mem_plan_info['entries'].delete_if{|build| build.has_value?(build_name)}
    end

    def _add_run_id_to_runs_results(entry_info)
      entry_info['runs'].each do |run|
        generated_id_config = run['config_ids'].sort.join.to_s
        if !@mem_runs_results.has_key?(generated_id_config)
          raise SupportError.new("Report configuration runs doesn't mach with the persisted #{generated_id_config}")
        end
        @mem_runs_results[generated_id_config][:run_id] = run['id']
      end
    end

    def _get_section_id(section_name)
      @mem_sections[section_name]
    end

    def _add_case(title, section_id, case_steps)
      case_props = Hash.new
      case_props['title'] = title
      case_props['type_id'] = TR_CASE_TYPES['AUTOMATED'.to_sym]
      case_props['custom_steps'] = case_steps.join("\n")

      begin
        new_case = @client.send_post("add_case/#{section_id}", case_props)
      rescue TestRail::APIError => e
        raise SupportError.new("#{e.to_s} - \nSection: #{section_id}\nProperties #{case_props.to_s}")
      end

      case_props = Hash.new
      case_props['id'] = new_case['id']

      @mem_automated_cases[title] = case_props
      new_case['id']
    end

    def _get_active_milestone
      begin
        active_milestones = @client.send_get("get_milestones/#{@project_id}&is_completed=0")
      rescue TestRail::APIError => e
        raise SupportError.new(e.to_s)
      end

      if active_milestones.count > 1
        raise SupportError.new('More than one milestone active!')
      end

      return active_milestones[0]['id'] , active_milestones[0]['name']
    end

    def _create_test_plan(name, milestone_id)
      if @project_id.nil?
        raise SupportError.new('Project not found')
      end

      plan_prop = Hash.new
      plan_prop['name'] = name
      #TODO - change this description
      plan_prop['description'] = 'change me'
      plan_prop['milestone_id'] = milestone_id

      begin
        plan = @client.send_post("add_plan/#{@project_id}", plan_prop)
      rescue TestRail::APIError => e
        raise SupportError.new(e.to_s)
      end

      plan['id']
    end

    def _set_results(run_id)
      results = Hash.new
      results['results'] = @results

      begin
        @client.send_post("add_results/#{run_id}", results)
      rescue TestRail::APIError => e
        raise SupportError.new(e.to_s)
      end
    end

    def _clear_test_results
      @results = []
    end

    def _add_test_result(test_id, result)
      result_config = Hash.new
      result_config['test_id'] = test_id
      result_config['status_id'] = _get_result_status(result)
      @results << result_config
    end

    def _get_tests(run_id)
      begin
        @client.send_get("get_tests/#{run_id}")
      rescue TestRail::APIError => e
        raise SupportError.new(e.to_s)
      end
    end

    def _check_section_exists?(name)
      section_found = false

      begin
        sections = @client.send_get("get_sections/#{@project_id}&suite_id=#{@suite_id}")
      rescue TestRail::APIError => e
        raise SupportError.new(e.to_s)
      end

      sections.each do |section|
        if section.key(name).eql? 'name'
          section_found = true
          break
        end
      end
      section_found
    end
  end

  class Results
    CUCUMBER_SUCCESS = 'passed'

    def initialize(file_name)
      begin
        @file = File.read(file_name)
      rescue Errno::ENOENT
        raise SupportError.new('File not found')
      ensure
        @file.close
      end
    end

    # Any parser must return the following hash:
    # {
    #    {
    #        :feature_name=>"<feature name A>",
    #        :steps=>["<step A>", "<step B>", "<step C>"],
    #        :status=>"<status>"
    #    }
    #    ...
    #    {
    #       :feature_name=>"<feature name B>",
    #       :steps=>["<step A>", "<step B>", "<step C>"],
    #       :status=>"<status>"
    #    }
    # }


    # Please use the following project to have results in scenarios outlines:
    # https://gist.github.com/blt04/9866357

    def cucumber_parse
      previous_scenario_name = nil
      scenario_outline_number = 0

      begin
        results = JSON.parse(@file)
      rescue JSON::ParserError
        raise SupportError.new('Error parsing file')
      end

      test_results = Hash.new
      results.each do |feature_results|
        if feature_results.has_key?('elements')
          feature_results['elements'].each do |scenarios|
            if !scenarios['type'].eql?('background')
              case_steps = []
              status = nil
              scenario_name = scenarios['name']

              if scenarios['type'].eql?('scenario_outline')
                if !previous_scenario_name.eql?(scenario_name)
                  scenario_outline_number = 0
                end
                previous_scenario_name = scenario_name
                scenario_outline_number += 1
                scenario_name = scenario_name + " \##{scenario_outline_number}"
              end

              #get scenario result
              if scenarios.has_key?('steps')
                scenarios['steps'].each do |steps|
                  status = steps['result']['status']
                  case_steps << "**#{steps['keyword']}** #{steps['name']}"
                  if !status.eql?(CUCUMBER_SUCCESS)
                    break
                  end
                end
                test_info = Hash.new
                test_info[:feature_name] = feature_results['name']
                test_info[:steps] = case_steps
                test_info[:status] = status
              end
              test_results[scenario_name] = test_info
            end
          end
        end
      end
      test_results
    end

    def self.merge_results(original_results, results_to_merge)
      results_to_merge.each do |test_name, test_info|
        original_results[test_name][:status] = test_info[:status]
      end
      original_results
    end
  end

  class SupportError < StandardError
  end
end