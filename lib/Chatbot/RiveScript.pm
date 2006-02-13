package Chatbot::RiveScript;

use strict;
no strict 'refs';
use warnings;

our $VERSION = '0.06';

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto || 'Chatbot::RiveScript';

	my $self = {
		debug   => 0,
		reserved    => [      # Array of reserved (unmodifiable) keys.
			qw (reserved replies array syntax streamcache botvars uservars botarrays
			sort users substitutions),
		],
		replies     => {},    # Replies
		array       => {},    # Sorted replies array
		syntax      => {},    # Keep files and line numbers
		streamcache => undef, # For streaming replies in
		botvars     => {},    # Bot variables (! var botname = Casey)
		substitutions => {},  # Substitutions (! sub don't = do not)
		uservars    => {},    # User variables
		users       => {},    # Temporary things
		botarrays   => {},    # Bot arrays
		sort        => {},    # For reply sorting
		loops       => {},    # Reply recursion
		macros      => {},    # Subroutine macro objects

		# Some editable globals.
		split_sentences    => 1,         # Perform sentence-splitting.
		sentence_splitters => '! . ? ;', # The sentence-splitters.
		@_,
	};

	bless ($self,$class);
	return $self;
}

sub debug {
	my ($self,$msg) = @_;

	print "RiveScript // $msg\n" if $self->{debug} == 1;
}

sub setSubroutine {
	my ($self,%subs) = @_;

	foreach my $sub (keys %subs) {
		$self->{macros}->{$sub} = $subs{$sub};
	}
}

sub setGlobal {
	my ($self,%data) = @_;

	foreach my $key (keys %data) {
		my $lc = lc($key);
		$lc =~ s/ //g;

		my $ok = 1;
		foreach my $res (@{$self->{reserved}}) {
			if ($res eq $lc) {
				warn "Can't modify reserved global $res";
				$ok = 0;
			}
		}

		next unless $ok;

		# Delete global?
		if ($data{$key} eq 'undef') {
			delete $self->{$key};
		}
		else {
			$self->{$key} = $data{$key};
		}
	}
}

sub setVariable {
	my ($self,%data) = @_;

	foreach my $key (keys %data) {
		if ($data{$key} eq 'undef') {
			delete $self->{botvars}->{$key};
		}
		else {
			$self->{botvars}->{$key} = $data{$key};
		}
	}
}

sub setSubstitution {
	my ($self,%data) = @_;

	foreach my $key (keys %data) {
		if ($data{$key} eq 'undef') {
			delete $self->{substitutions}->{$key};
		}
		else {
			$self->{substitutions}->{$key} = $data{$key};
		}
	}
}

sub setArray {
	my ($self,%data) = @_;

	foreach my $key (keys %data) {
		if ($data{$key} eq 'undef') {
			delete $self->{botarrays}->{$key};
		}
		else {
			$self->{botarrays}->{$key} = $data{$key};
		}
	}
}

sub setUservar {
	my ($self,$user,%data) = @_;

	foreach my $key (keys %data) {
		if ($data{$key} eq 'undef') {
			delete $self->{uservars}->{$user}->{$key};
		}
		else {
			$self->{uservars}->{$user}->{$key} = $data{$key};
		}
	}
}

sub getUservars {
	my $self = shift;
	my $user = shift || '__rivescript__';

	# Return uservars for a specific user?
	if ($user ne '__rivescript__') {
		return $self->{uservars}->{$user};
	}
	else {
		my $array = [];
		push (@{$array}, $self->{uservars}->{$_}) foreach (keys %{$self->{uservars}});
	}
}

sub loadDirectory {
	my $self = shift;
	my $dir = shift;

	# Load a directory.
	if (-d $dir) {
		opendir (DIR, $dir);
		foreach my $file (sort(grep(/\.rs$/i, readdir(DIR)))) {
			# Load in this file.
			$self->loadFile ("$dir/$file");
		}
		closedir (DIR);
	}
	else {
		warn "RiveScript // The directory $dir doesn't exist!";
	}
}

sub stream {
	my ($self,$code) = @_;

	$self->{streamcache} = $code;
	$self->loadFile (undef,1);
}

