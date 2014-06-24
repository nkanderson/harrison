module Harrison
  class Package < Base
    def initialize(opts={})
      # Config helpers for Harrisonfile.
      self.class.option_helper(:host)
      self.class.option_helper(:commit)
      self.class.option_helper(:purge)
      self.class.option_helper(:pkg_dir)
      self.class.option_helper(:remote_dir)
      self.class.option_helper(:exclude)

      # Command line opts for this action. Will be merged with common opts.
      arg_opts = [
        [ :commit, "Specific commit to be packaged. Accepts anything that `git rev-parse` understands.", :type => :string, :default => "HEAD" ],
        [ :purge, "Remove all previously packaged commits and working copies from the build host when finished.", :type => :boolean, :default => false ],
        [ :pkg_dir, "Local folder to save package to.", :type => :string, :default => "pkg" ],
        [ :remote_dir, "Remote working folder.", :type => :string, :default => "~/.harrison" ],
      ]

      super(arg_opts, opts)
    end

    def remote_exec(cmd)
      ensure_remote_dir(self.host, "#{remote_project_dir}/package")

      super("cd #{remote_project_dir}/package && #{cmd}")
    end

    def run(&block)
      return super if block_given?

      # Resolve commit ref to an actual short SHA.
      resolve_commit!

      puts "Packaging #{commit} for \"#{project}\" on #{host}..."

      # Make sure the folder to save the artifact to locally exists.
      ensure_local_dir(pkg_dir)

      # Fetch/clone git repo on remote host.
      remote_exec("if [ -d cached ] ; then cd cached && git fetch origin -p ; else git clone #{git_src} cached ; fi")

      # Check out target commit.
      remote_exec("cd cached && git reset --hard #{commit} && git clean -f -d")

      # Make a build folder of the target commit.
      remote_exec("rm -rf #{commit} && cp -a cached #{commit}")

      # Run user supplied build code.
      # TODO: alter remote_exec to set directory context to commit dir?
      super

      # Package build folder into tgz.
      remote_exec("rm -f #{artifact_name(commit)}.tar.gz && cd #{commit} && tar #{excludes_for_tar} -czf ../#{artifact_name(commit)}.tar.gz .")

      # Download (Expand remote path since Net::SCP doesn't expand ~)
      download(remote_exec("readlink -m #{artifact_name(commit)}.tar.gz"), "#{pkg_dir}/#{artifact_name(commit)}.tar.gz")

      if purge
        remote_exec("cd .. && rm -rf package")
      end

      puts "Sucessfully packaged #{commit} to #{pkg_dir}/#{artifact_name(commit)}.tar.gz"
    end

    protected

    def remote_project_dir
      "#{remote_dir}/#{project}"
    end

    def resolve_commit!
      self.commit = exec("git rev-parse --short #{self.commit} 2>/dev/null")
    end

    def excludes_for_tar
      return '' if !exclude || exclude.empty?

      "--exclude \"#{exclude.join('" --exclude "')}\""
    end

    def artifact_name(commit)
      @_timestamp ||= Time.new.utc.strftime('%Y%m%d%H%M%S')
      "#{@_timestamp}-#{commit}"
    end
  end
end
