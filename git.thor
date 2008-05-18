class GitError < RuntimeError; end
class GitRebaseError < GitError; end

class Git < Thor
  
  desc "close [NAME]", "Delete the current branch and switch back to master"
  def close(name)
    branch = (!name.empty? ? name : git_branch)
    current = git_branch
    if (branch == "master") then
      $stderr.puts("* Cannot delete master branch")
      exit(1)
    end
    if (current == branch) then
      puts("* Switching to master")
      git_checkout("master")
    end
    puts("* Deleting branch #{branch}")
    `git-branch -d #{branch} 2>/dev/null`
    if ($?.exitstatus == 1) then
      $stderr.puts("* Branch #{branch} isn't a strict subset of master, quitting")
      git_checkout(current)
      exit(1)
    end
    git_checkout(current) unless (current == branch)
    exit(0)
  end

  desc "fold", "Merge the current branch into the master branch."
  def fold
    branch = git_branch
    if (branch == "master") then
      $stderr.puts("* Cannot fold master branch")
      exit(1)
    end
    puts("* Switching to master")
    git_checkout("master")
    puts("* Merging #{branch}")
    system("git-merge #{@merge_flags} #{branch}")
    if ($?.exitstatus == 1) then
      $stderr.puts("* Merge had errors -- see to your friend")
      exit(1)
    end
    puts("* Switching to #{branch}")
    git_checkout(branch)
  end

  desc "ify", "Converts an existing Subversion Repo into a Git Repository"
  def ify
    unless File.directory?("./.svn") then
      $stderr.puts("This task can only be executed in an existing working copy! (No .svn-Folder found)")
      exit(1)
    end
    svnurl = `svn info`.grep(/^URL:/).first.gsub("URL: ", "").chomp
    project = "../#{File.basename(Dir.pwd)}.git"
    puts(cmd = "git svn clone #{svnurl} #{project}")
    `#{cmd}`
  end

  desc "open [NAME]", "Create a new branch off master, named NAME"
  def open(name)
    newbranch = (!name.empty? ? name : begin
      (require("readline")
      print("* Name your branch: ")
      Readline.readline.chomp)
    end)
    branch = git_branch
    if git_branches.include?(newbranch) then
      if (newbranch == branch) then
        puts("* Already on branch \"#{newbranch}\"")
      else
        puts("* Switching to existing branch \"#{newbranch}\"")
        git_checkout(newbranch)
      end
      exit(0)
    end
    unless (branch == "master") then
      puts("* Switching to master")
      git_checkout("master")
    end
    `git-checkout -b #{newbranch}`
    unless $?.exitstatus.zero? then
      puts("* Couldn't create branch #{newbranch}, switching back to #{branch}")
      git_checkout(branch)
      exit(1)
    end
    exit(0)
  end

  desc "push", "Push local commits into the remote repository"
  def push
    git_stash do
      puts("* Pushing changes...")
      git_push
      branch = git_branch
      unless (branch == "master") then
        git_checkout("master")
        puts("* Porting changes into master")
        git_rebase
        git_checkout(branch)
      end
    end
  end

  desc "squash", "Squash the current branch into the master branch."
  def squash
    @merge_flags = "--squash"
    Rake::Task["git:fold"].invoke
  end

  desc "update", "Pull new commits from the repository"
  def update
    git_stash do
      branch = git_branch
      if (branch == "master") then
        switch = false
      else
        switch = true
        git_checkout("master")
        puts("* Switching back to master...")
      end
      puts("* Pulling in new commits...")
      git_fetch
      git_rebase
      if switch then
        puts("* Porting changes into #{branch}...")
        git_checkout(branch)
        `git-rebase master`
      end
    end
  end

  desc "all", "Update all branches"
  def all
    git_stash do
      branch = git_branch
      switch = true
      git_branches.each do |b|
        puts("* Updating branch #{b}")
        begin
          git_rebase(b)
        rescue GitRebaseError => e
          puts("* Couldn't rebase #{b}, aborting so you can clean it up")
          switch = false
          break
        end
      end
      git_checkout(branch) if switch
    end
  end

  private
  
  def git_branch
    `git-branch`.grep(/^\*/).first.strip[(2..-1)]
  end
  
  def git_branches
    `git-branch`.to_a.map { |b| b[(2..-1)].chomp }
  end
  
  def git?
    `git-status`
    (not ($?.exitstatus == 128))
  end
  
  def git_stash
    `git-diff-files --quiet`
    if ($?.exitstatus == 1) then
      stash = true
      clear = (`git-stash list`.scan("\n").size == 0)
      puts("* Saving changes...")
      `git-stash save`
    else
      stash = false
    end
    begin
      yield
    rescue
      puts("* Encountered an error, backing out...")
    ensure
      if stash then
        puts("* Applying changes...")
        `git-stash apply`
        `git-stash clear` if clear
      end
    end
  end
 
  def git_checkout(what = nil)
    branch = git_branch
    `git-checkout #{what}` unless (branch == what)
    if block_given? then
      yield
      `git-checkout #{branch}` unless (branch == what)
    end
  end
 
  def git_fetch
    `git#{"-svn" if git_svn?} fetch`
  end
 
  def assert_command_succeeded(*args)
    raise(*args) unless ($?.exitstatus == 0)
  end
 
  def assert_rebase_succeeded(what = nil)
    assert_command_succeeded(GitRebaseError, "conflict while rebasing branch #{what}")
  end
  
  def git_rebase(what = nil)
    if git_svn? then
      git_checkout(what) do
        `git-svn rebase --local`
        assert_rebase_succeeded(what)
      end
    else
      `git-rebase origin/master #{what}`
      assert_rebase_succeeded(what)
    end
  end
  
  def git_push
    git_svn? ? (`git-svn dcommit`) : (`git-push`)
  end
  
  def git_svn?
    (not File.readlines(".git/config").grep(/^\[svn-remote "svn"\]\s*$/).empty?)
  end
end