sub loadFile {
	my $self = shift;
	my $file = shift || '(Streamed)';
	my $stream = shift || 0;

	# Prepare to load the file.
	my @data = ();

	# Streaming in replies?
	if ($stream) {
		@data = split(/\n/, $self->{streamcache});
		chomp @data;
	}
	else {
		open (FILE, $file);
		@data = <FILE>;
		close (FILE);
		chomp @data;
	}

	$self->debug ("Parsing in file $file");

	# Set up parser variables.
	my $started = 0;        # Haven't found a trigger yet
	my $inReply = 0;        # Not in a reply yet
	my $inCom   = 0;        # Not in commented code
	my $inObj   = 0;        # In an object.
	my $objName = '';       # Object's name
	my $objCode = '';       # Object's source.
	my $topic   = 'random'; # Default topic
	my $trigger = '';       # The trigger we're on
	my $replies = 0;        # -REPLY counter
	my $conds   = 0;        # *CONDITION counter
	my $num     = 0;        # Line numbers.
	my $conc    = 0;        # Concetanate the last command (0.06)
	my $lastCmd = '';       # The last command used (0.06)

	# Go through the file.
	foreach my $line (@data) {
		$num++;

		# If in an object...
		if ($inObj == 1) {
			if ($line !~ /< object/i) {
				$objCode .= "$line\n";
				next;
			}
		}

		# Format the line.
		$self->debug ("Line $num ($inCom): $line");
		next if length $line == 0; # Skip blank lines
		$line =~ s/^[\s\t]//g;     # Remove prepent whitepaces
		$line =~ s/[\s\t]$//g;     # Remove appent whitespaces

		# Separate the command from its data.
		my ($command,$data) = split(/\s+/, $line, 2);

		# Filter in hard spaces.
		$data =~ s/\\s/ /g if defined $data;

		# Check for comment commands...
		if ($command =~ /^\/\//) {
			# Single comment. Skip it.
			next;
		}
		if ($command eq '/*') {
			# We're starting a comment section.
			if (defined $data && $data =~ /\*\//) {
				# The section was ended here too.
				next;
			}
			$inCom = 1;
		}
		if ($command eq '*/' || (defined $data && $data =~ /\*\//)) {
			$inCom = 0;
			next;
		}

		# Skip comments.
		next if $inCom;

		# Concatenate previous commands.
		if ($command eq '^') {
			$self->debug ("^ Command - Command Continuation");

			if ($lastCmd =~ /^\! global (.*?)$/i) {
				my $var = $1;
				$self->{$var} .= $data;
			}
			elsif ($lastCmd =~ /^\! var (.*?)$/i) {
				my $var = $1;
				$self->{botvars}->{$var} .= $data;
			}
			elsif ($lastCmd =~ /^\! array (.*?)$/i) {
				my $var = $1;
				if ($data =~ /\|/) {
					my @words = split(/\|/, $data);
					push (@{$self->{botarrays}->{$var}}, @words);
				}
				else {
					my @words = split(/\s+/, $data);
					push (@{$self->{botarrays}->{$var}}, @words);
				}
			}
			elsif ($lastCmd =~ /^\+ (.*?)$/i) {
				my $tr = $1;
				$trigger = $tr . $data;
			}
			elsif ($lastCmd =~ /^\% (.*?)$/i) {
				my $that = $1;
				$topic .= $data;
			}
			elsif ($lastCmd =~ /^\@ (.*?)$/i) {
				my $at = $1;
				$self->{replies}->{$topic}->{$trigger}->{redirect} .= $data;
			}
			else {
				# Normal behavior
				$self->{replies}->{$topic}->{$trigger}->{$replies} .= $data;
			}

			next;
		}

		# Go through actual commands.
		if ($command eq '>') {
			$self->debug ("> Command - Label Begin!");
			my ($type,$text) = split(/\s+/, $data, 2);
			if ($type eq 'topic') {
				$self->debug ("\tTopic set to $text");
				$topic = $text;
			}
			elsif ($type eq 'begin') {
				$self->debug ("\tA begin handler");
				$topic = '__begin__';
			}
			elsif ($type eq 'object') {
				$self->debug ("\tAn object");
				$objName = $text || 'unknown';
				$inObj = 1;
			}
			else {
				warn "Unknown label type at $file line $num";
			}
		}
		elsif ($command eq '<') {
			$self->debug ("< Command - Label End!");
			if ($data eq 'topic' || $data eq '/topic' || $data eq 'begin' || $data eq '/begin') {
				$self->debug ("\tTopic reset!");
				$topic = 'random';
			}
			elsif ($data eq 'object') {
				# Save the object.
				my $code = "\$self->setSubroutine ($objName => \\&rscode_$objName);\n\n"
					. "sub rscode_$objName {\n"
					. "$objCode\n"
					. "}\n";

				my $eval = eval $code;
				$inObj = 0;
				$objName = '';
				$objCode = '';
			}
			else {
				warn "Unknown label ender at $file line $num";
			}
		}
		elsif ($command eq '!') {
			$self->debug ("! Command - Definition");

			my ($type,$details) = split(/\s+/, $data, 2);
			my ($what,$is) = split(/=/, $details, 2);
			$what =~ s/\s//g; $is =~ s/^\s//g;
			$type =~ s/\s//g;
			$type = lc($type);

			# Globals?
			if ($type eq 'global') {
				my $err = 0;
				foreach my $reserved (@{$self->{reserved}}) {
					if ($what eq $reserved) {
						$err = 1;
						last;
					}
				}

				# Skip if there was a problem.
				if ($err) {
					warn "Can't modify reserved global $what";
					next;
				}

				$lastCmd = "! global $what";

				# Set this top-level global.
				if ($is ne 'undef') {
					$self->debug ("\tSet global $what = $is");
					$self->{$what} = $is;
				}
				else {
					$self->debug ("\tDeleting global $what");
					delete $self->{$what};
				}
			}
			elsif ($type eq 'var') {
				# Set a botvariable.
				$lastCmd = "! var $what";
				if ($is ne 'undef') {
					$self->debug ("\tSet botvar $what = $is");
					$self->{botvars}->{$what} = $is;
				}
				else {
					$self->debug ("\tDeleting botvar $what");
					delete $self->{botvars}->{$what};
				}
			}
			elsif ($type eq 'array') {
				# An array.
				$lastCmd = "! array $what";

				# Delete the array?
				if ($is eq 'undef') {
					$self->debug ("\tDeleting array $what");
					delete $self->{botarrays}->{$what};
					next;
				}

				$self->debug ("\tSetting array $what = $is");
				my @array = ();

				# Does it contain pipes?
				if ($is =~ /\|/) {
					# Split at them.
					@array = split(/\|/, $is);
				}
				else {
					# Split at spaces.
					@array = split(/\s+/, $is);
				}

				# Keep them.
				$self->{botarrays}->{$what} = [ @array ];
			}
			elsif ($type eq 'sub') {
				# Substitutions.

				if ($is ne 'undef') {
					$self->debug ("\tSet substitution $what = $is");
					$self->{substitutions}->{$what} = $is;
				}
				else {
					$self->debug ("\tDeleting substitution $what");
					delete $self->{substitutions}->{$what};
				}
			}
			else {
				warn "Unsupported type at $file line $num";
			}
		}
		elsif ($command eq '+') {
			$self->debug ("+ Command - Reply Trigger!");

			if ($inReply == 1) {
				# Reset the topics?
				if ($topic =~ /^__that__/i) {
					$topic = 'random';
				}

				# New reply.
				$inReply = 0;
				$trigger = '';
				$replies = 0;
				$conds = 0;
			}

			# Reply trigger.
			$inReply = 1;
			$trigger = $data;
			$lastCmd = "+ $trigger";
			$self->debug ("\tTrigger: $trigger");

			# Set the trigger under its topic.
			$self->{replies}->{$topic}->{$trigger}->{topic} = $topic;
			$self->{syntax}->{$topic}->{$trigger}->{ref} = "$file line $num";
		}
		elsif ($command eq '%') {
			$self->debug ("% Command - Previous!");

			if ($inReply != 1) {
				# Error.
				warn "Syntax error at $file line $num";
				next;
			}

			# Set the topic to "__that__$data"
			$lastCmd = "\% $data";
			$topic = "__that__$data";
		}
		elsif ($command eq '-') {
			$self->debug ("- Command - Response!");

			$lastCmd = ''; # -Reply is the default usage for ^Continue

			if ($inReply != 1) {
				# Error.
				warn "Syntax error at $file line $num";
				next;
			}

			# Reply response.
			$replies++;

			$self->{replies}->{$topic}->{$trigger}->{$replies} = $data;
			$self->{syntax}->{$topic}->{$trigger}->{$replies}->{ref} = "$file line $num";
		}
		elsif ($command eq '@') {
			$self->debug ("\@ Command - Redirect");

			if ($inReply != 1) {
				# Error.
				warn "Syntax error at $file line $num";
				next;
			}

			$lastCmd = "\@ $data";

			$self->{replies}->{$topic}->{$trigger}->{redirect} = $data;
			$self->{syntax}->{$topic}->{$trigger}->{redirect}->{ref} = "$file line $num";
		}
		elsif ($command eq '*') {
			$self->debug ("* Command - Conditional");

			if ($inReply != 1) {
				# Error.
				warn "Syntax error at $file line $num";
				next;
			}

			$conds++;
			$self->{replies}->{$topic}->{$trigger}->{conditions}->{$conds} = $data;
			$self->{syntax}->{$topic}->{$trigger}->{conditions}->{$conds}->{ref} = "$file line $num";
		}
		elsif ($command eq '&') {
			$self->debug ("\& Command - Perl Code");

			if ($inReply != 1) {
				# Error.
				warn "Syntax error at $file line $num";
				next;
			}

			$self->{replies}->{$topic}->{$trigger}->{system}->{codes} .= $data;
			$self->{syntax}->{$topic}->{$trigger}->{system}->{codes}->{ref} = "$file line $num";
		}
		else {
			warn "Unknown command $command";
		}
	}
}

sub sortReplies {
	my ($self) = @_;

	# Reset defaults.
	$self->{sort}->{replycount} = 0;

	# Fail if replies hadn't been loaded.
	return 0 unless (scalar (keys %{$self->{replies}}));

	# Delete the replies array if it exists.
	if (exists $self->{array}) {
		delete $self->{array};
	}

	$self->debug ("Sorting the replies...");

	# Count them while we're at it.
	my $count = 0;

	# Go through each reply.
	foreach my $topic (keys %{$self->{replies}}) {
		# print "Sorting replies under topic $topic...\n";

		# Sort by number of whole words (or, not wildcards).
		my $sort = {
			def => [],
			unknown => [],
		};
		for (my $i = 0; $i <= 50; $i++) {
			$sort->{$i} = [];
		}

		# Set trigger arrays.
		my @trigNorm = ();
		my @trigWild = ();

		# Go through each item.
		foreach my $key (keys %{$self->{replies}->{$topic}}) {
			$count++;

			# print "\tSorting $key\n";

			# If this has wildcards...
			if ($key =~ /\*/) {
				# See how many full words it has.
				my @words = split(/\s/, $key);
				my $cnt = 0;
				foreach my $word (@words) {
					$word =~ s/\s//g;
					next unless length $word;
					if ($word !~ /\*/) {
						# A whole word.
						$cnt++;
					}
				}

				# What did we get?
				$cnt = 50 if $cnt > 50;

				# print "\t\tWildcard with $cnt words\n";

				if (exists $sort->{$cnt}) {
					push (@{$sort->{$cnt}}, $key);
				}
				else {
					push (@{$sort->{unknown}}, $key);
				}
			}
			else {
				# Save to normal array.
				# print "\t\tNormal trigger\n";
				push (@{$sort->{def}}, $key);
			}
		}

		# Merge all the arrays.
		$self->{array}->{$topic} = [
			@{$sort->{def}},
		];
		for (my $i = 50; $i >= 1; $i--) {
			push (@{$self->{array}->{$topic}}, @{$sort->{$i}});
		}
		push (@{$self->{array}->{$topic}}, @{$sort->{unknown}});
		push (@{$self->{array}->{$topic}}, @{$sort->{0}});
	}

	# Save the count.
	$self->{sort}->{replycount} = $count;
	return 1;
}

sub reply {
	my ($self,$id,$msg) = @_;

	# Reset loops.
	$self->{loops} = 0;

	# print "reply called\n";

	# Check a global begin set first.
	if (!exists $self->{users}->{'__rivescript__'}) {
		$self->{users}->{__rivescript__}->{topic} = '__begin__';
	}

	my $begin = $self->intReply ('__rivescript__', 'request');
	$begin = '{ok}' if $begin =~ /^ERR: No Reply/;

	my @out = ();
	if ($begin =~ /\{ok\}/i) {
		# Format their message.
		my @sentences = $self->splitSentences ($msg);
		foreach my $in (@sentences) {
			$in = $self->formatMessage ($in);
			next unless length $in > 0;
			# print "Sending sentence \"$in\" in...\n";
			my @returned = $self->intReply ($id,$in);
			push (@out,@returned);
		}

		my @final = ();

		foreach (@out) {
			my $reply = $begin;
			$reply =~ s/\{ok\}/$_/ig;
			push (@final,$reply);
		}

		return @final;
	}
	else {
		return $begin;
	}
}

sub intReply {
	my ($self,$id,$msg) = @_;

	# Sort replies if they haven't been yet.
	if (!(scalar(keys %{$self->{array}}))) {
		warn "You should sort replies BEFORE calling reply()!";
		$self->sortReplies;
	}

	# Create this user's history.
	if (!exists $self->{users}->{$id}->{history}) {
		$self->{users}->{$id}->{history}->{input} = ['', 'undefined', 'undefined', 'undefined', 'undefined',
			'undefined', 'undefined', 'undefined', 'undefined', 'undefined' ];
		$self->{users}->{$id}->{history}->{reply} = ['', 'undefined', 'undefined', 'undefined', 'undefined',
			'undefined', 'undefined', 'undefined', 'undefined', 'undefined' ];
		# print "\tCreated user history\n";
	}

	# Too many loops?
	if ($self->{loops} >= 15) {
		$self->{loops} = 0;
		my $topic = $self->{users}->{$id}->{topic} || 'random';
		return "ERR: Deep Recursion (15+ loops in reply set) at $self->{syntax}->{$topic}->{$msg}->{redirect}->{ref}";
	}

	# Create variables.
	my %stars = (); # Wildcard captors
	my $reply; # The final reply.

	# Topics?
	$self->{users}->{$id}->{topic} ||= 'random';

	# Setup the user's temporary history.
	$self->{users}->{$id}->{last} = '' unless exists $self->{users}->{$id}->{last}; # Last Msg
	$self->{users}->{$id}->{that} = '' unless exists $self->{users}->{$id}->{that}; # Bot Last Reply

	# Make sure some replies are loaded.
	if (!exists $self->{replies}) {
		return "ERR: No replies have been loaded!";
	}

	# See if this topic has any "that's" associated with it.
	my $thatTopic = "__that__$self->{users}->{$id}->{that}";
	my $lastSent = $self->{users}->{$id}->{that};
	my $isThat = 0;
	my $keepTopic = '';

	# Go through each reply.
	# print "Scanning through topics...\n";
	foreach my $topic (keys %{$self->{array}}) {
		# print "\tOn Topic: $topic\n";
		if ($isThat != 1 && length $lastSent > 0 && exists $self->{replies}->{$thatTopic}->{$msg}) {
			# It does exist. Set this as the topic so this reply should be matched.
			$isThat = 1;
			$keepTopic = $self->{users}->{$id}->{topic};
			$self->{users}->{$id}->{topic} = $thatTopic;
		}

		# Don't look at topics that aren't ours.
		next unless $topic eq $self->{users}->{$id}->{topic};

		# print "\tThis is our topic!\n";

		# Check the inputs.
		foreach my $in (@{$self->{array}->{$topic}}) {
			last if defined $reply;
			# Slightly format the trigger to be regexp friendly.
			my $regexp = $in;
			$regexp =~ s~\*~\(\.\*\?\)~g;

			# Run optional modifiers.
			while ($regexp =~ /\[(.*?)\]/i) {
				my $o = $1;
				my @parts = split(/\|/, $o);
				my @new = ();

				foreach my $word (@parts) {
					$word = '\s*' . $word . '\s*';
					push (@new,$word);
				}

				push (@new,'\s*');
				my $rep = '(' . join ('|',@new) . ')';

				$regexp =~ s/\s*\[(.*?)\]\s*/$rep/i;
			}

			# Filter in arrays.
			while ($regexp =~ /\(\@(.*?)\)/i) {
				my $o = $1;
				my $name = $o;
				my $rep = '';
				if (exists $self->{botarrays}->{$name}) {
					$rep = '(' . join ('|', @{$self->{botarrays}->{$name}}) . ')';
				}
				$regexp =~ s/\(\@(.*?)\)/$rep/i;

				print "Filtered in array $rep\n";
			}

			# Filter in botvariables.
			while ($regexp =~ /<bot (.*?)>/i) {
				my $o = $1;
				my $value = $self->{botvars}->{$o};
				$value =~ s/[^A-Za-z0-9 ]//g;
				$value = lc($value);
				$regexp =~ s/<bot (.*?)>/$value/i;
			}

			# print "\tComparing $msg with $regexp\n";

			# See if it's a match.
			if ($msg =~ /^$regexp$/i) {
				# Collect the stars.
				# print "\$1 = $1\n";
				for (my $i = 1; $i <= 100; $i++) {
					$stars{$i} = eval ('$' . $i);
				}

				# A solid redirect? (@ command)
				if (exists $self->{replies}->{$topic}->{$in}->{redirect}) {
					my $redirect = $self->{replies}->{$topic}->{$in}->{redirect};

					# Filter wildcards into it.
					$redirect = $self->mergeWildcards ($redirect,%stars);

					# Plus a loop.
					$self->{loops}++;
					$reply = $self->intReply ($id,$redirect);
					return $reply;
				}

				# Check for conditionals.
				if (exists $self->{replies}->{$topic}->{$in}->{conditions}) {
					for (my $c = 1; exists $self->{replies}->{$topic}->{$in}->{conditions}->{$c}; $c++) {
						last if defined $reply;

						my $condition = $self->{replies}->{$topic}->{$in}->{conditions}->{$c};
						my ($cond,$happens) = split(/=>/, $condition, 2);
						$cond =~ s/\s$//g;
						$happens =~ s/^\s//g;

						my ($var,$value) = split(/=/, $cond, 2);

						# Check variables.
						if (exists $self->{botvars}->{$var} || exists $self->{uservars}->{$id}->{$var}) {
							if (exists $self->{botvars}->{$var}) {
								if (($value =~ /[^0-9]/ && $self->{botvars}->{$var} eq $value) ||
								($self->{botvars}->{$var} eq $value)) {
									$reply = $happens;
								}
							}
							else {
								if (($value =~ /[^0-9]/ && $self->{uservars}->{$id}->{$var} eq $value) ||
								($self->{uservars}->{$id}->{$var} eq $value)) {
									$reply = $happens;
								}
							}
						}
					}
				}

				# If we have a reply, quit.
				last if defined $reply;

				# Get a random reply now.
				my @random = ();
				my $totweight = 0;
				for (my $i = 1; exists $self->{replies}->{$topic}->{$in}->{$i}; $i++) {
					my $item = $self->{replies}->{$topic}->{$in}->{$i};
					if ($item =~ /\{weight=(.*?)\}/i) {
						my $weight = $1;
						$item =~ s/\{weight=(.*?)\}//g;
						if ($weight !~ /[^0-9]/i) {
							$totweight += $weight;

							for (my $i = $weight; $i >= 0; $i--) {
								push (@random,$item);
							}
						}
						next;
					}
					push (@random, $self->{replies}->{$topic}->{$in}->{$i});
				}

				# print "\@random = " . scalar(@random) . "\n";
				$reply = $random [ int(rand(scalar(@random))) ];

				# Run system commands.
				if (exists $self->{replies}->{$topic}->{$in}->{system}->{codes}) {
					my $eval = eval ($self->{replies}->{$topic}->{$in}->{system}->{codes});
				}
			}
		}
	}

	# Reset "that" topics.
	if ($isThat == 1) {
		$self->{users}->{$id}->{topic} = $keepTopic;
		$self->{users}->{$id}->{that} = '<<undef>>';
	}

	# A reply?
	if (defined $reply) {
		# Filter in stars...
		$reply = $self->mergeWildcards ($reply,%stars);
	}
	else {
		# Were they in a possibly broken topic?
		if ($self->{users}->{$id}->{topic} ne 'random') {
			if (exists $self->{array}->{$self->{users}->{$id}->{topic}}) {
				$reply = "ERR: No Reply Matched in Topic $self->{users}->{$id}->{topic}";
			}
			else {
				$self->{users}->{$id}->{topic} = 'random'; # Breakaway
				$reply = "ERR: No Reply in Topic $self->{users}->{$id}->{topic} (possibly void topic?)";
			}
		}
		else {
			$reply = "ERR: No Reply Found";
		}
	}

	# History tags.
	$reply =~ s/<input(\d)>/$self->{users}->{$id}->{history}->{input}->[$1]/g;
	$reply =~ s/<reply(\d)>/$self->{users}->{$id}->{history}->{reply}->[$1]/g;

	# Insert variables.
	$reply =~ s/<bot (.*?)>/$self->{botvars}->{$1}/ig;
	$reply =~ s/<id>/$id/ig;

	# String modifiers.
	while ($reply =~ /\{(formal|uppercase|lowercase|sentence)\}(.*?)\{\/(formal|uppercase|lowercase|sentence)\}/i) {
		my ($type,$string) = ($1,$2);
		$type = lc($type);
		my $o = $string;
		$string = $self->stringUtil ($type,$string);
		$o =~ s/([^A-Za-z0-9 =<>])/\\$1/g;
		$reply =~ s/\{$type\}$o\{\/$type\}/$string/ig;
	}

	# Topic setters.
	if ($reply =~ /\{topic=(.*?)\}/i) {
		my $to = $1;
		$self->{users}->{$id}->{topic} = $to;
		# print "Setting topic to $to\n";
		$reply =~ s/\{topic=(.*?)\}//g;
	}

	# Variable setters?
	while ($reply =~ /\{\!(.*?)\}/i) {
		my $o = $1;
		my $data = $o;
		$data =~ s/^\s//g;
		$data =~ s/\s$//g;

		my ($type,$details) = split(/\s+/, $data, 2);
		my ($what,$is) = split(/=/, $details, 2);
		$what =~ s/\s//g; $is =~ s/^\s//g;
		$type =~ s/\s//g;
		$type = lc($type);

		# Stream this in.
		# print "Streaming in: ! $type $what = $is\n";
		$self->stream ("! $type $what = $is");
		$reply =~ s/\{\!$o\}//i;
	}

	# Sub-replies.
	while ($reply =~ /\{\@(.*?)\}/i) {
		my $o = $1;
		my $trig = $o;
		$trig =~ s/^\s//g;
		$trig =~ s/\s$//g;

		my $resp = $self->intReply ($id,$trig);

		$reply =~ s/\{\@$o\}/$resp/i;
	}

	# Run macros.
	while ($reply =~ /\&(.*?)\((.*?)\)/i) {
		my $rel = $1;
		my $data = $2;

		my ($object,$method) = split(/\./, $rel, 2);
		$method = 'default' unless defined $method;

		my $returned = '';

		if (defined $self->{macros}->{$object}) {
			$returned = &{$self->{macros}->{$object}} ($method,$data);
		}
		else {
			$returned = 'ERR(Unknown Macro)';
		}

		$reply =~ s/\&(.*?)\((.*?)\)/$returned/i;
	}

	# Randomness.
	while ($reply =~ /\{random\}(.*?)\{\/random\}/i) {
		my $text = $1;
		my @options = ();

		# Pipes?
		if ($text =~ /\|/) {
			@options = split(/\|/, $text);
		}
		else {
			@options = split(/\s+/, $text);
		}

		my $rep = $options [ int(rand(scalar(@options))) ];
		$reply =~ s/\{random\}(.*?)\{\/random\}/$rep/i;
	}

	# Get/Set uservars?
	while ($reply =~ /<set (.*?)>/i) {
		my $o = $1;
		my $data = $o;
		my ($what,$is) = split(/=/, $data, 2);
		$what =~ s/\s$//g;
		$is =~ s/^\s//g;

		# Set it.
		if ($is eq 'undef') {
			delete $self->{uservars}->{$id}->{$what};
		}
		else {
			# print "Set $what to $is for $id\n";
			$self->{uservars}->{$id}->{$what} = $is;
		}

		$reply =~ s/<set (.*?)>//i;
	}
	while ($reply =~ /<get (.*?)>/i) {
		my $o = $1;
		my $data = $o;
		my $value = $self->{uservars}->{$id}->{$data} || 'undefined';

		# print "Inserting $data ($value)\n";

		$reply =~ s/<get $o>/$value/i;
	}

	# Update history.
	shift (@{$self->{users}->{$id}->{history}->{input}});
	shift (@{$self->{users}->{$id}->{history}->{reply}});
	unshift (@{$self->{users}->{$id}->{history}->{input}}, $msg);
	unshift (@{$self->{users}->{$id}->{history}->{reply}}, $reply);
	unshift (@{$self->{users}->{$id}->{history}->{input}}, '');
	unshift (@{$self->{users}->{$id}->{history}->{reply}}, '');
	pop (@{$self->{users}->{$id}->{history}->{input}});
	pop (@{$self->{users}->{$id}->{history}->{reply}});

	# Format the bot's reply.
	my $simple = lc($reply);
	$simple =~ s/[^A-Za-z0-9 ]//g;
	$simple =~ s/^\s+//g;
	$simple =~ s/\s$//g;

	# Save this message.
	$self->{users}->{$id}->{that} = $simple;
	$self->{users}->{$id}->{last} = $msg;
	$self->{users}->{$id}->{hold} ||= 0;

	# Reset the loop timer.
	$self->{loops} = 0;

	# There SHOULD be a reply now.
	# Return it in pairs at {nextreply}
	if ($reply =~ /\{nextreply\}/i) {
		my @returned = split(/\{nextreply\}/i, $reply);
		return @returned;
	}

	# Filter in line breaks.
	$reply =~ s/\\n/\n/g;

	return $reply;
}

sub search {
	my ($self,$string) = @_;

	# Search for this string.
	$string = $self->formatMessage ($string);

	my @result = ();
	foreach my $topic (keys %{$self->{array}}) {
		foreach my $trigger (@{$self->{array}->{$topic}}) {
			my $regexp = $trigger;
			$regexp =~ s~\*~\(\.\*\?\)~g;

			# Run optional modifiers.
			while ($regexp =~ /\[(.*?)\]/i) {
				my $o = $1;
				my @parts = split(/\|/, $o);
				my @new = ();

				foreach my $word (@parts) {
					$word = ' ' . $word . ' ';
					push (@new,$word);
				}

				push (@new,' ');
				my $rep = '(' . join ('|',@new) . ')';

				$regexp =~ s/\s*\[(.*?)\]\s*/$rep/g;
			}

			# Filter in arrays.
			while ($regexp =~ /\(\@(.*?)\)/i) {
				my $o = $1;
				my $name = $o;
				my $rep = '';
				if (exists $self->{botarrays}->{$name}) {
					$rep = '(' . join ('|', @{$self->{botarrays}->{$name}}) . ')';
				}
				$regexp =~ s/\(\@$o\)/$rep/ig;
			}

			# Filter in botvariables.
			while ($regexp =~ /<bot (.*?)>/i) {
				my $o = $1;
				my $value = $self->{botvars}->{$o};
				$value =~ s/[^A-Za-z0-9 ]//g;
				$value = lc($value);
				$regexp =~ s/<bot $o>/$value/ig;
			}

			# Match?
			if ($string =~ /^$regexp$/i) {
				push (@result, "$trigger (topic: $topic) at $self->{syntax}->{$topic}->{$trigger}->{ref}");
			}
		}
	}

	return @result;
}

sub splitSentences {
	my ($self,$msg) = @_;

	# Split at sentence-splitters?
	if ($self->{split_sentences}) {
		my @syms = ();
		my @splitters = split(/\s+/, $self->{sentence_splitters});
		foreach my $item (@splitters) {
			$item =~ s/([^A-Za-z0-9 ])/\\$1/g;
			push (@syms,$item);
		}

		my $regexp = join ('|',@syms);

		my @sentences = split(/($regexp)/, $msg);
		return @sentences;
	}
	else {
		return $msg;
	}
}

sub formatMessage {
	my ($self,$msg) = @_;

	# Lowercase the string.
	$msg = lc($msg);

	# Get the words and run substitutions.
	my @words = split(/\s+/, $msg);
	my @new = ();
	foreach my $word (@words) {
		if (exists $self->{substitutions}->{$word}) {
			$word = $self->{substitutions}->{$word};
		}
		push (@new, $word);
	}

	# Reconstruct the message.
	$msg = join (' ',@new);

	# Remove punctuation and such.
	$msg =~ s/[^A-Za-z0-9 ]//g;
	$msg =~ s/^\s//g;
	$msg =~ s/\s$//g;

	return $msg;
}

sub mergeWildcards {
	my ($self,$string,%stars) = @_;

	foreach my $star (keys %stars) {
		# print "Converting <star$star> to $stars{$star}\n" if defined $stars{$star};
		$string =~ s/<star$star>/$stars{$star}/ig;
	}
	$string =~ s/<star>/$stars{1}/ig if defined $stars{1};

	return $string;
}

sub stringUtil {
	my ($self,$type,$string) = @_;

	if ($type eq 'uppercase') {
		return uc($string);
	}
	elsif ($type eq 'lowercase') {
		return lc($string);
	}
	elsif ($type eq 'sentence') {
		$string = lc($string);
		return ucfirst($string);
	}
	elsif ($type eq 'formal') {
		$string = lc($string);
		my @words = split(/ /, $string);
		my @out = ();
		foreach my $word (@words) {
			push (@out, ucfirst($word));
		}
		return join (" ", @out);
	}
	else {
		return $string;
	}
}

1;
__END__

=head1 NAME

Chatbot::RiveScript - Rendering Intelligence Very Easily

=head1 SYNOPSIS

  use Chatbot::RiveScript;

  # Create a new RiveScript interpreter.
  my $rs = new Chatbot::RiveScript;

  # Define a macro.
  $rs->setSubroutine (weather => \&weather);

  # Load in some RiveScript documents.
  $rs->loadDirectory ("./replies");

  # Load in another file.
  $rs->loadFile ("./more_replies.rs");

  # Stream in yet more replies.
  $rs->stream ('! global split_sentences = 1');

  # Sort them.
  $rs->sortReplies;

  # Grab a response.
  my @reply = $rs->reply ('localhost','Hello RiveScript!');
  print $reply[0] . "\n";

=head1 DESCRIPTION

RiveScript was formerly known as Chatbot::Alpha. However, Chatbot::Alpha's
syntax is B<not> compatible with RiveScript.

RiveScript is a simple input/response language. It is simple, easy to learn,
and mimics and perhaps even surpasses the power of AIML (Artificial Intelligence
Markup Language).

=head1 PUBLIC METHODS

=head2 new

Creates a new Chatbot::RiveScript instance. Pass in any defaults here.

=head2 setSubroutine (OBJECT_NAME => CODEREF)

Define a macro (see L<"OBJECT MACROS">)

=head2 loadDirectory (DIRECTORY)

Load a directory of RiveScript (.rs) files.

=head2 loadFile (FILEPATH[, STREAM])

Load a single file. Don't worry about the STREAM argument, it is handled
in the stream() method.

=head2 stream (CODE)

Stream RiveScript code directly into the module.

=head2 sortReplies

Sorts the replies. This is ideal for matching purposes. If you fail to
do so and just go ahead and call reply(), you'll get a nasty Perl warning.
It will sort them for you anyway, but it's always recommended to sort them
yourself. For example, if you sort them and then load new replies, the new
replies will not be matchable because the sort cache hasn't updated.

=head2 reply (USER_ID, MESSAGE)

Get a reply from the bot. This will return an array. The values of this
array would be all the replies (i.e. if you use {nextreply} in a response
to return multiple).

=head2 search (STRING)

Search all loaded replies for every trigger that STRING matches. Returns an
array of results, containing the trigger, what topic it was under, and the
reference to its file and line number.

=head2 setGlobal (VARIABLE => VALUE, ...)

Set a global variable directly from Perl (alias for B<! global>)

=head2 setVariable (VARIABLE => VALUE, ...)

Set a botvariable (alias for B<! var>)

=head2 setSubstitution (BEFORE => AFTER, ...)

Set a substitution setting (alias for B<! sub>)

=head2 setUservar (USER_ID, VARIABLE => VALUE, ...)

Set a user variable (alias for <set var=value>)

=head2 getUservars (USER_ID)

Get all variables for a user, returns a hash reference. (alias for <get var>
for every variable). If you don't provide a USER_ID, or provide '__rivescript__'
(see L<"RESERVED VARIABLES">), it will return an array reference of hash references,
to get variables of all users.

=head1 PRIVATE METHODS

These methods are called on internally and should not be called by you.

=head2 debug (MESSAGE)

# print a debug message.

=head2 intReply (USER_ID, MESSAGE)

This should not be called. Call B<reply> instead. This method assumes
that the variables are neatly formatted and may cause serious consequences
for passing in badly formatted data.

=head2 splitSentences (STRING)

Splits string at the sentence-splitters and returns an array.

=head2 formatMessage (STRING)

Formats the message (runs substitutions, removes punctuation, etc)

=head2 mergeWildcards (STRING, HASH)

Merges the hash from HASH into STRING, where the keys in HASH should be
from 1 to 100, for the wildcard captor.

=head2 stringUtil (TYPE, STRING)

Called on for string format tags (uppercase, lowercase, formal, sentence).

=head1 FORMAT

RiveScript documents have a simple format: they're a line-by-line
language. The first symbol(s) are the commands, and the following text
is typically the command's data.

In its most simple form, a valid RiveScript entry looks like this:

  + hello bot
  - Hello human.

=head1 RIVESCRIPT COMMANDS

The following are the commands that RiveScript supports.

=over 4

=item B<! (Definition)>

The ! command is for definitions. These are one of the few stand-alone
commands (ones that needn't be part of a bigger reply group). They are
to define variables and arrays. Their format is as follows:

  ! type variable = value

  type     = the variable type
  variable = the name of the variable
  value    = the variable's value

The supported types are as follows:

  global - Global settings (top-level things)
  var    - BotVariables (i.e. the bot's name, age, etc)
  array  - An array
  sub    - A substitution pattern

=item B<E<lt> and E<gt> (Label)>

The E<lt> and E<gt> commands are for defining labels. A label is used to treat
a part of code differently. Currently there are three uses for labels:
B<begin>, B<topic>, and B<object>. Example usage:

  // Define a topic
  > topic some_topic_name

    // there'd be some triggers here

  < topic
  // close the topic

=item B<+ (Trigger)>

The + command is the basis for all triggers. The + command is what the
user has to say to activate the reply set. In the example,

  + hello bot
  - Hello human.

The user would say "hello bot" only to get a "Hello human." back.

=item B<% (Previous)>

The % command is for drawing a user back to complete a thought. You
might say it's sort of like E<lt>thatE<gt> in AIML. Example:

  + ask me a question
  - Do you have any pets?

  + yes
  % do you have any pets
  - What kind of pet?

  // and so-on...

=item B<- (Response)>

The - command is the response. The - command has several uses, depending
on its context. For example, in the "hello bot/hello human" example, one
+ with one - gets a one-way question/answer scenario. If more than one -
is used, a random one is chosen (and some may be weighted). There are many
other uses that we'll get into later.

=item B<^ (Continue)>

The ^Continue command is for extending the previous command down a line.
Normally, this would only reply to -REPLY but in B<Version 0.06> this
has expanded to handle extensions of multiple types of commands.

The commands that can be continued with ^Continue:

  ! global
  ! var
  ! array
  + trigger
  % previous
  - response
  @ redirection

Sometimes your -REPLY is too long to fit on one line, and you don't like
the idea of having a horizontal scrollbar. The ^ command will continue on
from the last -REPLY. For example:

  + tell me a poem
  - Little Miss Muffit sat on her tuffet\s
  ^ in a nonchalant sort of way.\s
  ^ With her forcefield around her,\s
  ^ the Spider, the bounder,\s
  ^ is not in the picture today.

Here are some examples of the other uses of ^Continue new with version
0.06:

  ! array colors  = red blue green yellow cyan fuchsia
  ^ white black gray grey orange pink
  ^ turqoise magenta gold silver

  ! var quote = How much wood would a woodchuck
  ^ chuck if a woodchuck could chuck wood?

  + how much wood would a woodchuck\s
  ^ chuck if a woodchuck could chuck wood
  - A whole forest. ;)

  + how much wood
  @ how much wood would a woodchuck\s
  ^ chuck if a woodchuck could chuck wood

B<Change Note:> In version 0.06, a continuation of a -REPLY no longer assumes
a space between the parts of the response. For an example, look up at the
"tell me a poem" example just above. You now need to include a \s (see L<"TAGS">)
to include a white space.

=item B<@ (Redirect)>

The @ command is for directing one trigger to another. For example, there
may be complicated ways people have of asking the same thing, and you don't
feel like making your main trigger handle all of them.

  + my name is *
  - Nice to meet you, {formal}<star1>{/formal}.

  + people around here call me *
  @ my name is <star1>

Redirections can also be used inline. See the L<"TAGS"> section for more details.

=item B<* (Conditions)>

The * command is used for checking conditionals. The format is:

  * variable=value => say this

For example, you might want to make a condition to differentiate male from
female users.

  + am i a guy or a girl
  * gender=male => You're a guy.
  * gender=female => You're a girl.
  - I don't think you ever told me what you are.

=item B<& (Perl)>

Sometimes RiveScript isn't powerful enough to do what you want. The & command
will execute Perl codes to handle these cases. Be sure to read through this
whole manpage before resorting to Perl, though. RiveScript has come a long way
since it was known as Chatbot::Alpha.

  + what is 2 plus 2
  - 500 Internal Error.
  # $reply = '2 + 2 = 4';

=item B<// (Comments)>

The comment syntax is //, as it is in other programming languages. Also,
/* */ comments may be used to span over multiple lines.

  // A one-line comment

  /*
    this comment spans
    across multiple lines
  */

=back

=head1 RIVESCRIPT HOLDS THE KEYS

The RiveScript engine was designed for your RiveScript brain to hold most of the
control. As little programming on the Perl side as possible has made it so that
your RiveScript can define its own variables and handle what it wants to. See
L<"A GOOD BRAIN"> for tips on how to approach this.

=head1 COMPLEXITIES OF THE TRIGGER

The + command can be used for more complex things as a simple, 100% dead-on
trigger. This part is passed through a regexp. Therefore, any regexp things
can be used in the trigger.

B<Note:> an asterisk * is always converted into (.*?) regardless of its context.
Keep this in mind.

B<Alternations:> You can use alternations in the triggers like so:

  + what (s|is) your (home|office|cell) phone number

Anything inside of parenthesis, or anything matched by asterisks, can be
obtained through the tags E<lt>star1E<gt> to E<lt>star100E<gt>. For example (keeping in mind
that * equals (.*?):

  + my name is *
  - Nice to meet you, <star1>.

B<Optionals:> You can use optional words in a trigger. These words don't have
to exist in the user's message but they I<can>. Example:

  + what is your [home] phone number
  - You can call me at 555-5555.

So that would match "I<what is your phone number>" as well as
"I<what is your home phone number>"

Optionals can have alternations in them too.

  + what (s|is) your [home|office|cell] phone number

B<Arrays:> This is why it's good to define arrays using the !define tag. The
best way to explain how this works is by example.

  // Make an array of color names
  ! array colors = red blue green yellow white black orange

  // Now the user can tell us their favorite color from the array
  + my favorite color is (@colors)
  - Really! Mine is <star1> too!

It turns your array into regexp form, B<(red|blue|green|yellow|...)> before matching
so it saves you a lot of work there. Not to mention arrays can be used in any number
of triggers! Just imagine how many triggers you can come up with where a color name
would be needed...

=head1 COMPLEXITIES OF THE RESPONSE

As mentioned above, the - command has many many uses.

B<One-way question/answer:> A single + and a single - will lead to a dead-on
question and answer reply.

B<Random Replies:> A single + with multiple -'s will yield random results
from among the responses. For example:

  + hello
  - Hey.
  - Hi.
  - Hello.

Would randomly return any of those three responses.

B<Conditional Fallback:> When using conditionals, you should always provide
at least one response to fall back on, in case every conditional returns false.

B<Perl Code Fallback:> When executing Perl code, you should always have a response
to fall back on [even if the Perl is going to redefine $reply for itself]. This is
in case of an eval error and the Perl couldn't do its thing.

B<Weighted Responses:> Yes, with random responses you can weight them! Responses
with higher weight will have a better chance of being chosen over ones with a low
weight. For example:

  + hello
  - Hello, how are you?{weight=49}
  - Yo, wazzup dawg?{weight=1}

In this case, "Hello, how are you?" will almost always be sent back. A 1 in 50
chance would return "Yo, wazzup dawg?" instead.

(as a side note: you don't need to set a weight to 1; 1 is implied for any
response without weight. Weights of less than 1 aren't acceptable)

=head1 BEGIN STATEMENT

B<Note:> BEGIN statements are not required. That being said, begin statements
are executed before any request.

B<How to define a BEGIN statement>

  > begin
    + request
    - {ok}
  < begin

Begin statements are sort of like topics. They are called first. If the response
given contains {ok} in it, then the module knows it's allowed to get a reply.
Also note that {ok} is replaced with the response. In this way, B<begin> might be
useful to format all responses in one way. For a good example:

  > begin

    // Don't give a reply if the bot is down for maintenance.
    + request
    * down=yes => The bot is currently deactivated for maintenance.
    - <font color="red"><b>{ok}</b></font>

  < begin

That would give the reply about the bot being under maintenance if the variable
"down" equals "yes." Else, it would give a response in red bold font.

B<Note:> At the time being, the only trigger that BEGIN ever receives is "request"

=head1 TOPICS

Topics are declared in a way similar to the BEGIN statement. The way to declare
and close a topic is generally as follows:

  > topic TOPICNAME
    ...
  < topic

The topic name should be unique, and only one word.

B<The Default Topic:> The default topic name is "random"

B<Setting a Topic:> To set a topic, use the {topic} tag (see L<"TAGS"> below). Example:

  + i hate you
  - You're not very nice. I'm going to make you apologize.{topic=apology}

  > topic apology
    + *
    - Not until you admit that you're sorry.

    + sorry
    - Okay, I'll forgive you.{topic=random}
  < topic

Always set topic back to "random" to break out of a topic.

=head1 OBJECT MACROS

Special macros (Perl routines) can be defined and then utilized in your RiveScript
code.

=head2 Inline Objects

New with version 0.04 is the ability to define objects directly within the RiveScript code. Keep in mind
that the code for your object is evaluated local to Chatbot::RiveScript. That being said, basic tips to
follow to make an object work:

  1) If it uses any module besides strict and warnings, that module must be explicitely
     declared within your object with a 'use' statement.
  2) If your object refers to any variables global to your main program, 'main::' must
     be prepended (i.e. '$main::hashref->{key}')
  3) If your object refers to a subroutine of your main program, 'main::' must be prepended
     (i.e. '&main::reload()')

The basic way is to do it like this:

  > object fortune
    my ($method,$msg) = @_;

    my @fortunes = (
       'You will be rich and famous',
       'You will meet a celebrity',
       'You will go to the moon',
    );

    return $fortunes [ int(rand(scalar(@fortunes))) ];
  < object

Note: the B<closing tag> (last line in the above example) is required for objects. An object isn't included until the closing tag
is found.

=head2 Define an Object from Perl

This is done like so:

  # Define a weather lookup macro.
  $rs->setSubroutine (weather => \&weather_lookup);

The code of the subroutine would be basically the same as it would be in the example for Inline Objects.
Basically, think of the "E<gt> object fortune" as "sub fortune {" and the "E<lt> object" as "}" and it's a little
easier to visualize. ;)

