use strict;
package NetServer::Portal::Pi;
use NetServer::Portal qw(term);

# Lots of code is borrowed from Devel::Symdump.

NetServer::Portal->register(cmd => "pi",
			    title => "Perl Introspector",
			    package => __PACKAGE__);

sub new {
    my ($class, $client) = @_;
    my $o = $client->conf(__PACKAGE__);
    $o->{Package} ||= [];
    $o->{Path} ||= [];
    $o->{I} ||= [];
    $o->{O} ||= [];
    $o->{output_line} ||= 0;
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
    my $output_rows = $rows - 4;
    if (@{$o->{O}}) {
	my $O = $o->{O}[0];
	my $max_line = @$O - $output_rows/2;
	$max_line = 0
	    if $max_line < 0;
	$o->{output_line} = 0
	    if $o->{output_line} < 0;
	$o->{output_line} = $max_line
	    if $o->{output_line} > $max_line;
	my $to = $o->{output_line} + $output_rows - 1;
	$to = $#$O if
	    $to > $#$O;
	for (my $lx= $o->{output_line}; $lx <= $to; $lx++) {
	    my $l = $O->[$lx];
	    my $part;
	    if ($lx == $o->{output_line} or $lx == $to) {
		my $note = "[$lx]";
		$part = substr $l, 0, $cols - length($note) - 2;
		$part .= ' ' x ($cols - length($part) - length($note) - 1);
		$part .= $note;
	    } else {
		$part = substr $l, 0, $cols-1;
	    }
	    $part .= "\n"
		if $part !~ /\n$/;
	    $s .= $part;
	}
	$s .= "\n" x ($output_rows + $o->{output_line} - $to - 1);
    } else {
	$s .= "\n" x $output_rows;
    }
    $s .= "\n";
    $s .= $ln->($o->{error});
    $s .= (join('::', @{$o->{Package}}) || 'main').' ';
    $s;
}

sub cmd {
    no strict 'refs';
    my ($o, $c, $in) = @_;
    
    my $conf = $c->conf;
    my $rows = $conf->{rows};
    my $cols = $conf->{cols};

    # these are invisible to command history
    if (!$in) {
	return
    } elsif ($in eq '.') {
	$o->{output_line} += $rows/2; #XXX
	return;
    } elsif ($in eq ',') {
	$o->{output_line} -= $rows/2; #XXX
	return;
    } elsif ($in eq 'history') {
	my @tmp = @{$o->{I}};
	unshift @{$o->{O}}, \@tmp;
	return;
    }

    push @{$o->{I}}, $in;
    shift @{$o->{I}} if @{$o->{I}} > 16;

    if ($in eq 'ls') {  # add lots of flags XXX
	my @got;
	my $pack = join('::', @{$o->{Package}}) || 'main';
	while (my ($key,$val) = each(%{*{"$pack\::"}})) {
	    local(*ENTRY) = $val;
            if (defined $val && defined *ENTRY{HASH} && $key =~ /::$/ &&
                    $key ne "main::")
            {
                my($p) = $pack ne "main" ? "$pack\::" : "";
                ($p .= $key) =~ s/::$//;
		push @got, $p;
	    }
	}
	@got = sort { $a cmp $b } @got;
	unshift @{$o->{O}}, \@got;
    } elsif ($in =~ s/^cd\s+//) {
	if ($in eq '..') {
	    pop @{$o->{Package}};
	} else {
	    push @{$o->{Package}}, $in;
	}
    } else {
	$o->{error} = "? $in";
    }
    pop @{$o->{O}} if @{$o->{O}} > 16;
}

1;
