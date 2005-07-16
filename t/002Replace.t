######################################################################
# Test suite for Config::Patch (replace functions)
# by Mike Schilli <cpan@perlmeister.com>
######################################################################

use warnings;
use strict;

use Test::More tests => 5;
use Config::Patch;

my $TDIR = ".";
$TDIR = "t" if -d "t";
my $TESTFILE = "$TDIR/testfile";

END { unlink $TESTFILE; }

BEGIN { use_ok('Config::Patch') };

my $TESTDATA = "abc\ndef\nghi\n";

####################################################
# Replace a line
####################################################
blurt($TESTDATA, $TESTFILE);

my $patcher = Config::Patch->new(
                  file => $TESTFILE,
                  key  => "foobarkey");

$patcher->replace(qr(def), "weird stuff\nin here!");
my $data = slurp($TESTFILE);
$data =~ s/^#.*\n//mg;
is($data, "abc\nweird stuff\nin here!\nghi\n", "content replaced");

$patcher->remove();
$data = slurp($TESTFILE);
is($data, "abc\ndef\nghi\n", "content restored");

####################################################
# Comment out a line
####################################################
blurt($TESTDATA, $TESTFILE);

$patcher = Config::Patch->new(
                  file => $TESTFILE,
                  key  => "foobarkey");

$patcher->comment_out(qr(def));
$data = slurp($TESTFILE);
$data =~ s/^#.*\n//mg;
is($data, "abc\nghi\n", "content commented out");

$patcher->remove();
$data = slurp($TESTFILE);
is($data, "abc\ndef\nghi\n", "content restored");

###############################################
sub blurt {
###############################################
    my($data, $file) = @_;
    open FILE, ">$file" or die "Cannot open $file ($!)";
    print FILE $data;
    close FILE;
}

###############################################
sub slurp {
###############################################
    my($file) = @_;

    local $/ = undef;
    open FILE, "<$file" or die "Cannot open $file ($!)";
    my $data = <FILE>;
    close FILE;

    return $data;
}