=head2 Call an Object

You can use a macro within a reply such as this example:

  + give me the local weather for *
  - Weather for &weather.cityname(<star1>):\n\n
  ^ Temperature: &weather.temp(<star1>)\n
  ^ Feels Like: &weather.feelslike(<star1>)

The subroutine "weather_lookup" will receive two variables: the method and the
arguments. The method would be the bit following the dot (i.e. "cityname",
"temp", or "feelslike" in this example). The arguments would be the value of
<star1>.

Whatever weather_lookup would return is inserted into the reply in place of the
macro call.

=head1 TAGS

Special tags can be inserted into replies and redirections. They are as follows:

=head2 E<lt>starE<gt>, E<lt>star1E<gt> - E<lt>star100E<gt>

These tags will insert the values of $1 to $100, as matched in the regexp, into
the reply. They go in order from left to right. <star> is an alias for <star1>.

=head2 E<lt>input1E<gt> - E<lt>input9E<gt>; E<lt>reply1E<gt> - E<lt>reply9E<gt>

Inserts the last 1 to 9 things the user said, and the last 1 to 9 things the bot
said, respectively. Good for things like "You said hello and then I said hi and then
you said what's up and then I said not much"

=head2 E<lt>idE<gt>

Inserts the user's ID.

=head2 E<lt>botE<gt>

