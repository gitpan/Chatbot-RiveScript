#!/usr/bin/perl -w

use lib "./lib";
use strict;
use warnings;
use Chatbot::RiveScript;
use Data::Dumper;

my $debug = 0;
if (@ARGV) {
	$debug = 1 if $ARGV[0] eq '--debug';
}

# Create a new RS interpreter.
my $rs = new Chatbot::RiveScript (debug => $debug);

# Define a test macro.
$rs->setSubroutine (test => \&test);

# This macro is for getting uservars and printing them.
$rs->setSubroutine (uservars => \&uservars);

# Load in some RS files.
$rs->loadDirectory ("./replies");
$rs->sortReplies;

# Set the bot to be 16 instead of 14 years old
$rs->setVariable (age => 16);

while(1) {
	print " In> ";
	my $in = <STDIN>;
	chomp $in;

	my @reply = $rs->reply ('localhost',$in);

	print "Out> $_\n" foreach(@reply);
}

sub test {
	my ($method,$data) = @_;

	print "\n"
		. "test object called! method = $method; data = $data\n\n";

	return "random number: " . int(rand(99999));
}
sub uservars {
	my ($method,$data) = @_;

	# Get uservars for 'localhost'
	print "\nGetting uservars for localhost\n";

	my $vars = $rs->getUservars ('localhost');

	foreach my $key (keys %{$vars}) {
		print "$key = $vars->{$key}\n";
	}

	print "\n";

	# Return blank.
	return '';
}