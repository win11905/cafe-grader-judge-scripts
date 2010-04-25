require 'fileutils'
require File.join(File.dirname(__FILE__),'dir_init')

module Grader

  #
  # A grader engine grades a submission, against anything: a test
  # data, or a user submitted test data.  It uses two helpers objects:
  # room_maker and reporter.
  #
  class Engine
    
    attr_writer :room_maker
    attr_writer :reporter

    def initialize(options={})
      # default options
      if not options.include? :room_maker
        options[:room_maker] = Grader::SubmissionRoomMaker.new
      end
      if not options.include? :reporter
        options[:reporter] =  Grader::SubmissionReporter.new
      end

      @config = Grader::Configuration.get_instance

      @room_maker = options[:room_maker]
      @reporter = options[:reporter]
    end
    
    # takes a submission, asks room_maker to produce grading directories,
    # calls grader scripts, and asks reporter to save the result
    def grade(submission)
      current_dir = FileUtils.pwd

      user = submission.user
      problem = submission.problem

      # TODO: will have to create real exception for this
      if user==nil or problem == nil
        @reporter.report_error(submission,"Grading error: problem with submission")
        #raise "engine: user or problem is nil"
      end

      # TODO: this is another hack so that output only task can be judged
      if submission.language!=nil
        language = submission.language.name
        lang_ext = submission.language.ext
      else
        language = 'c'
        lang_ext = 'c'
      end

      # FIX THIS
      talk 'some hack on language'
      if language == 'cpp'
        language = 'c++'
      end

      # COMMENT: should it be only source.ext?
      if problem!=nil
        source_name = "#{problem.name}.#{lang_ext}"
      else
        source_name = "source.#{lang_ext}"
      end

      begin
        grading_dir = @room_maker.produce_grading_room(submission)
        @room_maker.save_source(submission,source_name)
        problem_home = @room_maker.find_problem_home(submission)

        # puts "GRADING DIR: #{grading_dir}"
        # puts "PROBLEM DIR: #{problem_home}"

        if !FileTest.exist?(problem_home)
          raise "No test data."
        end

        dinit = DirInit::Manager.new(problem_home)

        dinit.setup do
          copy_log = copy_script(problem_home)
          save_copy_log(problem_home,copy_log)
        end
      
        call_judge(problem_home,language,grading_dir,source_name)

        @reporter.report(submission,"#{grading_dir}/test-result")

        dinit.teardown do
          copy_log = load_copy_log(problem_home)
          clear_copy_log(problem_home)
          clear_script(copy_log,problem_home)
        end

      rescue RuntimeError => msg
        @reporter.report_error(submission, msg)

      ensure
        @room_maker.clean_up(submission)
        Dir.chdir(current_dir)   # this is really important
      end
    end
    
    protected
    
    def talk(str)
      if @config.talkative
        puts str
      end
    end

    def call_judge(problem_home,language,grading_dir,fname)
      ENV['PROBLEM_HOME'] = problem_home
      
      talk grading_dir
      Dir.chdir grading_dir
      cmd = "#{problem_home}/script/judge #{language} #{fname}"
      talk "CMD: #{cmd}"
      system(cmd)
    end

    def get_std_script_dir
      GRADER_ROOT + '/std-script'
    end

    def copy_script(problem_home)
      script_dir = "#{problem_home}/script"
      std_script_dir = get_std_script_dir

      raise "std-script directory not found" if !FileTest.exist?(std_script_dir)

      scripts = Dir[std_script_dir + '/*']
      
      copied = []

      scripts.each do |s|
        fname = File.basename(s)
        next if FileTest.directory?(s)
        if !FileTest.exist?("#{script_dir}/#{fname}")
          copied << fname
          FileUtils.cp(s, "#{script_dir}")
        end
      end
      
      return copied
    end

    def copy_log_filename(problem_home)
      return File.join(problem_home, '.scripts_copied')
    end

    def save_copy_log(problem_home, log)
      f = File.new(copy_log_filename(problem_home),"w")
      log.each do |fname|
        f.write("#{fname}\n")
      end
      f.close
    end
    
    def load_copy_log(problem_home)
      f = File.new(copy_log_filename(problem_home),"r")
      log = []
      f.readlines.each do |line|
        log << line.strip
      end
      f.close
      log
    end

    def clear_copy_log(problem_home)
      File.delete(copy_log_filename(problem_home))
    end

    def clear_script(log,problem_home)
      log.each do |s|
        FileUtils.rm("#{problem_home}/script/#{s}")
      end
    end

    def mkdir_if_does_not_exist(dirname)
      Dir.mkdir(dirname) if !FileTest.exist?(dirname)
    end
    
  end
  
end