Insert a bot variable (defined with B<! var>).

  + what is your name
  - I am <bot name>, created by <bot companyname>.

This variable can also be used in triggers.

  + my name is <bot name>
  - <set name=<bot name>>What a coincidence, that's my name too!

=head2 E<lt>getE<gt>, E<lt>setE<gt>

Get and set a user variable. These are local variables for each user.

  + my name is *
  - <set name={formal}<star1>{/formal}>Nice to meet you, <get name>!

  + who am i
  - You are <get name> aren't you?

=head2 {topic=...}

The topic tag. This will set the user's topic to something else (see L<"TOPICS">). Only
one of these should be in a response, and in the case of duplicates only the first
one is evaluated.

=head2 {nextreply}

Breaks the reply into two (or more) parts there. Will cause the B<reply> method
to return multiple responses.

=head2 {@...}

An inline redirection. These work like normal redirections, except are inserted
inline into a reply.

  + * or something
  - Or something. {@<star1>}

=head2 {!...}

An inline definition. These can be used to (re)set variables. This tag is invisible
in the final response of the bot; the changes are made silently.

=head2 {random}...{/random}

Will insert a bit of random text. This has two syntaxes:

  Insert a random word (separate by spaces)
  {random}red blue green yellow{/random}

  Insert a random phrase (separate by pipes)
  {random}Yes sir.|No sir.{/random}

