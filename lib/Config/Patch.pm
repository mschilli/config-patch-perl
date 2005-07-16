###########################################
# Config::Patch -- 2005, Mike Schilli <cpan@perlmeister.com>
###########################################

###########################################
package Config::Patch;
###########################################

use strict;
use warnings;
use MIME::Base64;

our $VERSION     = "0.01";
our $PATCH_REGEX = qr{^#\(Config::Patch-(.*?)-(.*?)\)}m;

###########################################
sub new {
###########################################
    my($class, %options) = @_;

    my $self = {
        %options,
    };

    bless $self, $class;
}

###########################################
sub append {
###########################################
    my($self, $string) = @_;

    open FILE, ">>$self->{file}" or
        die "Cannot open $self->{file}";

    print FILE $self->patch_marker("append");
    print FILE $string;
    print FILE $self->patch_marker("append");

    close FILE;
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

    $self->file_parse(
        sub { my($p, $k, $m, $t) = @_;
              push @patches, [$k, $m, $t];
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

    if(ref($search) ne "Regexp") {
        die "replace: search parameter not a regex";
    }

    if(substr($replace, -1, 1) ne "\n") {
        $replace .= "\n";
    }

    open FILE, "<$self->{file}" or
        die "Cannot open $self->{file}";
    my $data = join '', <FILE>;
    close FILE;

    my $positions = full_line_match($data, $search);
    my @pieces    = ();
    my $rest      = $data;

    for my $pos (@$positions) {
        my($from, $to) = @$pos;
        my $before = substr($data, 0, $from);
        $rest      = substr($data, $to+1);
        my $patch  = $self->patch_marker("replace") .
                     $replace .
                     replstring_hide(substr($data, $from, $to - $from + 1)) .
                     $self->patch_marker("replace");

        push @pieces, $before, $patch;
    }

    push @pieces, $rest;
    $data = join '', @pieces;

    open FILE, ">$self->{file}" or
        die "Cannot open $self->{file}";
    print FILE $data;
    close FILE;

    return scalar @$positions;
}

###########################################
sub full_line_match {
###########################################
    my($string, $rex) = @_;

    # Try a regex match and if it succeeds, extend the match
    # to cover the full first and last line. Return a ref to
    # an array of from-to offsets of all (extended) matching
    # regions.
    my @positions = ();

    while($string =~ /($rex)/g) {
        my $first = pos($string) - length($1) - 1;
        my $last  = pos($string);

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

        push @positions, [$first, $last];
    }

    return \@positions;
}

###########################################
sub comment_out {
###########################################
    my($self, $search) = @_;
}

###########################################
sub remove {
###########################################
    my($self) = @_;

    my $new_content = "";

    $self->file_parse(
        sub { my($p, $k, $m, $t) = @_;
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
                  $new_content .= $t;
              }
            },
        sub { my($p, $t) = @_;
              $new_content .= $t;
            },
    );

    open FILE, ">$self->{file}" or
        die "Cannot open $self->{file} ($!)";
    print FILE $new_content;
    close FILE;
}

###########################################
sub file_parse {
###########################################
    my($self, $patch_cb, $text_cb) = @_;

    open FILE, "<$self->{file}" or
        die "Cannot open $self->{file}";

    my $in_patch = 0;
    my $patch    = "";
    my $text     = "";

    while(<FILE>) {
        $patch .= $_ if $in_patch and $_ !~ $PATCH_REGEX;

            # text line?
        if($_ !~ $PATCH_REGEX and !$in_patch) {
            $text .= $_;
        }

            # closing line of patch
        if($_ =~ $PATCH_REGEX and 
           $in_patch) {
            $patch_cb->($self, $1, $2, $patch);
            $patch = "";
        }

            # toggle flag
        if($_ =~ $PATCH_REGEX) {
            $text_cb->($self, $text) if length $text;
            $text = "";
            $in_patch = ($in_patch xor 1);
        }
    }

    close FILE;

    $text_cb->($self, $text) if length $text;

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

        # Remove a patch
    config-patch -r -k key -f textfile

Note that 'patch' doesn't refer to a patch in the format used by the I<patch>
program, but to an arbitrary section of text inserted into a file.

C<Config::Patch> is format-agnostic. The only requirement is that lines
starting with a # character are comment lines. If you need to pay attention
to the syntax of the configuration file to be patched, use a subclass
of C<Config::Patch>.

=head1 METHODS

=over 4

=item C<$patcher = Config::Patch-E<gt>new(file =E<gt> $file, key =E<gt> $key)>

Creates a new patcher object.

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

        # Remove the all: target and all its production 
        # commands from a Makefile
    $patcher->replace(qr(^all:.*?\n\n)sm,
                      "all:\n\n");

Note that the replace command will replace I<the entire line> if it
finds that the regular expression is matching.

CAUTION: Make sure that C<$search> doesn't match a section that contains
another patch already. C<Config::Patch> can't handle this case yet.

=item C<$patcher-E<gt>comment_out($search)>

Patches by commenting out config lines matching the regular expression
C<$search>. Example:

        # Remove the function 'somefunction'
        # commands from a Makefile
    $patcher->replace(qr(^all:.*?\n\n)sm,
                      "all:\n\n");

Note that the replace command will replace I<the entire line> if it
finds that the regular expression is matching.

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
