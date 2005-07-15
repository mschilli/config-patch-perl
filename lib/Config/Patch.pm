###########################################
# Config::Patch -- 2005, Mike Schilli <cpan@perlmeister.com>
###########################################

###########################################
package Config::Patch;
###########################################

use strict;
use warnings;
use Sysadm::Install qw(:all);

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
sub remove {
###########################################
    my($self) = @_;

    my $new_content = "";

    $self->file_parse(
        sub { my($p, $k, $m, $t) = @_;
              if($k ne $self->{key}) {
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
        | #(Config::Patch-Append-mypatch)
        | # Log my stuff
        | my.*         /var/log/my
        | #(Config::Patch-Append-mypatch)
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
    config-patch -a -k key -f textfile

        # Remove a patch
    config-patch -r -k key

=head1 METHODS

=over 4

=item C<$patcher = Config::Patch-E<gt>new(file =E<gt> $file, key =E<gt> $key)>

Creates a new patcher object.

=item C<$patcher-E<gt>append($textstring)>

Appends a text string to the config file.

=item C<$patcher-E<gt>remove()>

Remove a previously applied patch.

=item C<$patcher-E<gt>patched()>

Checks if a patch with the given key was applied to the file already.

=item C<$patcher-E<gt>replace($search, $replace)>

Patches by searching for a given pattern $search (regexp) and replacing
it by C<$replace>.

=item C<$patcher-E<gt>comment_out($search)>

Patches by commenting out config lines matching the regular expression
C<$search>.

=item C<$hashref = $patcher-E<gt>patches()>

Returns a reference to a hash, mapping all patches within a file
by key.

=back

=head1 LIMITATIONS

C<Config::Patch> assumes that a hashmark (#) at the beginning of a line
in the configuration file marks a comment.

=head1 AUTHOR

2005, Mike Schilli <mschilli@yahoo-inc.com>
