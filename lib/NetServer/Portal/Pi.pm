use strict;
package NetServer::Portal::Pi;
use NetServer::Portal qw(term);
use Data::Dumper;

# Lots of code is borrowed from Devel::Symdump.  (Thanks!)
# clone Vim commands

NetServer::Portal->register(cmd => "pi",
			    title => "Perl Introspector",
			    package => __PACKAGE__);

my $Help = "*** Perl Introspector ***


Type ':help' to load this buffer!

output buffer commands:
  ,        previous screen full
  .        next screen full
  :10      jump to line 10 (like vi)
  /REx     search for /REx/

  <        previous buffer
  >        next buffer

  :history show history of commands

navigational commands:

  ls [-1fpv]
    -1 single column format
    -f functions
    -p sub-packages
    -v variables (scalars, arrays, hashes, IOs)

  cd ..          move to preceeding \"directory\"
  cd <package>   use 'ls' to see options
  cd \$code       make evaluate to a REF
";

sub new {
    my ($class, $client) = @_;
    my $o = $client->conf(__PACKAGE__);
    $o->{Package} ||= [];
    $o->{Path} ||= [];
    $o->{I} ||= [];
    if (!exists $o->{O}) {
	$o->{O} = [ { line => 0, buf => [split /\n/, $Help] } ];
    }
    $o->{buffer} ||= 0;
    $o;
}

sub update {
    my ($o, $c) = @_;
    
    my $ln = $c->format_line;
    my $conf = $c->conf;
    my $rows = $conf->{rows};
    my $cols = $conf->{cols};

    my $s = term->Tputs('cl',1,$c->{io}->fd);

    # optionally wrap lines longer than $cols XXX

    # turn off line numbers with
    # :set number

    my $output_rows = $rows - 2;
    if (@{$o->{O}}) {
	my $cur = $o->{O}[$o->{buffer}];
	my $O = $cur->{buf};
	my $max_line = @$O - $output_rows/2;
	$max_line = 0
	    if $max_line < 0;
	$cur->{line} = 0
	    if $cur->{line} < 0;
	$cur->{line} = $max_line
	    if $cur->{line} > $max_line;
	my $to = $cur->{line} + $output_rows - 1;
	$to = $#$O if
	    $to > $#$O;
	for (my $lx= $cur->{line}; $lx <= $to; $lx++) {
	    my $l = $O->[$lx];
	    my $note = '';
	    if ($lx == $cur->{line} or $lx == $to) {
		$note = " [".($lx+1)."]";
	    } elsif (($lx+1) % 4 == 0) {
		$note = " .";
	    }
	    my $part = substr $l, 0, $cols - length($note) - 1;
	    if ($note) {
		$part .= ' ' x ($cols - length($part) - length($note) - 1);
		$part .= $note;
	    }

	    $part .= "\n"
		if $part !~ /\n$/;
	    $s .= $part;
	}
	$s .= "\n" x ($output_rows + $cur->{line} - $to - 1);
    } else {
	$s .= "\n" x $output_rows;
    }
    $s .= "\n";
    $s .= $ln->($o->{error});
    $s .= (join('::', @{$o->{Package}}) || 'main').' ';
    $s;
}

sub add_buffer {
    my ($o, $lines) = @_;
    unshift @{$o->{O}}, { line => 0, buf => $lines };
    $o->{buffer} = 0;
}