=head2 {formal}...{/formal}

Will Make Your Text Formal

=head2 {sentence}...{/sentence}

Will make your text sentence-cased.

=head2 {uppercase}...{/uppercase}

WILL MAKE THE TEXT UPPERCASE.

=head2 {lowercase}...{/lowercase}

will make the text lowercase.

=head2 \s

(New with Version 0.06) Inserts a white space. Simple as that.

In version 0.06, reply continuations (- ^) would insert a space automatically
when combining a reply. This is no longer the case. The \s tag must be included
if you want spaces in the continuation.

=head2 \n

(New with Version 0.06) Inserts a newline. Note that this only happens when
you request a B<reply()> from the module.

=head1 RESERVED VARIABLES

The following are all the reserved variables and values within RiveScript's
processor.

=head2 Reserved Global Variables

These variables cannot be overwritten with the B<! global> command:

  reserved replies array syntax streamcache botvars uservars
  botarrays sort users substitutions

=head2 Reserved Topic Names

The following topic names are reserved and should never be (re)created in
your RiveScript files:

  __begin__   (used for the BEGIN method)
  __that__*   (used for the %PREVIOUS command)

=head2 Reserved User_ID's

These are the reserved User ID's that you should not pass in to the B<reply>
method when getting a reply.

  __rivescript__   (to query the BEGIN method)

