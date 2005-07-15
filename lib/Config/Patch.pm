###########################################
# Config::Patch -- 2005, Mike Schilli <cpan@perlmeister.com>
###########################################

###########################################
package Config::Patch;
###########################################

use strict;
use warnings;

our $VERSION = "0.01";

###########################################
sub new {
###########################################
    my($class, %options) = @_;

    my $self = {
        %options,
    };

    bless $self, $class;
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

=back

=head1 LIMITATIONS

C<Config::Patch> assumes that a hashmark (#) at the beginning of a line
in the configuration file marks a comment.

=head1 LEGALESE

Copyright 2005 by Mike Schilli, all rights reserved.
This program is free software, you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 AUTHOR

2005, Mike Schilli <cpan@perlmeister.com>
