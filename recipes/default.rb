#
# Cookbook Name:: sdx-nginx
# Recipe:: default
#
# Copyright 2013, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#


#create admin
#openssl passwd -1 "admin"
user "admin" do
	comment "Admin user"
	home "/home/admin"
	shell "/bin/bash"
	password "$1$XhfNJoLH$lyY/n2WgnXQQaLVacEwzC/"
	supports :manage_home => true, :non_unique => false
end

directory "/home/admin/.ssh" do
	owner "admin"
	group "admin"
	mode 0700
end

bash "known host for github" do
	code "ssh-keyscan -H github.com >> /home/admin/.ssh/known_hosts"
	user "admin"
	not_if "su admin --c 'ssh-keygen -F github.com | grep -q \'github\.com\''"
end

cookbook_file "/home/admin/.ssh/github.id_rsa" do
	source "github.id_rsa"
	mode 0600
	owner "admin"
	group "admin"
end

template '/home/admin/.ssh/config' do
	action 'create_if_missing'
	source 'ssh.config.erb'
	owner 'admin'
	group 'admin'
	mode 0600
end

#Config for git
template '/home/admin/.gitconfig' do
	action 'create_if_missing'
	source 'gitconfig.erb'
	owner 'admin'
	group 'admin'
	mode 0644
	variables(
		:email => node['sdx-nginx']['git_email'],
		:name => node['sdx-nginx']['git_name']
	)
end

#setup sdx
directory node['sdx-nginx']['dir'] do
	owner "admin"
	group "admin"
	recursive true
	mode 0755
end

git node['sdx-nginx']['dir'] + '/sdx' do
	repository "git@github.com:SunriseDigital/sdx.git"
	user "admin"
	group "admin"
	reference "master"
	action :sync
end

subversion "Zend Framework" do
  repository "http://framework.zend.com/svn/framework/standard/tags/release-1.11.9/library/Zend"
  revision "HEAD"
  destination  node['sdx-nginx']['dir'] + "/sdx/models/Zend"
  action :sync
  user "admin"
end

subversion "Smarty" do
  repository "http://smarty-php.googlecode.com/svn/tags/Smarty_3_1_9/distribution/libs"
  revision "HEAD"
  destination node['sdx-nginx']['dir'] + "/sdx/models/Smarty"
  action :sync
  user "admin"
end

node['sdx-nginx']['repos'].each do |repos|
	_repos_dir = node['sdx-nginx']['dir'] + '/' + repos.dir;

	#git clone
	git _repos_dir do
		repository repos.git
		user "admin"
		group "admin"
		reference (repos.branch || "master")
		action :sync
	end
	repos.servers.each do |server|
		_target_dir = _repos_dir + '/' + server.dir;
		_context_dir = _repos_dir + '/' + repos.context_dir;
		#virtual host
		template '/etc/nginx/conf.d/' + server.dir + '.conf' do
			action 'create_if_missing'
			source 'nginx.conf.erb'
			owner 'root'
			group 'root'
			mode 0644
			variables(
				:base_dir => _target_dir,
				:server_name => server.server_name
			)
		end

		#init app
		bash 'init app' do
			code node['sdx-nginx']['dir'] + "/sdx/initapp " + _target_dir + ' ' + _context_dir + ' ' +repos.namespace
			user "admin"
		end

		#insert mysql
		if repos['mysql_dump']
			#copy dump
			cookbook_file "/tmp/" + repos.mysql_dump do
				source repos.mysql_dump
				mode 0644
				owner "admin"
				group "admin"
			end

			_mysql_command = 'mysql -u root ';
			if repos['mysql_root_pwd']
				_mysql_command << ('-p ' + repos['mysql_root_pwd'] + ' ')
			end

			#insert dump
			bash 'insert dump' do
				code _mysql_command + ' < /tmp/' + repos.mysql_dump
				user "admin"
			end

			#grant
			_grant_sql = _context_dir + '/database/sql/grant.sql'
			bash 'grunt' do
				only_if {File.exists?(_grant_sql)}
				code _mysql_command + ' < ' + _grant_sql
				user "admin"
			end
		end
	end
end

service 'nginx' do
  action [:restart]
end