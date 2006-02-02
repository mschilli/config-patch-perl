###########################################
# Config::Patch -- 2005, Mike Schilli <cpan@perlmeister.com>
###########################################

###########################################
package Config::Patch;
###########################################

use strict;
use warnings;
use MIME::Base64;
use Set::IntSpan;
use Log::Log4perl qw(:easy);
use Fcntl qw/:flock/;

our $VERSION     = "0.03";
our $PATCH_REGEX = qr{^#\(Config::Patch-(.*?)-(.*?)\)}m;

###########################################
sub new {
###########################################
    my($class, %options) = @_;

    my $self = {
        flock   => undef,
        %options,
        locked => undef,
    };

        # Open file read/write (eventually for locking)
    open my $fh, "+<$self->{file}" or 
        LOGDIE "Cannot open $self->{file} ($!)";
    $self->{fh} = $fh;

    bless $self, $class;
}

###########################################
sub key {
###########################################
    my($self, $key) = @_;

    $self->{key} = $key if defined $key;
    return $self->{key};
}

###########################################
sub append {
###########################################
    my($self, $string) = @_;

    $self->lock();

        # Has the file been patched with this key before?
    my(undef, $keys) = $self->patches();

    if(exists $keys->{$self->{key}}) {
        INFO "Append cancelled: File already patched with key $self->{key}";
        $self->unlock();
        return undef;
    }

    my $data = slurp($self->{file});
    $data .= "\n" unless substr($data, -1, 1) eq "\n";

    $data .= $self->patch_marker("append");
    $data .= $string;
    $data .= $self->patch_marker("append");

    blurt($data, $self->{file});

    $self->unlock();
}

###########################################
sub lock {
###########################################
    my($self) = @_;

        # Ignore if locking wasn't requested
    return if ! $self->{flock};

        # Already locked?
    if($self->{locked}) {
        $self->{locked}++;
        return 1;
    }

    open my $fh, "+<$self->{file}" or 
        LOGDIE "Cannot open $self->{file} ($!)";

    flock($fh, LOCK_EX);

    $self->{fh} = $fh;

    $self->{locked} = 1;
}

###########################################
sub unlock {
###########################################
    my($self) = @_;

        # Ignore if locking wasn't requested
    return if ! $self->{flock};

    if(! $self->{locked}) {
            # Not locked?
        return 1;
    }

    if($self->{locked} > 1) {
            # Multiple lock released?
        $self->{locked}--;
        return 1;
    }

        # Release the last lock
    flock($self->{fh}, LOCK_UN);
    $self->{locked} = undef;
    1;
}

###########################################
sub freeze {
###########################################
    my($string) = @_;

    # Hide an arbitrary string in a comment
    my $encoded = encode_base64($string);

    $encoded =~ s/^/# /gm;
    return $encoded;
}

###########################################
sub thaw {
###########################################
    my($string) = @_;

    # Decode a hidden string 
    $string =~ s/^# //gm;
    my $decoded = decode_base64($string);
    return $decoded;
}

###########################################
sub replstring_extract {
###########################################
    my($patch) = @_;

    # Find the replace string in a patch
    my $replace_marker = replace_marker();
    $replace_marker = quotemeta($replace_marker);
    if($patch =~ /^$replace_marker\n(.*?)
                  ^$replace_marker/xms) {
        my $repl = $1;
        $patch =~ s/^$replace_marker.*?
                    ^$replace_marker\n//xms;

        return(thaw($repl), $patch);
    }

    return undef;
}

###########################################
sub replstring_hide {
###########################################
    my($replstring) = @_;

    # Add a replace string to a patch
    my $replace_marker = replace_marker();
    my $encoded = $replace_marker . "\n" .
                  freeze($replstring) .
                  $replace_marker .
                  "\n";

    return $encoded;
}

###########################################
sub patched {
###########################################
    my($self) = @_;

    my($patchlist, $patches) = $self->patches();
    return $patches->{$self->{key}};
}

###########################################
sub patches {
###########################################
    my($self) = @_;

    my @patches = ();
    my %patches = ();

    $self->{forbidden_zones} = Set::IntSpan->new();

    $self->file_parse(
        sub { my($p, $k, $m, $t, $p1, $p2) = @_;
              DEBUG "union: p1=$p1 p2=$p2";
              $p->{forbidden_zones} = Set::IntSpan::union(
                                          $p->{forbidden_zones}, 
                                          "$p1-$p2");
              DEBUG "forbidden zones: ", 
                    Set::IntSpan::run_list($p->{forbidden_zones});
              push @patches, [$k, $m, $t, $p1, $p2];
              $patches{$k}++;
            },
        sub { },
    );

    return \@patches, \%patches;
}

###########################################
sub replace {
###########################################
    my($self, $search, $replace) = @_;

    $self->lock();

        # Has the file been patched with this key before?
    my(undef, $keys) = $self->patches();

    if(exists $keys->{$self->{key}}) {
        INFO "Replace cancelled: File already patched with key $self->{key}";
        $self->unlock();
        return undef;
    }

    if(ref($search) ne "Regexp") {
        LOGDIE "replace: search parameter not a regex";
    }

    if(length $replace and
       substr($replace, -1, 1) ne "\n") {
        $replace .= "\n";
    }

    open FILE, "<$self->{file}" or
        LOGDIE "Cannot open $self->{file}";
    my $data = join '', <FILE>;
    close FILE;

    my $positions = $self->full_line_match($data, $search);
    my @pieces    = ();
    my $rest      = $data;
    my $offset    = 0;

    for my $pos (@$positions) {
        my($from, $to) = @$pos;
        my $before = substr($data, $offset, $from-$offset);
        $rest      = substr($data, $to+1);
        DEBUG "patch: from=$from to=$to off=$offset ",
              "before='$before' rest='$rest'";
        my $patch  = $self->patch_marker("replace") .
                     $replace .
                     replstring_hide(substr($data, $from, $to - $from + 1)) .
                     $self->patch_marker("replace");

        push @pieces, $before, $patch;
        $offset = $to + 1;
    }

    push @pieces, $rest;
    $data = join '', @pieces;

    open FILE, ">$self->{file}" or
        LOGDIE "Cannot open $self->{file}";
    print FILE $data;
    close FILE;

    $self->unlock();
    return scalar @$positions;
}

###########################################
sub full_line_match {
###########################################
    my($self, $string, $rex) = @_;

    DEBUG "Trying to match '$string' with /$rex/";

    # Try a regex match and if it succeeds, extend the match
    # to cover the full first and last line. Return a ref to
    # an array of from-to offsets of all (extended) matching
    # regions.
    my @positions = ();

    while($string =~ /($rex)/g) {
        my $first = pos($string) - length($1);
        my $last  = pos($string) - 1;

        DEBUG "Found match at pos $first-$last ($1) pos=", pos($string);

            # Is this match located in any of the forbidden zones?
        my $intersect = Set::IntSpan::intersect(
                            $self->{forbidden_zones}, "$first-$last");
        unless(Set::IntSpan::empty($intersect)) {
            DEBUG "Match was in forbidden zone - skipped";
            next;
        }

            # Go back to the start of the line
        while($first and
              substr($string, $first, 1) ne "\n") {
            $first--;
        }
        $first += 1 if $first;

            # Proceed until the end of the line
        while($last < length($string) and
              substr($string, $last, 1) ne "\n") {
            $last++;
        }

        DEBUG "Match positions corrected to $first-$last (line start/end)";

            # Ignore overlapping matches
        if(@positions and $positions[-1]->[1] > $first) {
            DEBUG "Detected overlap (two matches in same line) - skipped";
            next;
        }

        push @positions, [$first, $last];
    }

    return \@positions;
}

###########################################
sub comment_out {
###########################################
    my($self, $search) = @_;

        # Same as "replace by nothing"
    return $self->replace($search, "");
}

###########################################
sub remove {
###########################################
    my($self) = @_;

    my $new_content = "";

    $self->file_parse(
        sub { my($p, $k, $m, $t, $p1, $p2, $header) = @_;
              DEBUG "Remove: '$t' ($p1-$p2)";
              if($k eq $self->{key}) {
                  if($m eq "replace") {
                       # We've got a replace section, extract its
                       # hidden content and re-establish it
                       my($hidden, $stripped) = replstring_extract($t);
                       $new_content .= $hidden;
                  } else {
                       # Replace by nothing
                  }
              } else {
                      # This isn't our patch
                  $new_content .= $header . $t . $header;
              }
            },
        sub { my($p, $t) = @_;
              $new_content .= $t;
            },
    );

    open FILE, ">$self->{file}" or
        LOGDIE "Cannot open $self->{file} ($!)";
    print FILE $new_content;
    close FILE;
}

###########################################
sub file_parse {
###########################################
    my($self, $patch_cb, $text_cb) = @_;

    $self->lock();

    open FILE, "<$self->{file}" or
        LOGDIE "Cannot open $self->{file}";

    my $in_patch  = 0;
    my $patch     = "";
    my $text      = "";
    my $start_pos;
    my $end_pos;
    my $pos       = 0;
    my $header;

    while(<FILE>) {
        $pos += length($_);
        $patch .= $_ if $in_patch and $_ !~ $PATCH_REGEX;

            # text line?
        if($_ !~ $PATCH_REGEX and !$in_patch) {
            $text .= $_;
        }

            # closing line of patch
        if($_ =~ $PATCH_REGEX and 
           $in_patch) {
            $end_pos = $pos - 1;
            $patch_cb->($self, $1, $2, $patch, $start_pos, $end_pos, $header);
            $patch = "";
        }

            # toggle flag
        if($_ =~ $PATCH_REGEX) {
            if($in_patch) {
                # End line
            } else {
                # Start Line
                $text_cb->($self, $text);
                $start_pos = $pos - length $_;
                $header = $_;
            }
            $text = "";
            $in_patch = ($in_patch xor 1);
        }
    }

    close FILE;

    $text_cb->($self, $text) if length $text;

    $self->unlock();
    return 1;
}

###########################################
sub patch_marker {
###########################################
    my($self, $method) = @_;

    return "#" .
           "(Config::Patch-" .
           "$self->{key}-" .
           "$method)" .
           "\n";
}

###########################################
sub replace_marker {
###########################################

    return "#" .
           "(Config::Patch::replace)";
}

###############################################
sub blurt {
###############################################
    my($data, $file) = @_;
    open FILE, ">$file" or LOGDIE "Cannot open $file ($!)";
    print FILE $data;
    close FILE;
}

###############################################
sub slurp {
###############################################
    my($file) = @_;

    local $/ = undef;
    open FILE, "<$file" or LOGDIE "Cannot open $file ($!)";
    my $data = <FILE>;
    close FILE;

    return $data;
}

1;

__END__

=head1 NAME

Config::Patch - Patch configuration files and unpatch them later

=head1 SYNOPSIS

    use Config::Patch;

    my $patcher = Config::Patch->new( 
        file => "/etc/syslog.conf",
        key  => "mypatch", 
    );

        # Append a patch:
    $patcher->append(q{
        # Log my stuff
        my.*         /var/log/my
    });

        # Appends the following to /etc/syslog.conf:
        *-------------------------------------------
        | ...
        | #(Config::Patch-mypatch-append)
        | # Log my stuff
        | my.*         /var/log/my
        | #(Config::Patch-mypatch-append)
        *-------------------------------------------

    # later on, to remove the patch:
    $patcher->remove();

=head1 DESCRIPTION

C<Config::Patch> helps changing configuration files, remembering the changes,
and undoing them if necessary. 

Every change (patch) is marked by a I<key>, which must be unique for the
change, in order allow undoing it later on.

To facilitate its usage, C<Config::Patch> comes with a command line script
that performs all functions:

        # Append a patch
    echo "my patch text" | config-patch -a -k key -f textfile

        # Patch a file by search-and-replace
    echo "none:" | config-patch -s 'all:.*' -k key -f config_file

        # Comment out sections matched by a regular expression:
    config-patch -c '(?ms-xi:^all:.*?\n\n)' -k key -f config_file


        # Remove a previously applied patch
    config-patch -r -k key -f textfile

Note that 'patch' doesn't refer to a patch in the format used by the I<patch>
program, but to an arbitrary section of text inserted into a file. Patches
are line-based, C<Config::Patch> always adds/removes entire lines.

The only requirement is that lines starting with a # character 
are comment lines. 
Other than that, C<Config::Patch> is format-agnostic. 
If you need to pay attention
to the syntax of the configuration file to be patched, create a subclass
of C<Config::Patch> and put the format specific logic there.

You can only patch a file I<once> with a given key. Note that a single
patch might result in multiple patched sections within a file 
if you're using the C<replace()> or C<comment_out()> methods.

To apply different patches to the same file, use different keys. They
can be can rolled back separately.

=head1 METHODS

=over 4

=item C<$patcher = Config::Patch-E<gt>new(file =E<gt> $file, key =E<gt> $key)>

Creates a new patcher object. Optionally, exclusive updates are ensured
by flocking if the C<flock> parameter is set to 1:

    my $patcher = Config::Patch->new(
        file  => $file, 
        key   => $key,
        flock => 1,
    );

=item C<$patcher-E<gt>append($textstring)>

Appends a text string to the config file.

=item C<$patcher-E<gt>remove()>

Remove a previously applied patch. 
The patch key has either been provided 
with the constructor call previously or can be 
supplied as C<key =E<gt> $key>.

=item C<$patcher-E<gt>patched()>

Checks if a patch with the given key was applied to the file already.
The patch key has either been provided 
with the constructor call previously or can be 
supplied as C<key =E<gt> $key>.

=item C<$patcher-E<gt>replace($search, $replace)>

Patches by searching for a given pattern $search (regexp) and replacing
it by the text string C<$replace>. Example:

        # Replace the 'all:' target in a Makefile and all 
        # of its production rules by a dummy rule.
    $patcher->replace(qr(^all:.*?\n\n)sm, 
                      "all:\n\techo 'all is gone!'\n");

Note that the replace command will replace I<the entire line> if it
finds that a regular expression is matching a partial line.

CAUTION: Make sure your C<$search> patterns only cover the areas
you'd like to replace. Multiple matches within one line are ignored,
and so are matches that overlap with areas patched with different
keys (I<forbidden zones>).

=item C<$patcher-E<gt>comment_out($search)>

Patches by commenting out config lines matching the regular expression
C<$search>. Example:

        # Remove the 'all:' target and its production rules
        # from a makefile
    $patcher->comment_out(qr(^all:.*?\n\n)sm);

Commenting out is just a special case of C<replace()>. Check its
documentation for details.

=item C<$patcher-E<gt>key($key)>

Set a new patch key for applying subsequent patches.

=item C<($arrayref, $hashref) = $patcher-E<gt>patches()>

Examines the file and locates all patches. 

It returns two results: 
C<$arrayref>, a reference to an array, mapping patch keys to the 
text of the patched sections:

    $arrayref = [ ['key1', 'patchtext1'], ['key2', 'patchtext2'],
                  ['key2', 'patchtext3'] ];

Note that there can be several patched sections appearing under 
the same patch key (like the two non-consecutive sections under
C<key2> above).

The second result is a reference C<$hashref> to a hash, holding all 
patch keys as keys. Its values are the number of patch sections
appearing under a given key.

=back

=head1 LIMITATIONS

C<Config::Patch> assumes that a hashmark (#) at the beginning of a line
in the configuration file marks a comment.

=head1 COPYRIGHT AND LICENSE

Copyright 2005 by Mike Schilli. This library is free software; you can
redistribute it and/or modify it under the same terms as Perl itself.

=head1 AUTHOR

2005, Mike Schilli <cpan@perlmeister.com>
