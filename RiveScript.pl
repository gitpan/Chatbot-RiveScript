#!/usr/bin/perl -w

use strict;
use warnings;
use Chatbot::RiveScript;
use Data::Dumper;

my $debug = 0;
if (@ARGV) {
	$debug = 1 if $ARGV[0] eq '--debug';
}

print "Chatbot::RiveScript $Chatbot::RiveScript::VERSION Loaded\n";

# Create a new RS interpreter.
my $rs = new Chatbot::RiveScript (debug => $debug);

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