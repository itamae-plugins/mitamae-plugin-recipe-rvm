node.reverse_merge!(
  rvm: {
    default_ruby: 'ruby-2.4.1',
    rubies: [],
    global_gems: [
      { name: 'bundler', version: '1.14.6' },
    ],

    installer_url: 'https://raw.githubusercontent.com/rvm/rvm/1.26.10/binscripts/rvm-installer',
    version: '1.26.10',

    root_path: '/usr/local/rvm',
    group_id: 'default',

    gpg_key: 'D39DC0E3',

    # for ubuntu
    install_pkgs: %w{sed grep tar gzip bzip2 bash curl git-core},
    user_home_root: '/home',
  }
)

define :bash, code: '' do
  execute "bash[#{params[:name]}]" do
    command "bash -c #{params[:code].shellescape}"
  end
end

define :rvm_ruby do
  rvm_root = node[:rvm][:root_path]
  version = params[:name]

  bash "rvm install #{version}" do
    code <<-EOS
      set -e
      . /usr/local/rvm/scripts/rvm
      rvm install #{::Shellwords.shellescape(version)}
    EOS
    only_if {
      rvm_ruby_bin = ::File.join(rvm_root, 'rubies', version, 'bin', 'ruby')
      not(system("test -x #{rvm_ruby_bin.shellescape}"))
    }
  end

  node[:rvm][:global_gems].each do |gem|
    gem_options = []
    if Hash === gem
      gem_options << gem[:name]
      gem_options << '--version' << gem[:version] if gem[:version]
    else
      gem_options << gem.to_s
    end
    bash "rvm: #{version}: gem install #{gem_options}" do
      code <<-EOS
        set -e
        . /usr/local/rvm/scripts/rvm
        rvm use #{::Shellwords.shellescape(version)}
        gem install #{::Shellwords.shelljoin(gem_options)}
      EOS
      not_if "bash -c #{<<-EOS.shellescape}"
        set -e
        . /usr/local/rvm/scripts/rvm
        rvm use #{::Shellwords.shellescape(version)}
        gem list -i #{::Shellwords.shelljoin(gem_options)}
      EOS
    end
  end
end

### recipes/system.rb from here

node[:rvm][:install_pkgs].each do |name|
  package name
end

if node[:rvm][:group_id] != 'default'
  raise NotImplementedError, 'non-default group_id is not supported yet'
end

rvm_root = node[:rvm][:root_path]

rvm_gpgkey = ::File.join('/var/chef/cache', 'D39DC0E3.gpg')
remote_file rvm_gpgkey do
  source 'files/D39DC0E3.gpg'
end

bash 'install default RVM GPG key' do
  code "gpg --import #{::Shellwords.shellescape(rvm_gpgkey)}"
  not_if 'gpg --list-key D39DC0E3'
end

bash 'install system-wide RVM' do
  code <<-EOS
    set -ex
    rvm="$(mktemp /tmp/rvm.XXXXXXXX.sh)"
    trap "rm -f \"${rvm}\"" EXIT
    if ! gpg --list-key #{::Shellwords.shellescape(node[:rvm][:gpg_key])}; then
      gpg --keyserver hkp://keys.gnupg.net --recv-keys #{::Shellwords.shellescape(node[:rvm][:gpg_key])}
    fi
    curl -fsSL #{::Shellwords.shellescape(node[:rvm][:installer_url])} > "${rvm}"
    cat "${rvm}" | bash -s -- --version #{::Shellwords.shellescape(node[:rvm][:version])}
  EOS
  only_if {
    rvm_bin = ::File.join(rvm_root, 'bin', 'rvm')
    not(system("test -x #{rvm_bin.shellescape}") and `#{::Shellwords.shellescape(rvm_bin)} --version 2>/dev/null || true`.split[1] == node[:rvm][:version])
  }
end

# Stop injecting RVM into user's shell
file '/etc/profile.d/rvm.sh' do
  action :delete
end

[
  node[:rvm][:default_ruby],
  node[:rvm][:rubies],
].flatten.compact.each do |version|
  rvm_ruby version
end

if version = node[:rvm][:default_ruby]
  bash "rvm set #{version} as default" do
    code <<-EOS
      set -e
      . /usr/local/rvm/scripts/rvm
      rvm alias create default #{::Shellwords.shellescape(version)}
    EOS
    only_if {
      rvm_default_ruby_prefix = ::File.join(rvm_root, 'rubies', 'default')
      rvm_ruby_prefix = ::File.join(rvm_root, 'rubies', version)
      not(::File.symlink?(rvm_default_ruby_prefix) and ::File.expand_path(::File.readlink(rvm_default_ruby_prefix)) == ::File.expand_path(rvm_ruby_prefix))
    }
  end
end

node[:rvm][:global_gems].each do |gem|
  gem_options = []
  if Hash === gem
    gem_options << gem[:name]
    gem_options << '--version' << gem[:version] if gem[:version]
  else
    gem_options << gem.to_s
  end
  [
    node[:rvm][:default_ruby],
    node[:rvm][:rubies],
  ].flatten.compact.each do |version|
    bash "rvm: #{version}: gem install #{gem_options}" do
      code <<-EOS
        set -e
        . /usr/local/rvm/scripts/rvm
        rvm use #{::Shellwords.shellescape(version)}
        gem install #{::Shellwords.shelljoin(gem_options)}
      EOS
      not_if "bash -c #{<<-EOS.shellescape}"
        set -e
        . /usr/local/rvm/scripts/rvm
        rvm use #{::Shellwords.shellescape(version)}
        gem list -i #{::Shellwords.shelljoin(gem_options)}
      EOS
    end
  end
end
