package Shinobu;

#LANraragi Background Worker.
#  While the Webapp is active, executes a workload every X seconds.
#  This workload currently is:
#
#    Automatic detection/indexing of new archives without visiting the main page 
#    Automatic tagging of new archives using enabled plugins
#    Automatic cleaning of the temporary folder when it reaches a certain size
#

use strict;
use warnings;
use utf8;
use feature qw(say);
use Cwd;

use FindBin;
BEGIN { unshift @INC, "$FindBin::Bin/../lib"; } #As this is a new process, reloading the LRR libs into INC is needed.

use Mojolicious;
use File::Find;
use File::Path qw(make_path remove_tree);
use Encode;

use LANraragi::Model::Config;
use LANraragi::Model::Utils;

sub initialize_from_new_process {

	my $interval = LANraragi::Model::Config::get_interval;

	say ("Shinobu Background Worker started -- Running every $interval seconds.");
	say ("Working dir is ".cwd);

	while (1) {
	
		&workload;
		#say ("All Background Tasks done, sleeping $interval seconds.");
		sleep($interval);
	}

}

sub workload {

	#say ("Parsing Archive Directory...");
	my @archives = LANraragi::Model::Utils::get_archive_list;
	my $redis = LANraragi::Model::Config::get_redis;

	my $cachecount = $redis->hget("LRR_JSONCACHE","archive_count");
	my $force = $redis->hget("LRR_JSONCACHE","force_refresh");

	#say ("Checking for new archives...");
	if ( scalar @archives != $cachecount ) {
		&new_archive_check(@archives);
	}

	#say ("Building JSON cache from Redis...");
	if ( scalar @archives != $cachecount || $force) {
		if ($force) { say ("JSON rebuild forced by main app..."); }
			else { say ("Archive count has changed since last cached value ($cachecount), rebuilding..."); }
		LANraragi::Model::Utils::build_json_cache(@archives);
		say ("Done!");
	}

	#say ("Checking Temp Folder Size...");
	if (-e "$FindBin::Bin/../public/temp")
		{ &autoclean_temp_folder; }

}

sub new_archive_check {

	my (@dircontents) = @_;
	my $redis = LANraragi::Model::Config::get_redis;

	my ($file, $id);

	foreach $file (@dircontents) {
		#ID of the archive, used for storing data in Redis.
		$id = LANraragi::Model::Utils::shasum($file,256);

		#Trigger archive addition if title isn't in Redis
		unless ($redis->hexists($id,"title")) {
				say ("Adding new file $file");
				say ("ID is $id");
				LANraragi::Model::Utils::add_archive_to_redis($id,$file,$redis);
			}
	}
}

sub autoclean_temp_folder {

	my $size = 0;
	find(sub { $size += -s if -f }, "$FindBin::Bin/../public/temp");
	$size = int($size/1048576*100)/100;

	my $maxsize = LANraragi::Model::Config::get_tempmaxsize;

	if ($size > $maxsize) {
		say ("Current temporary folder size is $size MBs, Maximum size is $maxsize MBs. Cleaning.");

		remove_tree("$FindBin::Bin/../public/temp", {error => \my $err}); 

		if (@$err) {
	  		for my $diag (@$err) {
		      my ($file, $message) = %$diag;
		      if ($file eq '') {
		          say "General error: $message\n";
		      }
		      else {
		          say "Problem unlinking $file: $message\n";
		      }
  			}
  		}
	}
}

__PACKAGE__->initialize_from_new_process unless caller;

1;