sub cmd {
    no strict 'refs';
    my ($o, $c, $in) = @_;
    
    my $conf = $c->conf;
    my $Rows = $conf->{rows};
    my $Cols = $conf->{cols};

    # these are invisible to command history
    if (!$in) {
	return
    } elsif ($in =~ m/^(\.+)$/) {
	$o->{O}[$o->{buffer}]{line} += length($1) * $Rows/2; #XXX
	return;
    } elsif ($in =~ m/^(,+)$/) {
	$o->{O}[$o->{buffer}]{line} -= length($1) * $Rows/2; #XXX
	return;
    } elsif ($in =~ m/^(\<+)$/) {
	$o->{buffer} += length $1;
	$o->{buffer} = $#{$o->{O}} if
	    $o->{buffer} > $#{$o->{O}};
	return;
    } elsif ($in =~ m/^(\>+)$/) {
	$o->{buffer} -= length $1;
	$o->{buffer} = 0 if
	    $o->{buffer} < 0;
	return;
    } elsif ($in =~ s,^/,,) {
	if (!$in) {
	    $in = $o->{last_search};
	} else {
	    $o->{last_search} = $in;
	}
	my $cur = $o->{O}[$o->{buffer}];
	my $buf = $cur->{buf};
	my $at = $cur->{line};
	my $ok;
	for (my $x=$at; $x < @$buf; $x++) {
	    if ($buf->[$x] =~ m/$in/) {
		next if $cur->{line} == $x;  # try to do something
		$cur->{line} = $x;
		$ok=1;
		last;
	    }
	}
	if (!$ok) {
	    $o->{error} = "No match for /$in/.";
	}
	return;
    } elsif ($in =~ s/^:\s*//) {
	if ($in =~ m/^(\d+)$/) {
	    $o->{O}[$o->{buffer}]{line} = $1 - $Rows/2; #XXX
	} elsif ($in eq 'help') {
	    $o->add_buffer([split /\n/, $Help]);
	} elsif ($in eq 'history') {
	    my @tmp = @{$o->{I}};
	    $o->add_buffer(\@tmp);
	} else {
	    $o->{error} = "$in?  Try :help for a list of commands.";
	}
	return;
    }

    push @{$o->{I}}, $in;
    shift @{$o->{I}} if @{$o->{I}} > 16;

    if ($in =~ m/^ls (\s+ -[1apfv]+)? $/x) {
	my %f;
	if ($1) {
	    my $flags = $1;
	    $flags =~ s/^\s*-//;
	    ++$f{$_} for split / */, $flags;
	}
	if ($f{a}) {
	    ++$f{$_} for qw(p f v);
	}
	++$f{p} if keys %f == 0;
	my @got;
	my $pack = join('::', @{$o->{Package}}) || 'main';

	# TODO:
	#
	# this code gives too many false positives
	#
	# cope with control chars

	while (my ($key,$val) = each(%{*{"$pack\::"}})) {
	    next if !defined $val;
	    local(*ENTRY) = $val;
            #### PACKAGE ####
            if ($f{p} and defined *ENTRY{HASH} &&
		$key =~ /::$/ && $key ne "main::")
            {
		push @got, $key;
	    }
            #### FUNCTION ####
            if ($f{f} and defined *ENTRY{CODE}) {
		push @got, "\&$key";
            }
            #### SCALAR ####
            if ($f{v} and defined *ENTRY{SCALAR}) {
		push @got, "\$" . $key;
            }
            #### ARRAY ####
            if ($f{v} and defined *ENTRY{ARRAY}) {
		push @got, "\@$key";
            }
            #### HASH ####
            if ($f{v} and defined *ENTRY{HASH} &&
		$key !~ /::/)
	    {
		push @got, "\%$key";
            }
            #### IO #### (only 5.003_10+)
	    if ($f{v} and defined *ENTRY{IO}){
		push @got, $key;
	    }
	}
	@got = sort { $a cmp $b } @got;
	if (!$f{1}) {
	    my $maxlen=0;
	    for (@got) {
		$maxlen = length $_
		    if $maxlen < length $_;
	    }
	    ++$maxlen;
	    my $cols = int $Cols / $maxlen;
	    if ($cols > 1) {
		my $per = int(($cols + @got - 1) / $cols);
		my @grid;
		for (my $l=0; $l < $per; $l++) {
		    my $row='';
		    for (my $c=0; $c < $cols; $c++) {
			my $cel = $got[$l + $c*$per] || '';
			$cel .= ' 'x($maxlen - length $cel);
			$row .= $cel;
		    }
		    push @grid, $row;
		}
		@got = @grid;
	    }
	}
	$o->add_buffer(\@got);

    } elsif ($in =~ s/^cd\s+//) {
	if ($in eq '..') {
	    pop @{$o->{Package}};
	} elsif ($in =~ m/^ (\w+) (::)? $/x) {
	    push @{$o->{Package}}, $1;
	} else {
	    $o->{error} = "cd $in: not implemented";
	}
    } else {
	$in .= "\n" if $in !~ /\n$/;
	my @warn;
	local $SIG{__WARN__} = sub {
	    push @warn, @_;
	};
	my $pack = join('::', @{$o->{Package}}) || 'main';
	my @eval = eval "no strict;\n#line 1 \"input\"\npackage $pack;\n$in";
	if ($@) {
	    $o->add_buffer([split /\n/, "package $pack;\n$in\n---\n$@"]);
	} else {
	    my $warns='';
	    $warns = join('', @warn)."---\n"
		if @warn;
	    my $Dumper = Data::Dumper->new(\@eval);
	    $o->add_buffer([split /\n/, "package $pack;\n$in---\n".$warns.
			    $Dumper->Dump]);
	}
    }
    pop @{$o->{O}} if @{$o->{O}} > 16;
}

1;