=head1 A GOOD BRAIN

Since RiveScript leaves a lot of control up to the brain and not the Perl code,
here are some general tips to follow when writing your own brain:

B<Make a config file.> This would probably be named "config.rs" and it would
handle all your definitions. For example it might look like this:

  // Set up globals
  ! global debug = 0
  ! global split_sentences = 1
  ! global sentence_splitters = . ! ; ?

  // Set a variable to say that we're active.
  ! var active = yes

  // Set up botvariables
  ! var botname = Rive
  ! var botage = 5
  ! var company = AiChaos Inc.
  // note that "bot" isn't required in these variables,
  // it's only there for readibility

  // Set up substitutions
  ! sub won't = will not
  ! sub i'm = i am
  // etc

  // Set up arrays
  ! array colors = red green blue yellow cyan fuchsia ...

Here are a list of all the globals you might want to configure.

  split_sentences    - Whether to do sentence-splitting (1 or 0, default 1)
  sentence_splitters - Where to split sentences at. Separate items with a single
                       space. The defaults are:   ! . ? ;
  debug              - Debug mode (1 or 0, default 0)

B<Make a begin file.> This file would handle your BEGIN code. Again, this isn't
required but has its benefits. This file might be called "begin.rs" (or you could
include it in config.rs if you're a micromanager).

Your begin file could check the "active" variable we set in the config file to
decide if it should give a reply.

  > begin
    + request
    * active=no => Sorry but I'm deactivated right now!
    - {ok}
  < begin

These are the basic tips, just for organizational purposes.

=head1 SEE OTHER

You might want to take a look at L<Chatbot::Alpha>, this module's predecessor.

=head1 KNOWN BUGS

None yet known.

=head1 CHANGES

  Version 0.06
  - Extended ^CONTINUE to cover more commands
  - Revised POD

  Version 0.05
  - Fixed a bug with optionals. If they were used at the start or end
    of a trigger, the trigger became unmatchable. This has been fixed
    by changing ' ' into '\s*'

  Version 0.04
  - Added support for optional parts of the trigger.
  - Begun support for inline objects to be created.

  Version 0.03
  - Added search() method.
  - <bot> variables can be inserted into triggers now (for example having
    the bot reply to its name no matter what its name is)

  Version 0.02
  - Fixed a regexp bug; now it stops searching when it finds a match
    (it would cause errors with $1 to $100)
  - Fixed an inconsistency that didn't allow uservars to work in
    conditionals.
  - Added <id> tag, useful for objects that need a unique user to work
    with.
  - Fixed bug that lets comments begin with more than one set of //

  Version 0.01
  - Initial Release

=head1 TO-DO LIST

Feel free to offer any ideas. ;)

=head1 AUTHOR

  Cerone Kirsle, kirsle --at-- rainbowboi.com

=head1 COPYRIGHT AND LICENSE

    Chatbot::RiveScript - Rendering Intelligence Very Easily
    Copyright (C) 2006  Cerone J. Kirsle

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

=cut